-- ZAŁADOWANIE DANYCH

-- sprawdzamy listę tabel w schemacie rasters
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'rasters';

-- podgląd typów kolumn w wybranej tabeli
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_schema='rasters' AND table_name='landsat8';

-- sprawdzamy metadane raster_columns
SELECT * FROM public.raster_columns;


-- TWORZENIE RASTRÓW Z ISTNIEJĄCYCH RASTRÓW I PRACA Z WEKTORAMI

-- wybieramy kafelki rastra, które przecinają się z wybraną geometrią (gmina Porto)
CREATE TABLE sanek.intersects AS  
SELECT a.rast, b.municipality
FROM rasters.dem AS a, vectors.porto_parishes AS b  
WHERE ST_Intersects(a.rast, b.geom) 
  AND b.municipality ILIKE 'porto';

-- dodajemy identyfikator kafelka
ALTER TABLE sanek.intersects
ADD COLUMN rid SERIAL PRIMARY KEY;

-- tworzymy indeks przestrzenny dla szybszych zapytań
CREATE INDEX idx_intersects_rast_gist 
ON sanek.intersects USING gist (ST_ConvexHull(rast));

-- dodajemy zestaw standardowych ograniczeń dla rastrów
SELECT AddRasterConstraints('sanek'::name, 'intersects'::name,'rast'::name);


-- ST_CLIP – wycinamy raster na podstawie granic poligonu
CREATE TABLE sanek.clip AS  
SELECT ST_Clip(a.rast, b.geom, true), b.municipality  
FROM rasters.dem AS a, vectors.porto_parishes AS b  
WHERE ST_Intersects(a.rast, b.geom) 
  AND b.municipality ILIKE 'PORTO';


-- ST_Union – łączymy wiele kafelków w jeden raster
CREATE TABLE sanek.union AS
SELECT ST_Union(ST_Clip(a.rast, b.geom, true))
FROM rasters.dem AS a, vectors.porto_parishes AS b
WHERE b.municipality ILIKE 'porto'
  AND ST_Intersects(b.geom, a.rast);


-- TWORZENIE RASTRÓW Z WEKTORÓW

-- ST_AsRaster – rasteryzacja geometrii na siatkę rastra referencyjnego
CREATE TABLE sanek.porto_parishes AS 
WITH r AS (SELECT rast FROM rasters.dem LIMIT 1)
SELECT ST_AsRaster(a.geom, r.rast, '8BUI', a.id, -32767) AS rast 
FROM vectors.porto_parishes AS a, r 
WHERE a.municipality ILIKE 'porto';

DROP TABLE sanek.porto_parishes;

-- tworzenie jednego rastra z wielu geometrii — po rasteryzacji łączymy kafelki
CREATE TABLE sanek.porto_parishes AS 
WITH r AS (SELECT rast FROM rasters.dem LIMIT 1)
SELECT ST_Union(ST_AsRaster(a.geom, r.rast, '8BUI', a.id, -32767)) AS rast 
FROM vectors.porto_parishes AS a, r 
WHERE a.municipality ILIKE 'porto';

DROP TABLE sanek.porto_parishes;

-- dzielenie dużego rastra na mniejsze fragmenty (tiling)
CREATE TABLE sanek.porto_parishes AS 
WITH r AS (SELECT rast FROM rasters.dem LIMIT 1)
SELECT ST_Tile(
    ST_Union(ST_AsRaster(a.geom, r.rast, '8BUI', a.id, -32767)),
    128, 128, true, -32767
) AS rast 
FROM vectors.porto_parishes AS a, r 
WHERE a.municipality ILIKE 'porto';


-- KONWERTOWANIE RASTRÓW NA WEKTORY

-- ST_Intersection – zwraca wektor z wartością pikseli wewnątrz poligonu
CREATE TABLE sanek.intersection AS  
SELECT 
  a.rid,
  (ST_Intersection(b.geom, a.rast)).geom,
  (ST_Intersection(b.geom, a.rast)).val 
FROM rasters.landsat8 AS a, vectors.porto_parishes AS b  
WHERE b.parish ILIKE 'paranhos' 
  AND ST_Intersects(b.geom, a.rast);

-- ST_DumpAsPolygons – konwersja pikseli rastra na poligony
CREATE TABLE sanek.dumppolygons AS 
SELECT 
  a.rid,
  (ST_DumpAsPolygons(ST_Clip(a.rast, b.geom))).geom,
  (ST_DumpAsPolygons(ST_Clip(a.rast, b.geom))).val 
FROM rasters.landsat8 AS a, vectors.porto_parishes AS b  
WHERE b.parish ILIKE 'paranhos' 
  AND ST_Intersects(b.geom, a.rast);


-- ANALIZA RASTRÓW

-- ST_Band – pobieramy wybrane pasmo rastra
CREATE TABLE sanek.landsat_nir AS 
SELECT rid, ST_Band(rast,4) AS rast 
FROM rasters.landsat8;

-- ST_Clip – wycięcie rastra dem dla konkretnej parafii
CREATE TABLE sanek.paranhos_dem AS 
SELECT a.rid, ST_Clip(a.rast, b.geom, true) AS rast 
FROM rasters.dem AS a, vectors.porto_parishes AS b 
WHERE b.parish ILIKE 'paranhos' AND ST_Intersects(b.geom,a.rast);

-- ST_Slope – obliczanie nachylenia terenu
CREATE TABLE sanek.paranhos_slope AS 
SELECT a.rid, ST_Slope(a.rast,1,'32BF','PERCENTAGE') AS rast 
FROM sanek.paranhos_dem AS a;

-- ST_Reclass – klasyfikacja wartości pikseli
CREATE TABLE sanek.paranhos_slope_reclass AS 
SELECT a.rid, ST_Reclass(a.rast,1,']0-15]:1,(15-30]:2,(30-9999:3','32BF',0) 
FROM sanek.paranhos_slope AS a;

-- ST_SummaryStats – statystyki pojedynczego rastra
SELECT st_summarystats(a.rast) AS stats 
FROM sanek.paranhos_dem AS a;

-- statystyki dla połączonego rastra
SELECT st_summarystats(ST_Union(a.rast)) 
FROM sanek.paranhos_dem AS a;

-- wybór konkretnych statystyk
WITH t AS (
  SELECT st_summarystats(ST_Union(a.rast)) AS stats 
  FROM sanek.paranhos_dem AS a
)
SELECT (stats).min, (stats).max, (stats).mean FROM t;

-- statystyki dla każdej parafii z osobna
WITH t AS (
  SELECT b.parish AS parish, 
         st_summarystats(ST_Union(ST_Clip(a.rast, b.geom,true))) AS stats 
  FROM rasters.dem AS a, vectors.porto_parishes AS b 
  WHERE b.municipality ILIKE 'porto' AND ST_Intersects(b.geom,a.rast) 
  GROUP BY b.parish
)
SELECT parish, (stats).min, (stats).max, (stats).mean FROM t;

-- ST_Value – odczyt wartości pikseli w punktach
SELECT b.name, st_value(a.rast, (ST_Dump(b.geom)).geom) 
FROM rasters.dem a, vectors.places AS b 
WHERE ST_Intersects(a.rast,b.geom) 
ORDER BY b.name;


-- TPI – topographic position index
CREATE TABLE sanek.tpi30 AS 
SELECT ST_TPI(a.rast,1) AS rast 
FROM rasters.dem a;

CREATE INDEX idx_tpi30_rast_gist ON sanek.tpi30 
USING gist (ST_ConvexHull(rast));

SELECT AddRasterConstraints('sanek','tpi30','rast');

-- TPI dla obszaru Porto
CREATE TABLE sanek.tpi30_porto AS 
SELECT ST_TPI(a.rast,1) AS rast 
FROM rasters.dem AS a, vectors.porto_parishes AS b  
WHERE ST_Intersects(a.rast, b.geom) AND b.municipality ILIKE 'porto';

CREATE INDEX idx_tpi30_porto_rast_gist ON sanek.tpi30_porto 
USING gist (ST_ConvexHull(rast));

SELECT AddRasterConstraints('sanek','tpi30_porto','rast');


-- ALGEBRA MAP – obliczanie NDVI

-- NDVI z wyrażenia algebraicznego
CREATE TABLE sanek.porto_ndvi AS  
WITH r AS (
  SELECT a.rid, ST_Clip(a.rast, b.geom,true) AS rast 
  FROM rasters.landsat8 AS a, vectors.porto_parishes AS b 
  WHERE b.municipality ILIKE 'porto' AND ST_Intersects(b.geom,a.rast)
)
SELECT r.rid,
       ST_MapAlgebra(
          r.rast, 1,
          r.rast, 4,
          '([rast2.val] - [rast1.val]) / ([rast2.val] + [rast1.val])::float',
          '32BF'
       ) AS rast
FROM r;

CREATE INDEX idx_porto_ndvi_rast_gist ON sanek.porto_ndvi 
USING gist (ST_ConvexHull(rast));

SELECT AddRasterConstraints('sanek','porto_ndvi','rast');


-- NDVI z funkcją zwrotną
CREATE OR REPLACE FUNCTION sanek.ndvi(
  value double precision[][][],
  pos integer[][],
  VARIADIC userargs text[]
)
RETURNS double precision AS
$$
BEGIN
  RETURN (value[2][1][1] - value[1][1][1]) /
         (value[2][1][1] + value[1][1][1]);
END;
$$ LANGUAGE plpgsql IMMUTABLE COST 1000;

CREATE TABLE sanek.porto_ndvi2 AS  
WITH r AS (
  SELECT a.rid, ST_Clip(a.rast, b.geom,true) AS rast 
  FROM rasters.landsat8 AS a, vectors.porto_parishes AS b 
  WHERE b.municipality ILIKE 'porto' AND ST_Intersects(b.geom,a.rast)
)
SELECT r.rid,
       ST_MapAlgebra(
         r.rast, ARRAY[1,4],
         'sanek.ndvi(double precision[], integer[], text[])'::regprocedure,
         '32BF'
       ) AS rast
FROM r;

CREATE INDEX idx_porto_ndvi2_rast_gist ON sanek.porto_ndvi2 
USING gist (ST_ConvexHull(rast));

SELECT AddRasterConstraints('sanek','porto_ndvi2','rast');


-- EKSPORT DANYCH

-- ST_AsTiff – tworzymy binarny TIFF
SELECT ST_AsTiff(ST_Union(rast))
FROM sanek.porto_ndvi;

-- ST_AsGDALRaster – eksport w dowolnym formacie GDAL + kompresja
SELECT ST_AsGDALRaster(
    ST_Union(rast),
    'GTiff',
    ARRAY['COMPRESS=DEFLATE','PREDICTOR=2','ZLEVEL=9']
)
FROM sanek.porto_ndvi;

-- lista wspieranych formatów GDAL
SELECT ST_GDALDrivers();

-- zapis rastra jako Large Object i eksport do pliku
CREATE TABLE tmp_out AS 
SELECT lo_from_bytea(
    0,
    ST_AsGDALRaster(
        ST_Union(rast),'GTiff',
        ARRAY['COMPRESS=DEFLATE','PREDICTOR=2','ZLEVEL=9']
    )
) AS loid
FROM sanek.porto_ndvi;

SELECT lo_export(loid, 'C:\\Temp\\myraster.tiff')
FROM tmp_out;

SELECT lo_unlink(loid)
FROM tmp_out;

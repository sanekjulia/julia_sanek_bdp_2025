-- Zadanie 1
-- Budynki nowe lub zmienione w 2019 względem 2018
CREATE TABLE renovated_buildings AS
SELECT b2019.*
FROM public.t2019_kar_buildings b2019
LEFT JOIN public.t2018_kar_buildings b2018
       ON b2019.polygon_id = b2018.polygon_id
          AND ST_Equals(b2019.geom, b2018.geom)
WHERE b2018.polygon_id IS NULL;

-- Zadanie 2
-- poi do 500m od budynkow
CREATE TEMP TABLE new_pois AS
SELECT p19.*
FROM public.t2019_kar_poi_table p19
WHERE NOT EXISTS (
    SELECT 1
    FROM public.t2018_kar_poi_table p18
    WHERE ST_Equals(p19.geom, p18.geom)
);

CREATE TABLE pois_500m_buildings AS
SELECT np.type, np.poi_id
FROM new_pois np
JOIN renovated_buildings rb
ON ST_DWithin(np.geom, rb.geom, 500);

-- zliczenie kategorii
SELECT type, COUNT(*) AS poi_count
FROM pois_500m_buildings
GROUP BY type
ORDER BY poi_count DESC;

-- Zadanie 3 zmiana ukladu wspolrzednych na DHDN.Berlin/Cassini - EPSG:3068
CREATE TABLE streets_reprojected AS
SELECT 
    *,
    ST_Transform(geom, 3068) AS geom_reprojected
FROM public.t2019_kar_streets;

-- Zadanie 4,5,6 - punkty
CREATE TABLE input_points (
    id SERIAL PRIMARY KEY,
    geom geometry(Point, 4326)  
);

INSERT INTO input_points (geom)
VALUES
    (ST_SetSRID(ST_MakePoint(8.36093, 49.03174), 4326)),
    (ST_SetSRID(ST_MakePoint(8.39876, 49.00644), 4326));

ALTER TABLE input_points ADD COLUMN geom_3068 geometry(Point, 3068);

UPDATE input_points
SET geom_3068 = ST_Transform(geom, 3068);

-- skrzyżowania w odleglosci do 200m
WITH input_line AS (
    SELECT 
        ST_MakeLine(geom_3068 ORDER BY id) AS geom
    FROM input_points
),
reprojected_nodes AS (
    SELECT 
        node_id,
        ST_Transform(geom, 3068) AS geom_3068
    FROM public.t2019_kar_street_node
)
SELECT n.node_id
FROM reprojected_nodes n
JOIN input_line l
ON ST_DWithin(n.geom_3068, l.geom, 200);

-- Zadanie 7 - zliczone sklepy sportowe w odl 300m do parków
SELECT COUNT(DISTINCT p.poi_id) AS sporting_goods_near_parks
FROM public.t2019_kar_poi_table p
JOIN public.t2019_kar_land_use_a l
  ON ST_DWithin(
       ST_Transform(p.geom, 3068),  
       ST_Transform(l.geom, 3068),
       300                           
     )
WHERE p.type = 'Sporting Goods Store'
  AND l.type = 'Park (City/County)';

-- Zadanie 8 - przeciecia rzek i torów (mosty)
CREATE TABLE public.t2019_kar_bridges AS
SELECT 
    ST_Intersection(r.geom, w.geom) AS geom
FROM public.t2019_kar_railways r
JOIN public.t2019_kar_water_lines w
    ON ST_Intersects(r.geom, w.geom)
WHERE GeometryType(ST_Intersection(r.geom, w.geom)) IN ('POINT', 'MULTIPOINT');

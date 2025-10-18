--- a) suma dlugosci drog
SELECT 
    SUM(ST_Length(geom)) AS total_length
FROM roads;

---b) geometria wkt, pole i obwod budynku A
SELECT 
    ST_AsText(geom) AS wkt,
    ST_Area(geom) AS pole,
    ST_Perimeter(geom) AS obwod
FROM buildings
WHERE name = 'Building A';

--- c) pola alfabetycznie
SELECT 
    name,
    ST_Area(geom) AS pole
FROM buildings
ORDER BY name;

--- d) nazwy i obwody budynkow o najwiekszej powierzchni
SELECT 
    name,
    ST_Perimeter(geom) AS obwod
FROM buildings
ORDER BY ST_Area(geom) DESC
LIMIT 2;

--- e) odl. od budynku B do punktu K
SELECT 
    ST_Distance(b.geom, p.geom) AS odleglosc_min
FROM buildings b
JOIN poi p ON p.name = 'K'
WHERE b.name = 'Building C';

--- f) pole czesci budynku C  dalej niż 0.5  od budynku B

SELECT 
    ST_Area(ST_Difference(
            c.geom,
            ST_Buffer(b.geom, 0.5)
        )
    ) AS pole_czesci
FROM buildings c, buildings b
WHERE c.name = 'Building C' AND b.name = 'Building B';

--- g) budynki - centroid powyzej drogi X
SELECT 
    b.name
FROM buildings b
JOIN roads r ON r.name = 'RoadX'
WHERE ST_Y(ST_Centroid(b.geom)) > ST_Y(ST_Centroid(r.geom));

--- h) pole budynku C oddzielne od podanego poligonu

SELECT 
    ST_Area(
        ST_SymDifference(
            b.geom,
            ST_GeomFromText('POLYGON((4 7, 6 7, 6 8, 4 8, 4 7))')
        )
    ) AS pole_C
FROM buildings b
WHERE b.name = 'Building C';

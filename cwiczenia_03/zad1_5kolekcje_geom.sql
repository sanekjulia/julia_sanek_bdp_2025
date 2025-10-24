-- ZADANIE 1
DROP TABLE IF EXISTS obiekty;

CREATE TABLE obiekty (
    id SERIAL PRIMARY KEY,
    nazwa TEXT,
    geom GEOMETRY
);

INSERT INTO obiekty (nazwa, geom)
VALUES (
  'obiekt1',
  ST_LineToCurve(
    ST_GeomFromText('LINESTRING(0 1, 1 1, 2 0, 3 1, 4 2, 5 1, 6 1)')
  )
);

INSERT INTO obiekty (nazwa, geom)
VALUES (
  'obiekt2',
  ST_LineToCurve(
    ST_GeomFromText('POLYGON((
      10 2, 10 6, 14 6, 16 4, 14 2, 13 0, 11 2, 10 2
    ),
    (11 2, 12 3, 13 2, 12 1, 11 2))')
  )
);

INSERT INTO obiekty (nazwa,geom)
VALUES
(
'obiekt3',
  ST_GeomFromEWKT('POLYGON((
	7 15,
	10 17,
	12 13,
	7 15
  ))')
);
INSERT INTO obiekty (nazwa, geom)
VALUES (
  'obiekt4',
  ST_LineFromMultiPoint(
    ST_GeomFromText('MULTIPOINT(
      (20 20),
      (20.5 19.5),
      (22 19),
      (26 21),
      (25 22),
      (27 24),
      (25 25)
    )')
  )
);
INSERT INTO obiekty (nazwa, geom)
VALUES (
  'obiekt5',
  ST_GeomFromEWKT('MULTIPOINTZ((38 32 234), (30 30 59))')
);

INSERT INTO obiekty (nazwa, geom)
VALUES (
  'obiekt6',
  ST_GeomFromEWKT('GEOMETRYCOLLECTION(
    POINT(4 2),
    LINESTRING(1 1, 3 2)
  )')
);

---2 pole bufora w okol najkrotszej linii
SELECT 
    ST_Area(
        ST_Buffer(
            ST_ShortestLine(
                (SELECT geom FROM obiekty WHERE nazwa = 'obiekt3'),
                (SELECT geom FROM obiekty WHERE nazwa = 'obiekt4')
            ),
            5
        )
    ) AS pole_bufora;

---3 zamiana obiektu 4 na poligon
UPDATE obiekty
SET geom = ST_MakePolygon(
              ST_LineFromText('LINESTRING(
                  20 20,
                  20.5 19.5,
                  22 19,
                  26 21,
                  25 22,
                  27 24,
                  25 25,
                  20 20
              )')
          )
WHERE nazwa = 'obiekt4';

---4 obiekt 7
INSERT INTO obiekty (nazwa, geom)
SELECT
    'obiekt7',
    ST_Union(geom)
FROM obiekty
WHERE nazwa IN ('obiekt3', 'obiekt4');

---5 pole buforow 5 jednostek - wokol obiektow bez lukow
SELECT SUM(ST_Area(ST_Buffer(geom, 5))) AS suma_pole_buforow
FROM obiekty
WHERE NOT ST_HasArc(geom);


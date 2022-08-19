-- Prepare MM roadlink table.

-- generate pgRouting compatible source and target fields
alter table os_mm_roads.roadlink
add column source int8,
add column target int8; 

update os_mm_roads.roadlink
set source = ltrim(startnodehref, '#osgb')::int8,
target = ltrim(endnodehref, '#osgb')::int8;

-- deal with issue of pseudo nodes (type: grade separation)
-- node id is localid (change from charvar to bigint).

alter table os_mm_roads.roadnode
alter column localid type int8 using localid::int8;

-- create lookup table of the pseudo grade separation nodes with newid
create table os_mm_roads.pseudo_nodes_gs as
select localid, (localid + 3000000000000000) AS newid from os_mm_roads.roadnode where formofroadnodetitle = 'pseudo node' and classification = 'Grade Separation';

-- update roadlink table
update os_mm_roads.roadlink a
set source = b.newid
from os_mm_roads.pseudo_nodes_gs b
where a.startgradeseparation = 1 and a.source = b.localid;

update os_mm_roads.roadlink a
set target = b.newid
from os_mm_roads.pseudo_nodes_gs b
where a.endgradeseparation = 1 and a.target = b.localid;

-- prepare for directed
-- based on directionalitytitle:
-- 'both directions'
-- 'in direction'
-- 'in opposite direction'

alter table os_mm_roads.roadlink
add column cost real,
add column reverse_cost real;

update os_mm_roads.roadlink
set cost = length
where directionalitytitle in ('both directions', 'in direction');

update os_mm_roads.roadlink
set cost = 1000000
where directionalitytitle = 'in opposite direction';

update os_mm_roads.roadlink
set reverse_cost = length
where directionalitytitle in ('both directions', 'in opposite direction');

update os_mm_roads.roadlink
set reverse_cost= 1000000
where directionalitytitle = 'in direction';


SELECT
	X.*,
	A.formofway,
	A.name 
FROM
	pgr_dijkstra('SELECT ogc_fid as id, source, target, cost, reverse_cost FROM os_mm_roads.roadlink', 4000000023134762, 4000000023104587, true) as X
	LEFT JOIN (select ogc_fid, formofway, roadname as name from os_mm_roads.roadlink) AS A ON A.ogc_fid = X.edge 
ORDER BY
	seq;
	




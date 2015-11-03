# This R Script will automatically generate drive distance or drive time based buffers
# for a given set of start nodes, using the pgRouting functions: pgr_drivingDistance and pgr_pointsASPolygon.
# The polygons are written to a PostgreSQL table. It requires suitably prepared database tables derived from
# the Ordnance Survey Open Roads dataset, but could be modified to use any other suitably prepared routable network.

# Load required libraries
library(RPostgreSQL)

# define the database connection - amend as required
drv <- dbDriver("PostgreSQL")
con <-
  dbConnect(
    drv, host = "localhost", user = "postgres", password = "password", dbname =
      "spatial"
  )

# create a table called drivetime_polygons which will store the drive time polygons
query <-
  paste(
    "CREATE TABLE openroads.drivetime_polygons(gid serial NOT NULL PRIMARY KEY, startnode integer)"
  )
dbGetQuery(con, query)

# add geometry column with CRS 27700 - amend CRS as required
query <-
  paste(
    "SELECT AddGeometryColumn('openroads','drivetime_polygons','geom', 27700, 'polygon', 2)"
  )
dbGetQuery(con, query)


# set a vector of desired start nodes - amend as required
startnodes <- c(6663798, 8045423, 7526814, 6661546)

# initiate windows progress bar
pb <- winProgressBar(
  title = "progress bar", min = 0,
  max = length(startnodes), width = 300
)

# set the cost field and cost value options here rather than modifying the query - amend as required

# costColumn - can be cost_len or cost_time
costField <- 'cost_len'

# cost value in units of the cost column - meters for cost_len or minutes for cost_time
costValue <- 10000

# loop through the startnodes and create temporary table to hold the nodes

for (i in 1:length(startnodes)) {
  # create the temp table
  query2 <-
    paste(
      "CREATE TEMP TABLE nodes AS
      SELECT a.seq, a.id1, a.cost, b.geom from pgr_drivingDistance('SELECT
      gid AS id,
      source::integer,
      target::integer,",
      costField,
      "::double precision AS cost
      FROM openroads.roadlink',",
      startnodes[i],
      ",",
      costValue,
      ", false, false) AS a
      INNER JOIN openroads.roadnode as b ON b.identifier = a.id1;", sep = ""
      )
  # this next line just removes line breaks from the query - allows the query to be written over mutiple lines as above
  query2 <- gsub(pattern = '\\s', replacement = " ", x = query2)
  dbGetQuery(con, query2)
  # pgr_pointsASPolygon requires at least 3 points, so do a row count of the nodes table
  count_rows <- dbGetQuery(con, "select count(*) from nodes")
  if (count_rows > 2) {
    # generate the polygon and insert into drivetime_polygons table
    query3 <-
      paste(
        "INSERT INTO openroads.drivetime_polygons (geom, startnode)
        VALUES (
        (ST_SetSRID(pgr_pointsAsPolygon('SELECT seq::integer AS id, st_x(geom)::float as x, st_y(geom)::float as y FROM nodes'),27700)),
        ('", startnodes[i], "'))", sep = ""
      )
    query3 <- gsub(pattern = '\\s', replacement = " ", x = query3)
    dbGetQuery(con, query3)
  }
  # set progress bar
  setWinProgressBar(pb, i, title = paste(round(i / length(startnodes) * 100, 0),"% done"))
  # drop the temp table
  dbGetQuery(con, "DROP TABLE nodes")
}

# close the windows progress bar
close(pb)
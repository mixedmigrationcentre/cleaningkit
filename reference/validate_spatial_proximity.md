# Validate Spatial Proximity Between Surveys

Checks how close together surveys were conducted by computing the
geodesic distance between every pair of GPS coordinates and grouping
nearby surveys into spatial clusters. Each survey that belongs to a
cluster of two or more surveys within `distance_threshold_m` metres is
flagged with one log row, regardless of how many other surveys are in
the same cluster.

## Usage

``` r
validate_spatial_proximity(
  dataset,
  lat_column = "_location_latitude",
  lon_column = "_location_longitude",
  uuid_column = "_uuid",
  enumerator_column = "username",
  log_name = "spatial_proximity_log",
  distance_threshold_m = 50,
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe or a list containing a dataframe named `checked_dataset`.

- lat_column:

  Name of the latitude column (decimal degrees, WGS84). Default
  `"_location_latitude"`.

- lon_column:

  Name of the longitude column (decimal degrees, WGS84). Default
  `"_location_longitude"`.

- uuid_column:

  Name of the unique-identifier column. Default `"_uuid"`.

- enumerator_column:

  Name of the enumerator column. When supplied, clustering is performed
  within each enumerator's surveys only. When `NULL`, all surveys are
  compared globally. Default `"username"`.

- log_name:

  Name of the log element in the returned list. Default
  `"spatial_proximity_log"`.

- distance_threshold_m:

  Numeric. Two surveys are considered in proximity if they are within
  this many metres of each other. Default `50`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  treated as the ONA label/description row and excluded.

## Value

A list containing:

- checked_dataset:

  The original dataset, unchanged.

- \<log_name\>:

  A dataframe with one row per survey that belongs to a spatial cluster,
  with columns `uuid`, `old_value` (coordinates as `"lat, lon"`),
  `question` (`"gps_location"`), `issue` (cluster size, nearest
  neighbour distance, and all cluster member UUIDs), and `check_binding`
  (shared by all surveys in the same cluster).

## Details

**Why clusters instead of pairs?** A naive pairwise approach flags every
combination of nearby surveys: a camp with 20 surveys within 50 m of
each other produces 20×19/2 = 190 pairs and 380 log rows. The cluster
approach groups all transitively connected surveys (connected components
in the proximity graph) and emits exactly one row per survey in a
cluster, so the same 20 surveys produce 20 rows. The output size is
therefore proportional to the number of suspicious surveys, not to the
square of them.

**What is a cluster?** Two surveys are *directly* connected if they are
within `distance_threshold_m` metres of each other. A cluster is the
maximal set of surveys where every survey is reachable from every other
via a chain of direct connections (a connected component in graph
terms). A cluster of size 1 is not flagged.

**Enumerator grouping:** When `enumerator_column` is supplied,
clustering is performed independently within each enumerator's surveys.
A proximity flag is only raised when the same enumerator collected
multiple nearby interviews. When `enumerator_column` is `NULL`, all
surveys are compared globally.

**check_binding:** All surveys in the same cluster share one
`check_binding` value (`"proximity ~/~ <cluster_id>"`), so they are
coloured as a group in the review workbook.

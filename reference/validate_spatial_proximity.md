# Validate Spatial Proximity Between Surveys

Checks how close together surveys were conducted by computing the
geodesic distance between every pair of GPS coordinates. Flags pairs
whose interviews were conducted within `distance_threshold_m` metres of
each other, which may indicate that surveys were collected from the same
household or location rather than from distinct respondents.

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

  Name of the enumerator column. When supplied, proximity is checked
  only within each enumerator's surveys. When `NULL`, all surveys are
  compared globally. Default `"username"`.

- log_name:

  Name of the log element in the returned list. Default
  `"spatial_proximity_log"`.

- distance_threshold_m:

  Numeric. Surveys closer than this many metres are flagged. Default
  `50` (roughly the footprint of one household compound).

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  treated as the ONA label/description row and excluded from all
  calculations.

## Value

A list containing:

- checked_dataset:

  The original dataset, unchanged.

- \<log_name\>:

  A dataframe with columns `uuid`, `old_value` (the coordinate pair as
  `"lat, lon"`), `question` (`"gps_location"`), `issue` (distance in
  metres to the nearest flagged neighbour, with enumerator and paired
  uuid), and `check_binding` (shared between both surveys in a flagged
  pair).

## Details

When `enumerator_column` is supplied, pairwise distances are computed
only within each enumerator's own surveys — a proximity flag is only
raised if the same enumerator conducted two nearby interviews. When
`enumerator_column` is `NULL`, all surveys in the dataset are compared
against each other regardless of who collected them.

GPS coordinates from ONA exports are decimal degrees on the WGS84 datum
(EPSG:4326). Distances are computed as geodesic metres using
[`sf::st_distance()`](https://r-spatial.github.io/sf/reference/geos_measures.html),
which accounts for the curvature of the earth.

Each flagged *pair* produces two log rows (one per survey), sharing a
`check_binding` so both surveys are coloured as a group in the review
workbook. A survey that is close to multiple others produces multiple
pairs, each with its own binding.

Surveys with missing or non-numeric coordinates are excluded from
comparison and a warning is issued with the count.

# Validate Interview Location Against Claimed Country and City

Checks whether the GPS coordinates recorded during an in-person
interview are plausibly consistent with the country and city the
respondent claims the interview was conducted in. Two independent checks
are performed:

## Usage

``` r
validate_interview_location(
  dataset,
  uuid_column = "_uuid",
  lat_column = "_location_latitude",
  lon_column = "_location_longitude",
  country_question = "Q13",
  city_question = "Q14",
  log_name = "interview_location_log",
  city_radius_km = 75,
  check_country = TRUE,
  check_city = TRUE,
  flag_missing_gps = TRUE,
  nominatim_delay_s = 1,
  skip_label_row = TRUE
)
```

## Arguments

- dataset:

  A dataframe or a list containing a dataframe named `checked_dataset`.

- uuid_column:

  Name of the uuid column. Default `"_uuid"`.

- lat_column:

  Name of the GPS latitude column. Default `"_location_latitude"`.

- lon_column:

  Name of the GPS longitude column. Default `"_location_longitude"`.

- country_question:

  Column containing the claimed country of interview. Default `"Q13"`.

- city_question:

  Column containing the claimed city of interview. Default `"Q14"`.

- log_name:

  Name of the log element in the returned list. Default
  `"interview_location_log"`.

- city_radius_km:

  Maximum acceptable distance in kilometres between the GPS point and
  the geocoded city centre. Default `75` — large enough to cover outer
  suburbs of most cities while still detecting GPS points that are
  clearly in the wrong location. Adjust per context: use a smaller value
  (e.g. 30) for small cities, larger (e.g. 150) for sprawling
  metropolitan areas.

- check_country:

  Logical. If `TRUE` (the default), perform the country-level polygon
  containment check. Requires the `rnaturalearthdata` and `sf` packages.

- check_city:

  Logical. If `TRUE` (the default), perform the city-level distance
  check via Nominatim geocoding. Requires an internet connection.

- flag_missing_gps:

  Logical. If `TRUE` (the default), surveys with missing or invalid GPS
  coordinates are flagged in the log.

- nominatim_delay_s:

  Numeric. Seconds to wait between Nominatim API requests. Must be at
  least 1 to comply with the usage policy. Default `1`.

- skip_label_row:

  Logical. If `TRUE` (the default), the first row of the dataset is
  treated as the ONA label/description row and excluded from all checks.

## Value

A list containing:

- checked_dataset:

  The original dataset, unchanged.

- \<log_name\>:

  A dataframe with columns `uuid`, `old_value` (the GPS coordinates or
  "NA"), `question` (the relevant column), `issue` (description of the
  problem), `check_binding` (shared within each check type per survey).
  Three possible `check_binding` prefixes: `"location_missing_gps"`,
  `"location_country"`, `"location_city"`.

## Details

1.  **Country check** (requires `rnaturalearthdata`): tests whether the
    GPS point falls inside the polygon of the claimed country.

2.  **City check**: geocodes each unique city+country combination in the
    dataset once via the Nominatim/OpenStreetMap API, then checks
    whether the GPS point is within `city_radius_km` kilometres of the
    city centre. Requires an internet connection.

Surveys with no GPS coordinates are flagged separately — in an in-person
survey a missing GPS point may indicate the interview was not actually
conducted at the claimed location, or that the device GPS was disabled.

**Nominatim usage policy:** this function respects the [Nominatim
Acceptable Use
Policy](https://operations.osmfoundation.org/policies/nominatim/) by
geocoding only unique city+country pairs (not every row), adding a
1-second delay between requests, and identifying itself via the
`User-Agent` header. For large datasets with many unique city
combinations, geocoding may take a few minutes.

**City matching**: city names are passed to Nominatim as-is from the
dataset. Spelling must be in English and must reasonably match OSM data
(e.g. "Kampala", "Nairobi", "Addis Ababa"). Minor variations are usually
handled by OSM's search engine. If a city cannot be geocoded, those
surveys are excluded from the city check and a warning is issued.

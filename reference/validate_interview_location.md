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
  border_tolerance_km = 10,
  check_country = TRUE,
  check_city = TRUE,
  flag_missing_gps = TRUE,
  treat_blank_gps_as_phone = TRUE,
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

- border_tolerance_km:

  Numeric. How far outside the claimed country's border a GPS point may
  fall before it is flagged, in kilometres. Absorbs ordinary GPS error
  and coarse border geometry. Default `10`.

- check_country:

  Logical. If `TRUE` (the default), perform the country-level polygon
  containment check. Requires the `rnaturalearthdata` and `sf` packages.

- check_city:

  Logical. If `TRUE` (the default), perform the city-level distance
  check via Nominatim geocoding. Requires an internet connection and the
  `httr` and `jsonlite` packages.

- flag_missing_gps:

  Logical. If `TRUE` (the default), surveys whose GPS coordinates are
  present but unusable are flagged in the log. Phone interviews (both
  coordinate columns empty) are governed by `treat_blank_gps_as_phone`,
  not by this argument.

- treat_blank_gps_as_phone:

  Logical. If `TRUE` (the default), a survey with *both* coordinate
  columns empty is taken to be a phone interview and is excluded from
  every check, including the missing-GPS flag. Set to `FALSE` for a
  round known to be entirely in person, so that a completely absent
  geopoint is flagged instead.

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
    GPS point falls inside the polygon of the claimed country, allowing
    a small tolerance for points just outside the border.

2.  **City check**: geocodes each unique city+country combination in the
    dataset once via the Nominatim/OpenStreetMap API, then checks
    whether the GPS point is within `city_radius_km` kilometres of the
    city centre. Requires an internet connection.

**Phone interviews are skipped.** A survey conducted by phone records no
geopoint, so both coordinate columns come back empty. Those surveys are
identified up front and excluded from all three checks — there is
nothing to validate and flagging them would bury the real problems.
Surveys whose GPS is present but unusable are a different matter and are
still flagged: one coordinate filled and the other empty, non-numeric
text, out-of-range values, or the `(0, 0)` device default. Set
`treat_blank_gps_as_phone = FALSE` to flag fully-empty coordinates too,
which is appropriate for a round that was entirely face-to-face.

**Nominatim usage policy:** this function respects the [Nominatim
Acceptable Use
Policy](https://operations.osmfoundation.org/policies/nominatim/) by
geocoding only unique city+country pairs (not every row), adding a
1-second delay between requests, and identifying itself via the
`User-Agent` header. For large datasets with many unique city
combinations, geocoding may take a few minutes.

**City matching**: city names are passed to Nominatim as-is from the
dataset. Spelling must be in English and must reasonably match OSM data
(e.g. "Kampala", "Nairobi", "Addis Ababa"). Each pair is first tried as
a structured query (`city=` + `country=`); if that returns nothing the
pair is retried as a free-form query (`q="city, country"`), which
resolves many small towns, border crossings and settlements that are not
tagged as cities in OSM. If a pair still cannot be geocoded, those
surveys are excluded from the city check and a warning is issued.

**Country matching**: the claimed country is matched case-insensitively
against several Natural Earth name fields (`admin`, `name`, `name_long`,
`sovereignt`, `formal_en`, `name_en`) as well as the ISO2 and ISO3 code
columns, so either a country name or an ISO code works. A small alias
table covers common humanitarian variants (e.g. "DRC", "Ivory Coast",
"Syria", "UAE"). Field names in `rnaturalearthdata` are resolved
case-insensitively, so both the older lower-case and any upper-case
variants of the package are supported.

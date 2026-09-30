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
  location_column = "location",
  country_question = "Q13",
  city_question = "Q14",
  log_name = "interview_location_log",
  city_radius_km = 75,
  border_tolerance_km = 10,
  check_country = TRUE,
  check_city = TRUE,
  flag_missing_gps = TRUE,
  treat_blank_gps_as_phone = TRUE,
  use_location_fallback = TRUE,
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

- location_column:

  Name of the raw ONA geopoint column used as a fallback when
  `lat_column` / `lon_column` are unusable. The column holds all four
  geopoint components separated by spaces, in the order
  `"latitude longitude altitude precision"`, e.g.
  `"33.9820598 71.5482743 317.4000244140625 18.033"`. Default
  `"location"`. The column is optional: if it is absent from the dataset
  the fallback is simply not available.

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
  unusable are counted and reported as a console warning. They are
  *never* written to the cleaning log — the log carries only surveys
  that a check actually ran on and failed. Set to `FALSE` to suppress
  the warning as well. Phone interviews are governed by
  `treat_blank_gps_as_phone`, not by this argument.

- treat_blank_gps_as_phone:

  Logical. If `TRUE` (the default), a survey with *all* coordinate
  columns empty — `lat_column`, `lon_column` and `location_column` — is
  taken to be a phone interview and excluded from every check and from
  the unusable-GPS warning count. Set to `FALSE` for a round known to be
  entirely in person, so that a completely absent geopoint is counted as
  unusable instead.

- use_location_fallback:

  Logical. If `TRUE` (the default) and `location_column` is present in
  the dataset, any survey whose `lat_column` / `lon_column` pair is
  missing or invalid falls back to the first two space-separated values
  of `location_column`. Surveys whose split coordinates are already
  valid are left untouched.

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
  Two possible `check_binding` prefixes: `"location_country"` and
  `"location_city"`. Surveys with unusable GPS never appear — they are
  reported as a console warning instead (see `flag_missing_gps`).

## Details

1.  **Country check** (requires `rnaturalearthdata`): tests whether the
    GPS point falls inside the polygon of the claimed country, allowing
    a small tolerance for points just outside the border.

2.  **City check**: geocodes each unique city+country combination in the
    dataset once via the Nominatim/OpenStreetMap API, then checks
    whether the GPS point is within `city_radius_km` kilometres of the
    city centre. Requires an internet connection.

**Unusable GPS is reported, not logged.** A survey whose coordinates are
missing, non-numeric, out of range or the `(0, 0)` device default cannot
be checked against anything, so it produces no cleaning-log row. An
unusable geopoint is not itself an answer the enumerator can correct,
and logging one row per survey buried the genuine location problems
under hundreds of lines. Those surveys are counted and reported as a
console warning instead, and the log contains only surveys whose
coordinates were good enough for the country or city check to actually
run and fail. Set `flag_missing_gps = FALSE` to silence the warning too.

**Phone interviews are skipped.** A survey conducted by phone records no
geopoint, so the coordinate columns come back empty. Those surveys are
identified up front and excluded from every check and from the warning
count — there is nothing to validate. Set
`treat_blank_gps_as_phone = FALSE` to count fully-empty coordinates as
unusable instead, which is appropriate for a round that was entirely
face-to-face.

**Rounded or corrupted coordinate columns.** Opening an ONA export in
Excel frequently damages the split coordinate columns — the decimals are
rounded away, the value is re-read as a date or as scientific notation,
or the cell is emptied altogether. The raw geopoint column (`location`
by default) is normally left intact because Excel treats it as text.
When a survey's `lat_column` / `lon_column` pair fails validation, the
function therefore falls back to that column, taking its first two
space-separated values as latitude and longitude. The column holds the
four ONA geopoint components in the order
`"latitude longitude altitude precision"`, e.g.
`"33.9820598 71.5482743 317.4000244140625 18.033"`; altitude and
precision are ignored. Surveys whose split coordinates are already valid
are never overwritten, and the number of surveys rescued this way is
reported in a message. Set `use_location_fallback = FALSE` to disable.

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

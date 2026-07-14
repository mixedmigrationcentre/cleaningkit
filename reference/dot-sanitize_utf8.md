# Coerce a vector to valid UTF-8

Replaces invalid byte sequences so that openxlsx / stringi can measure
the string length. Non-character vectors are returned unchanged; factor
levels are cleaned in place.

## Usage

``` r
.sanitize_utf8(x)
```

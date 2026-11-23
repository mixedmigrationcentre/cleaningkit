# Options for Translating Other Responses

Settings used by
[`translate_other_responses()`](translate_other_responses.md) and by
`prepare_other_responses(translate = TRUE)`. The defaults are chosen to
stay well inside what Google's free translation service tolerates and to
send as little as possible; most users only set `cache_file`.

## Usage

``` r
ck_translate_options(
  mask_numbers = TRUE,
  cache_file = NULL,
  target_language = "en",
  pause = 0.5,
  max_retries = 4,
  retry_wait = 2,
  batch_size = 50,
  batch_chars = 4000,
  timeout = 30
)
```

## Arguments

- mask_numbers:

  Logical. If `TRUE` (the default), any run of five or more digits - a
  phone number, an ID, a bank or case number, even with spaces, dashes,
  brackets or a leading `+` - is replaced by `#####` before the text is
  sent. Shorter numbers such as ages or years written as two digits are
  kept, because they are rarely identifying and often matter for the
  meaning.

- cache_file:

  Optional path to an `.rds` file. Every text that has been translated
  is saved there (after each batch), and a later run only sends texts
  that are not in it yet. Use one cache per project; it contains the
  response texts, so keep it with the data and never commit or share it.
  `NULL` (the default) keeps no cache.

- target_language:

  Language code to translate into. Default `"en"`.

- pause:

  Seconds to wait between two requests. Default `0.5`.

- max_retries:

  How many times a request is retried after a "too many requests" reply,
  a server error or a lost connection. Default `4`.

- retry_wait:

  Seconds to wait before the first retry. The wait doubles with each
  further retry (2, 4, 8, 16 seconds with the defaults).

- batch_size:

  Maximum number of texts sent in one request. Default `50`.

- batch_chars:

  Maximum number of characters sent in one request. Google rejects
  requests much above 5000 characters. Default `4000`.

- timeout:

  Seconds to wait for one reply before giving up on it. Default `30`.

## Value

A named list of the settings.

## See also

[`translate_other_responses()`](translate_other_responses.md)

## Examples

``` r
ck_translate_options(cache_file = "output/translation_cache.rds")
#> $mask_numbers
#> [1] TRUE
#> 
#> $cache_file
#> [1] "output/translation_cache.rds"
#> 
#> $target_language
#> [1] "en"
#> 
#> $pause
#> [1] 0.5
#> 
#> $max_retries
#> [1] 4
#> 
#> $retry_wait
#> [1] 2
#> 
#> $batch_size
#> [1] 50
#> 
#> $batch_chars
#> [1] 4000
#> 
#> $timeout
#> [1] 30
#> 
```

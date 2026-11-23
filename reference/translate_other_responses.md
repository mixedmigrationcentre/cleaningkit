# Machine-Translate Other Responses

Fills the `translation` column of an other-responses data frame with an
English machine translation of each `response`, using Google Translate's
free web service. The detected language is shown in front of each
translation, e.g. `"[Arabic] I want to work"`.

## Usage

``` r
translate_other_responses(
  df,
  translate = "preview",
  options = ck_translate_options(),
  verbose = TRUE
)
```

## Arguments

- df:

  Data frame from
  [`prepare_other_responses()`](prepare_other_responses.md). One made by
  an earlier version (with `response_en` and no `translation` column)
  also works.

- translate:

  `"preview"` (the default) returns the texts that would be sent and
  sends nothing. `TRUE` sends them and fills the `translation` column.
  `FALSE` does nothing and returns `df` with an empty `translation`
  column.

- options:

  Settings from [`ck_translate_options()`](ck_translate_options.md).

- verbose:

  Logical. Print what is being sent and how it went. Default `TRUE`.

## Value

With `translate = TRUE` or `FALSE`, `df` with its `translation` column.
With `translate = "preview"`, a data frame with one row per text that
would be sent: `text_to_send` (exactly as it would be sent, after
masking), `n_responses` (how many responses share it) and `questions`.

## Details

**Nothing is sent unless you ask for it.** The default,
`translate = "preview"`, sends nothing: it returns the exact list of
texts that would be sent, so a team can check it first. Only
`translate = TRUE` contacts Google.

## What is sent

Only the text of the "other" responses, and each distinct text once. No
uuid, enumerator, date, location, question or any other column is sent,
and nothing links a text to the respondent. Before sending:

- blank responses and responses with no letters (only numbers or
  punctuation) are skipped;

- long numbers are masked as `#####` (see `mask_numbers` in
  [`ck_translate_options()`](ck_translate_options.md));

- texts already in the cache, and rows whose `translation` is already
  filled, are skipped.

The texts travel in the body of an HTTPS request, not in the web
address, so they do not end up in proxy or browser logs. Google still
receives them, and it sees the computer's IP address. The free service
comes with no data processing agreement: check your data-protection
rules before using it.

## Limits and failures

Google does not publish limits for the free service and blocks a
computer that sends too much too fast. Texts are therefore combined into
batches, requests are paced, and a "too many requests" reply is retried
after a growing wait (see
[`ck_translate_options()`](ck_translate_options.md)). If Google keeps
refusing, sending stops. A text that could not be translated is left
blank with a warning, and the rest of the work carries on; with a
`cache_file`, run it again later and only the missing texts are sent.

## Accuracy

Machine translation of short, informal, misspelt answers is often wrong,
and the language of a one-word answer can be misdetected. The
translation is a help for the reviewer, never applied to the data:
confirm it against the original response. A response detected as English
is left blank, as is one whose translation is identical to the original.

## See also

[`ck_translate_options()`](ck_translate_options.md),
[`prepare_other_responses()`](prepare_other_responses.md)

## Examples

``` r
if (FALSE) { # \dontrun{
# see what would be sent - nothing leaves the computer
preview <- translate_other_responses(other_responses_df)
View(preview)

# send it
other_responses_df <- translate_other_responses(
  other_responses_df,
  translate = TRUE,
  options = ck_translate_options(cache_file = "output/translation_cache.rds")
)
} # }
```

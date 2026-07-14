# Split a space-joined multi-word token string using a known vocabulary

The concat column in ONA exports joins selected values with spaces. When
values are multi-word labels (e.g. "Travel in a group Plan my journey
carefully Other") a naive whitespace split breaks them. This function
greedily matches the longest known token from `vocab` (sorted by
descending word count), case-insensitively, so multi-word labels are
correctly identified as atomic tokens.

## Usage

``` r
.split_concat(concat, vocab)
```

## Arguments

- concat:

  Space-joined string of selected values.

- vocab:

  Character vector of all valid tokens for this question.

## Value

Character vector of matched tokens (in original order).

# Normalise a token loosely: lowercase, punctuation to spaces, spaces collapsed

Two versions of the same XLSForm often differ only in punctuation or
spacing (`"Other (specify)"` vs `"Other(specify)"`), so exact matching
alone loses choices that are plainly the same.

## Usage

``` r
.norm_loose(x)
```

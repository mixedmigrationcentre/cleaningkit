# Pre-normalised view of tool_choices, computed once per call

Choice lookups compare normalised text, and normalising the whole
choices sheet on every lookup dominated the runtime. This builds the
normalised vectors once and memoises them in the shared cache.

## Usage

``` r
.norm_tool_choices(tool_choices, cache = NULL)
```

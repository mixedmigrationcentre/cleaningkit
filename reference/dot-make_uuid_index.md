# Build a uuid -\> row position lookup for the dataset

Built once per call and reused for every lookup. Resolving a uuid used
to mean copying the whole dataframe and re-scanning the uuid column,
which on a wide export costs more than all the cleaning logic put
together.

## Usage

``` r
.make_uuid_index(dataset, uuid_column, skip_label_row = TRUE)
```

## Value

A named integer vector: uuid -\> row position in `dataset` (positions
refer to the original dataframe, label row included).

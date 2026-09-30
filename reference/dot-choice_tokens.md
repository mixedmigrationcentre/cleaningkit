# Every token a choice could be written as in the dataset

The `list_name` recorded in `other_db` comes from whichever version of
the tool produced the original output, and that need not be the list the
current `tool_choices` calls by that name — a colleague's tool can name
the same list differently, or name a different list the same. So the
stated list is tried first, then the rest of `tool_choices` is searched
for the same text, so a mismatched `list_name` degrades to a slower
lookup rather than a wrong answer.

## Usage

``` r
.choice_tokens(text, list_name, tool_choices, tc_norm = NULL)
```

## Arguments

- text:

  The choice as written in the other-responses file (usually the label,
  occasionally the code).

- list_name:

  The `list_name` recorded in `other_db`.

- tool_choices:

  The XLSForm choices sheet.

## Value

Character vector of candidate tokens, most trustworthy first: the text
itself, then its counterpart within the stated list, then counterparts
found in any other list.

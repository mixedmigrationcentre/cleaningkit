# Resolve the Parent Question of an "Other" Text Question

Works out which question an "other" text question belongs to. The naming
convention is treated as the primary source of truth (`Q32_1` -\> `Q32`,
`Q86_b_1` -\> `Q86_b`) and the relevance expression is only consulted
when the convention does not resolve to a question that actually exists
in the survey sheet.

## Usage

``` r
.resolve_ref_question(name, relevant, tool_survey)
```

## Arguments

- name:

  Character vector of "other" text question names.

- relevant:

  Character vector of relevance expressions, same length as `name`.
  `NULL` is treated as all missing.

- tool_survey:

  The XLSForm survey sheet, used to check that a candidate parent exists
  and to read `q_type` when available.

## Value

A dataframe with one row per input: `name`, `ref_question`,
`resolved_via` and `option_other` (the option the parent is compared
against in the relevance expression).

## Details

This exists because reading the relevance expression alone is
unreliable: compound expressions such as
`${Q31} = 'kenya' and selected(${Q32}, 'other')` reference several
questions and the first one is usually a filter, not the parent.

Resolution order, per row:

1.  a name-convention candidate that is a `select_one` /
    `select_multiple` question and is also referenced in the relevance
    expression (`"name_and_relevance"`);

2.  a name-convention candidate that is a `select_*` question in the
    survey sheet (`"name"`);

3.  a `select_*` question that the relevance expression compares against
    an "other"-looking option (`"relevance"`);

4.  a name-convention candidate, not a select question, that the
    relevance expression also references (`"name_and_relevance"`);

5.  a name-convention candidate that exists in the survey sheet
    (`"name"`);

6.  any question referenced by the relevance expression, preferring an
    "other"-looking clause, then a `select_*` question, then the last
    reference (`"relevance"`);

7.  the question's own name (`"self"`).

Steps 1-3 are what put a select question ahead of a same-named
non-select one: `Q90_1` sitting under an integer `Q90` but relevant on
`selected(${Q78}, 'other')` resolves to `Q78`, because only a select
question has choices to recode an "other" response into.

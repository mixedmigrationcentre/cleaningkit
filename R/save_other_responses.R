#' Coerce a vector to valid UTF-8
#'
#' Replaces invalid byte sequences so that openxlsx / stringi can measure the
#' string length. Non-character vectors are returned unchanged; factor levels
#' are cleaned in place.
#' @keywords internal
.sanitize_utf8 <- function(x) {
  if (is.character(x)) {
    stringi::stri_enc_toutf8(x, validate = TRUE)
  } else if (is.factor(x)) {
    levels(x) <- stringi::stri_enc_toutf8(levels(x), validate = TRUE)
    x
  } else {
    x
  }
}

#' Prepare Other Responses Dataframe
#'
#' Combines other responses from all sheets/loops into a single dataframe
#' ready for use with \code{save_other_responses()}. The function dynamically
#' includes extra columns (e.g., enumerator, sample_area) if provided.
#'
#' @param raw_data Main raw dataset dataframe (always required).
#' @param other_db Dataframe from \code{get_other_db()} with question metadata.
#' @param kobo_choices Dataframe of Kobo choices sheet.
#' @param raw_loops Optional list of loop/roster dataframes (default is NULL).
#'   Pass as a named or unnamed list, e.g.,
#'   \code{list(household_roster = df1, children = df2)} or \code{list(df1, df2)}.
#' @param extra_columns Optional character vector of additional column names
#'   to include from the raw data (e.g., \code{c("enumerator", "sample_area")}).
#'   Default is NULL.
#' @param uuid_column Name of the uuid column in raw_data (default is "_uuid").
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row of
#'   \code{raw_data} and of every loop/roster in \code{raw_loops} is dropped
#'   before processing. ONA exports place a label/description row immediately
#'   after the header; if it is kept it is mistaken for a respondent and produces
#'   one spurious "other" response (label text, bogus uuid) per question.
#' @param label_language_fallback Logical. If \code{TRUE} (the default), when the
#'   English label lookup for a selected \code{select_multiple} code returns
#'   nothing, the first non-empty label column in \code{kobo_choices} (e.g. an
#'   Arabic \code{label::Arabic (ar)} column) is used instead, so responses in
#'   other languages are shown as they appear in the raw data rather than as
#'   \code{NA}.
#' @param fallback_to_code Logical. If \code{TRUE} (the default), a selected code
#'   with no label in any language is displayed as the raw code itself, so no
#'   \code{"NA"} is ever written into \code{selected_choices}.
#' @param preferred_language Optional. The label language to prefer when resolving
#'   \code{select_multiple} choice labels. May be an exact label column name (e.g.
#'   \code{"label::Arabic (ar)"}) or a substring (e.g. \code{"Arabic"}). Passed to
#'   \code{get_label_from_name()} and also used to order the fallback lookup. If
#'   \code{NULL} (the default), the existing preference order is used (a bare
#'   \code{label} column, else the first label column found).
#' @param questions Optional character vector of question names (as they appear
#'   in the \code{name} column of \code{other_db}) to process. If \code{NULL}
#'   (the default), all questions in \code{other_db} are used. When provided,
#'   only the specified questions are prepared; an error is raised if any name
#'   is not found in \code{other_db}.
#' @return A dataframe formatted for \code{save_other_responses()}. It carries an
#'   attribute \code{"ona_label_row_skipped"} recording whether the label row was
#'   dropped, so \code{save_other_responses()} does not drop a row a second time.
#' @export
prepare_other_responses <- function(
  raw_data,
  other_db,
  kobo_choices,
  raw_loops = NULL,
  extra_columns = NULL,
  uuid_column = "_uuid",
  questions = NULL,
  skip_label_row = TRUE,
  label_language_fallback = TRUE,
  fallback_to_code = TRUE,
  preferred_language = NULL
) {
  # --- Drop the ONA label/description row (first row after the header) --------
  # Done first, before any pivot, so it is never treated as real survey data.
  # Applied to the main data and to every loop/roster (each has its own label row).
  if (isTRUE(skip_label_row)) {
    if (nrow(raw_data) > 0) {
      raw_data <- raw_data[-1, , drop = FALSE]
    }
    if (!is.null(raw_loops)) {
      raw_loops <- lapply(raw_loops, function(loop_df) {
        if (!is.null(loop_df) && nrow(loop_df) > 0) {
          loop_df[-1, , drop = FALSE]
        } else {
          loop_df
        }
      })
    }
  }

  # --- Optionally filter other_db to only the requested questions -------------
  if (!is.null(questions)) {
    missing_qs <- setdiff(questions, other_db$name)
    if (length(missing_qs) > 0) {
      stop(
        "The following question(s) were not found in `other_db`: ",
        paste(missing_qs, collapse = ", ")
      )
    }
    other_db <- other_db[other_db$name %in% questions, , drop = FALSE]
  }

  # Rename uuid column if needed
  if (uuid_column != "uuid" && uuid_column %in% colnames(raw_data)) {
    raw_data <- raw_data %>% rename(uuid = !!sym(uuid_column))
  }

  # Rename uuid column in all loop datasets
  if (!is.null(raw_loops)) {
    raw_loops <- lapply(raw_loops, function(loop_df) {
      if (uuid_column != "uuid" && uuid_column %in% colnames(loop_df)) {
        loop_df <- loop_df %>% rename(uuid = !!sym(uuid_column))
      }
      return(loop_df)
    })
  }

  # --- Main dataset other responses ---
  var_other_raw <- other_db$name[other_db$name %in% colnames(raw_data)]

  select_cols_main <- c("uuid", var_other_raw)
  if (!is.null(extra_columns)) {
    select_cols_main <- c(
      select_cols_main,
      intersect(extra_columns, colnames(raw_data))
    )
  }

  other_responses_main <- raw_data %>%
    select(all_of(select_cols_main)) %>%
    pivot_longer(
      cols = all_of(var_other_raw),
      names_to = "question_name",
      values_to = "response_en"
    ) %>%
    filter(!is.na(response_en))

  # --- Loop datasets other responses (if provided) ---
  other_responses <- other_responses_main

  if (!is.null(raw_loops) && length(raw_loops) > 0) {
    for (loop_df in raw_loops) {
      var_other_loop <- other_db$name[other_db$name %in% colnames(loop_df)]

      if (length(var_other_loop) > 0) {
        select_cols_loop <- c("uuid", var_other_loop)
        if (!is.null(extra_columns)) {
          select_cols_loop <- c(
            select_cols_loop,
            intersect(extra_columns, colnames(loop_df))
          )
        }

        other_responses_loop <- loop_df %>%
          select(all_of(select_cols_loop)) %>%
          pivot_longer(
            cols = all_of(var_other_loop),
            names_to = "question_name",
            values_to = "response_en"
          ) %>%
          filter(!is.na(response_en))

        other_responses <- bind_rows(other_responses, other_responses_loop)
      }
    }
  }

  # Build the dynamic select columns
  select_cols <- c("uuid")
  if (!is.null(extra_columns)) {
    select_cols <- c(
      select_cols,
      intersect(extra_columns, colnames(other_responses))
    )
  }
  select_cols <- c(
    select_cols,
    "question_name",
    "list_name",
    "full_label",
    "response_en"
  )

  # Generate final dataframe
  df <- other_responses %>%
    arrange(question_name, uuid) %>%
    left_join(
      select(other_db, name, full_label, list_name),
      by = c("question_name" = "name")
    ) %>%
    select(all_of(select_cols)) %>%
    mutate(
      "TRUE other (copy response_en or provide a better translation)" = NA,
      "EXISTING other 1 (select the most appropriate choice)" = NA,
      "EXISTING other 2 (select the most appropriate choice)" = NA,
      "EXISTING other 3 (select the most appropriate choice)" = NA,
      "INVALID other (select yes or leave blank)" = NA,
      "FOLLOW-UP message (what is unclear about this response?)" = NA,
      "Explanation" = NA,
      selected_choices = NA_character_
    )

  # ---------------------------------------------------------------------------
  # Vectorized "selected choices" for select_multiple questions.
  #
  # Here we:
  #   1. resolve ref_question / q_type once via match(),
  #   2. build a uuid -> value lookup per referenced column (main data first,
  #      loops fill only missing/NA uuids, first occurrence wins),
  #   3. memoize get_label_from_name() over unique (list_name, code) pairs.
  # ---------------------------------------------------------------------------
  df$selected_choices <- NA_character_

  if (nrow(df) > 0) {
    meta_idx <- match(df$question_name, other_db$name)
    type_row <- other_db[["q_type"]][meta_idx]
    ref_row <- other_db[["ref_question"]][meta_idx]

    sm_idx <- which(!is.na(type_row) & type_row == "select_multiple")

    if (length(sm_idx) > 0) {
      ref_for_row <- as.character(ref_row[sm_idx])
      uuid_for_row <- as.character(df$uuid[sm_idx])
      list_for_row <- df$list_name[sm_idx]

      # Build a uuid -> value map for a single referenced column.
      build_uuid_map <- function(ref_col) {
        m <- character(0)

        if (ref_col %in% colnames(raw_data) && "uuid" %in% colnames(raw_data)) {
          keep <- !duplicated(as.character(raw_data$uuid))
          m <- setNames(
            as.character(raw_data[[ref_col]])[keep],
            as.character(raw_data$uuid)[keep]
          )
        }

        if (!is.null(raw_loops)) {
          for (loop_df in raw_loops) {
            if (
              ref_col %in% colnames(loop_df) && "uuid" %in% colnames(loop_df)
            ) {
              keep <- !duplicated(as.character(loop_df$uuid))
              vals <- as.character(loop_df[[ref_col]])[keep]
              uus <- as.character(loop_df$uuid)[keep]
              add <- setNames(vals, uus)
              # only fill uuids that are missing or NA in the main-data map
              have <- names(m)[!is.na(m)]
              need <- setdiff(uus, have)
              m[need] <- add[need]
            }
          }
        }
        m
      }

      uniq_refs <- unique(ref_for_row[!is.na(ref_for_row)])
      ref_maps <- lapply(uniq_refs, build_uuid_map)
      names(ref_maps) <- uniq_refs

      # Look up the raw (space-separated) value for each select_multiple row.
      raw_values <- vapply(
        seq_along(sm_idx),
        function(k) {
          rc <- ref_for_row[k]
          if (is.na(rc) || is.null(ref_maps[[rc]])) {
            return(NA_character_)
          }
          val <- ref_maps[[rc]][uuid_for_row[k]]
          if (length(val) == 0 || is.na(val)) {
            NA_character_
          } else {
            as.character(val)
          }
        },
        character(1)
      )

      # Split the stored value into its individual selected choices.
      #
      # A naive space split breaks a multi-word choice ("Waiting for transport")
      # into single words. Instead we segment the value against a known
      # vocabulary:
      #   * fast path - if every space-token is a valid short code (from
      #     kobo_choices$name for this list), use the tokens as-is;
      #   * otherwise - greedily match the longest known label phrase from
      #     other_db$choices (the ";;"-separated labels), case-insensitively.
      # Tokens that match nothing are kept as-is (e.g. an "other" code, which the
      # downstream resolver then turns into its label).
      vocab_by_list <- if (!is.null(kobo_choices) &&
        all(c("list_name", "name") %in% names(kobo_choices))) {
        split(
          as.character(kobo_choices$name),
          as.character(kobo_choices$list_name)
        )
      } else {
        list()
      }

      # list_name -> vector of label phrases, taken from other_db$choices ("A;;B").
      label_vocab_by_list <- list()
      if (!is.null(other_db) &&
        all(c("list_name", "choices") %in% names(other_db))) {
        ldf <- other_db[
          !is.na(other_db$list_name) & !is.na(other_db$choices),
          c("list_name", "choices"),
          drop = FALSE
        ]
        ldf <- ldf[!duplicated(ldf$list_name), , drop = FALSE]
        for (i in seq_len(nrow(ldf))) {
          labs <- strsplit(as.character(ldf$choices[i]), ";;", fixed = TRUE)[[1]]
          labs <- trimws(labs)
          labs <- labs[nzchar(labs)]
          label_vocab_by_list[[as.character(ldf$list_name[i])]] <- labs
        }
      }

      split_selected <- function(value, ln) {
        if (is.na(value) || !nzchar(trimws(value))) {
          return(character(0))
        }
        toks <- strsplit(trimws(value), "\\s+")[[1]]
        toks <- toks[nzchar(toks)]
        if (length(toks) == 0) {
          return(character(0))
        }

        # fast path: proper single-token codes
        name_vn <- if (!is.na(ln)) vocab_by_list[[ln]] else NULL
        if (!is.null(name_vn) && length(name_vn) > 0 && all(toks %in% name_vn)) {
          return(toks)
        }

        # greedy longest-match against the ";;" label phrases (case-insensitive)
        lab_vn <- if (!is.na(ln)) label_vocab_by_list[[ln]] else NULL
        if (is.null(lab_vn) || length(lab_vn) == 0) {
          return(toks)
        }
        lab_words <- strsplit(lab_vn, "\\s+")
        ord <- order(-lengths(lab_words))
        lab_vn <- lab_vn[ord]
        lab_words <- lab_words[ord]
        lab_words_lc <- lapply(lab_words, tolower)
        toks_lc <- tolower(toks)

        out <- character(0)
        i <- 1L
        n <- length(toks)
        while (i <= n) {
          matched <- NA_character_
          for (j in seq_along(lab_vn)) {
            L <- length(lab_words_lc[[j]])
            if (i + L - 1L <= n &&
              identical(toks_lc[i:(i + L - 1L)], lab_words_lc[[j]])) {
              matched <- lab_vn[j] # canonical label from other_db
              i <- i + L
              break
            }
          }
          if (is.na(matched)) {
            out <- c(out, toks[i]) # unmatched token: keep (resolver handles codes)
            i <- i + 1L
          } else {
            out <- c(out, matched)
          }
        }
        out
      }

      split_codes <- Map(split_selected, raw_values, list_for_row)
      names(split_codes) <- NULL
      label_cache <- new.env(parent = emptyenv())

      pair_keys <- unique(unlist(
        Map(
          function(codes, ln) {
            if (length(codes) == 0) {
              return(character(0))
            }
            codes <- codes[!is.na(codes) & nzchar(codes)]
            if (length(codes) == 0) {
              return(character(0))
            }
            paste(ln, codes, sep = "\u0001")
          },
          split_codes,
          list_for_row
        ),
        use.names = FALSE
      ))
      pair_keys <- pair_keys[!is.na(pair_keys)]

      # Build a language fallback map from kobo_choices: for each
      # (list_name, name) pair, the first non-empty label column value. Kobo
      # label columns start with "label" (e.g. "label::English (en)",
      # "label::Arabic (ar)"). When preferred_language is set, that column is put
      # first so the fallback also prefers it; otherwise columns keep their order.
      choice_fallback_map <- NULL
      if (isTRUE(label_language_fallback) &&
        !is.null(kobo_choices) &&
        all(c("list_name", "name") %in% names(kobo_choices)) &&
        nrow(kobo_choices) > 0) {
        label_cols <- grep(
          "^label", names(kobo_choices),
          ignore.case = TRUE, value = TRUE
        )
        if (!is.null(preferred_language) && length(label_cols) > 0) {
          pref <- label_cols[
            label_cols == preferred_language |
              grepl(preferred_language, label_cols, ignore.case = TRUE)
          ]
          label_cols <- c(pref, setdiff(label_cols, pref))
        }
        if (length(label_cols) > 0) {
          lab_mat <- as.matrix(kobo_choices[, label_cols, drop = FALSE])
          first_nonempty <- apply(lab_mat, 1, function(vals) {
            vals <- vals[!is.na(vals) & nzchar(trimws(vals))]
            if (length(vals) == 0) NA_character_ else vals[[1]]
          })
          ck <- paste(
            as.character(kobo_choices$list_name),
            as.character(kobo_choices$name),
            sep = "\u0001"
          )
          choice_fallback_map <- stats::setNames(
            as.character(first_nonempty), ck
          )
        }
      }

      # Resolve a code's label: preferred language first (via get_label_from_name),
      # then any other language (via the fallback map), then the raw code
      # (never NA when fallback_to_code = TRUE).
      resolve_label <- function(list_name, code) {
        lab <- tryCatch(
          as.character(get_label_from_name(
            list_name, code, kobo_choices,
            label_column = preferred_language
          ))[1],
          error = function(e) NA_character_
        )
        if (!is.na(lab) && nzchar(lab) && !identical(lab, "NA")) {
          return(lab)
        }
        if (!is.null(choice_fallback_map)) {
          alt <- unname(
            choice_fallback_map[paste(list_name, code, sep = "\u0001")]
          )
          if (!is.na(alt) && nzchar(alt)) {
            return(alt)
          }
        }
        if (isTRUE(fallback_to_code)) {
          return(code)
        }
        NA_character_
      }

      for (pk in pair_keys) {
        parts <- strsplit(pk, "\u0001", fixed = TRUE)[[1]]
        assign(
          pk,
          resolve_label(parts[1], parts[2]),
          envir = label_cache
        )
      }

      df$selected_choices[sm_idx] <- vapply(
        seq_along(sm_idx),
        function(k) {
          codes <- split_codes[[k]]
          codes <- codes[!is.na(codes) & nzchar(codes)]
          if (length(codes) == 0) {
            return(NA_character_)
          }
          labs <- vapply(
            codes,
            function(cc) {
              get0(
                paste(list_for_row[k], cc, sep = "\u0001"),
                envir = label_cache,
                ifnotfound = NA_character_
              )
            },
            character(1)
          )
          paste0(labs, collapse = ";\n")
        },
        character(1)
      )
    }
  }

  df <- relocate(df, "selected_choices", .before = "response_en")

  # Record that the label row has (or has not) been handled, so downstream
  # save_other_responses() does not drop a row a second time.
  attr(df, "ona_label_row_skipped") <- isTRUE(skip_label_row)
  return(df)
}

#' Save Other Responses
#'
#' This function saves the other responses into an Excel workbook with specific
#' formatting and data validation. Target columns are identified dynamically by
#' name, allowing flexibility such as adding an `enumerator_id`.
#'
#' @param df Data frame containing the responses to write.
#' @param ref_date Reference date for the filename (default is "").
#' @param enumerator_id Optional string indicating the enumerator id column
#'   (default is NULL).
#' @param save_location Directory to save the output file (default is "output").
#' @param other_db Data frame containing dropdown mapping for existing choices
#'   (default is NULL).
#' @param apply_styles Logical. If TRUE (default) apply the coloured/bordered
#'   cell styling. Set to FALSE for very large exports where per-cell styling
#'   makes openxlsx slow or memory-hungry; the data and dropdowns are still
#'   written.
#' @param skip_label_row Logical. If \code{TRUE} (the default), guard against an
#'   ONA label/description row still sitting at the top of \code{df}. When \code{df}
#'   comes from \code{prepare_other_responses()} the label row was already handled
#'   (tracked via the \code{"ona_label_row_skipped"} attribute) and nothing is
#'   dropped. Only when \code{df} has no such provenance is its first row dropped,
#'   with a message. Set to \code{FALSE} to always keep every row.
#' @return NULL. Saves an Excel file.
#' @export
save_other_responses <- function(
  df,
  ref_date = "",
  enumerator_id = NULL,
  save_location = "output",
  other_db = NULL,
  apply_styles = TRUE,
  skip_label_row = TRUE
) {
  get_column_letter <- function(r) {
    result <- character(length(r))
    for (i in seq_along(r)) {
      n <- r[i]
      col <- ""
      while (n > 0) {
        remainder <- (n - 1) %% 26
        col <- paste0(LETTERS[remainder + 1], col)
        n <- (n - 1) %/% 26
      }
      result[i] <- col
    }
    result
  }

  # --- Guard against a stray ONA label row -----------------------------------
  # The authoritative place to drop the label row is prepare_other_responses().
  # If df carries the "ona_label_row_skipped" attribute it already went through
  # that step, so we must NOT drop again (that would delete a real response).
  # Only when provenance is unknown (no attribute) do we drop the first row.
  if (isTRUE(skip_label_row) &&
    is.null(attr(df, "ona_label_row_skipped")) &&
    nrow(df) > 0) {
    message(
      "save_other_responses(): dropping the first row as the ONA label row ",
      "(df did not come from prepare_other_responses(); set skip_label_row = FALSE to keep it)."
    )
    df <- df[-1, , drop = FALSE]
  }

  # --- Clean invalid UTF-8 BEFORE any writeData call --------------------------
  # openxlsx::writeData -> stringi::stri_length() errors on invalid byte
  # sequences, so this must run before df reaches writeData.
  df[] <- lapply(df, .sanitize_utf8)
  names(df) <- stringi::stri_enc_toutf8(names(df), validate = TRUE)

  # --- Place enumerator column right after uuid if provided --------------------
  if (!is.null(enumerator_id) && enumerator_id %in% names(df)) {
    uuid_pos <- which(names(df) == "uuid")
    if (length(uuid_pos) > 0) {
      other_cols <- setdiff(names(df), enumerator_id)
      insert_at <- uuid_pos[1]
      new_order <- c(
        other_cols[seq_len(insert_at)],
        enumerator_id,
        other_cols[setdiff(seq_along(other_cols), seq_len(insert_at))]
      )
      df <- df[, new_order, drop = FALSE]
    }
  }

  n_rows <- nrow(df)
  n_cols <- ncol(df)

  # --- Guard against Excel's hard limits --------------------------------------
  if (n_rows + 1L > 1048576L) {
    stop(sprintf(
      "df has %s rows; Excel supports at most 1,048,576 rows per sheet.",
      format(n_rows, big.mark = ",")
    ))
  }
  if (n_cols > 16384L) {
    stop(sprintf(
      "df has %s columns; Excel supports at most 16,384 columns per sheet.",
      format(n_cols, big.mark = ",")
    ))
  }

  wb <- createWorkbook()

  style.col.color <- createStyle(
    fgFill = "#E5FFCC",
    border = "TopBottomLeftRight",
    borderColour = "#000000",
    valign = "top",
    wrapText = TRUE
  )
  style.col.color1 <- createStyle(
    fgFill = "#E5FFEC",
    border = "TopBottomLeftRight",
    borderColour = "#000000",
    valign = "top",
    wrapText = TRUE
  )
  style.col.color2 <- createStyle(
    fgFill = "#CCE5FF",
    border = "TopBottomLeftRight",
    borderColour = "#000000",
    valign = "top",
    wrapText = TRUE
  )
  style.col.color.first <- createStyle(
    textDecoration = "bold",
    fgFill = "#E5FFCC",
    valign = "top",
    border = "TopBottomLeftRight",
    borderColour = "#000000",
    wrapText = TRUE
  )
  style.col.color.first1 <- createStyle(
    textDecoration = "bold",
    fgFill = "#E5FFEC",
    valign = "top",
    border = "TopBottomLeftRight",
    borderColour = "#000000",
    wrapText = TRUE
  )
  style.col.color.first2 <- createStyle(
    textDecoration = "bold",
    fgFill = "#CCE5FF",
    valign = "top",
    border = "TopBottomLeftRight",
    borderColour = "#000000",
    wrapText = TRUE
  )
  style.default.body <- createStyle(valign = "top", wrapText = TRUE)
  style.default.header <- createStyle(textDecoration = "bold")

  addWorksheet(wb, "Sheet1")
  writeData(wb = wb, x = df, sheet = "Sheet1", startRow = 1)

  exist_cols <- which(
    names(df) %in%
      c(
        "EXISTING other 1 (select the most appropriate choice)",
        "EXISTING other 2 (select the most appropriate choice)",
        "EXISTING other 3 (select the most appropriate choice)"
      )
  )
  invalid_col <- which(names(df) == "INVALID other (select yes or leave blank)")

  # --- Styling: assign a category per column, then style in batches -----------
  # Batching with gridExpand = TRUE reduces ~2*ncol addStyle calls to a handful,
  # which matters a lot when there are many columns.
  if (isTRUE(apply_styles)) {
    category <- rep("default", n_cols)
    category[exist_cols] <- "exist"
    category[invalid_col] <- "invalid"

    if (length(exist_cols) > 0) {
      pre <- min(exist_cols) - 1L
      if (pre >= 1L && category[pre] == "default") category[pre] <- "trueother"
    }
    if (length(invalid_col) > 0) {
      post <- which(seq_len(n_cols) > max(invalid_col) & category == "default")
      category[post] <- "postinvalid"
    }

    apply_cat <- function(cat_name, body_style, header_style) {
      cols <- which(category == cat_name)
      if (length(cols) == 0) {
        return(invisible())
      }
      addStyle(
        wb,
        "Sheet1",
        body_style,
        rows = seq_len(n_rows + 1L),
        cols = cols,
        gridExpand = TRUE
      )
      addStyle(
        wb,
        "Sheet1",
        header_style,
        rows = 1,
        cols = cols,
        gridExpand = TRUE
      )
    }

    apply_cat("exist", style.col.color1, style.col.color.first1)
    apply_cat("invalid", style.col.color, style.col.color.first)
    apply_cat("trueother", style.col.color, style.col.color.first)
    apply_cat("postinvalid", style.col.color2, style.col.color.first2)
    apply_cat("default", style.default.body, style.default.header)
  }

  addWorksheet(wb, "Dropdown_values")
  if (!is.null(other_db) && nrow(other_db) > 0) {
    for (r in seq_len(nrow(other_db))) {
      if (other_db$q_type[r] != "text") {
        choices <- str_split(other_db$choices[r], ";;")[[1]]
        writeData(wb, sheet = "Dropdown_values", x = choices, startCol = r)
        uuids <- which(df$question_name == other_db$name[r])
        if (length(uuids) > 0 && length(exist_cols) > 0) {
          column_letter <- get_column_letter(r)
          values <- paste0(
            "='Dropdown_values'!$",
            column_letter,
            "$1:$",
            column_letter,
            "$",
            other_db$num_choices[r]
          )
          for (c_idx in exist_cols) {
            dataValidation(
              wb,
              "Sheet1",
              cols = c_idx,
              rows = uuids + 1,
              type = "list",
              value = values
            )
          }
        }
      }
    }
  } else {
    r <- 0
  }

  writeData(
    wb,
    sheet = "Dropdown_values",
    x = c("Yes"),
    startCol = r + 1,
    colNames = FALSE
  )
  column_letter <- get_column_letter(r + 1)
  values <- paste0(
    "='Dropdown_values'!$",
    column_letter,
    "$1:$",
    column_letter,
    "$1"
  )
  if (length(invalid_col) > 0) {
    dataValidation(
      wb,
      "Sheet1",
      cols = invalid_col,
      rows = 2:(n_rows + 1L),
      type = "list",
      value = values
    )
  }

  setColWidths(wb, "Sheet1", cols = seq_len(n_cols), widths = 25)
  setColWidths(wb, "Sheet1", cols = seq_len(min(5L, n_cols)), widths = 15)

  modifyBaseFont(wb, fontSize = 12, fontColour = "black", fontName = "Calibri")

  sub.filename <- paste0(Sys.Date(), "_other_responses.xlsx")
  if (!dir.exists(save_location)) {
    dir.create(save_location, recursive = TRUE)
  }

  saveWorkbook(wb, file.path(save_location, sub.filename), overwrite = TRUE)
}
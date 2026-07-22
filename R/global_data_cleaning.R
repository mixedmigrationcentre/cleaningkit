#' Combine multiple ONA select-multiple questions into a single consolidated column
#'
#' Takes several source select-multiple questions (e.g. QO100, Q100, Q104,
#' Q108, Q112, Q116) — each with its own parent concat column and label-value
#' dummy sub-columns — and collapses them into a single target select-multiple
#' column (e.g. Q118a) and its dummy sub-columns.
#'
#' This function handles the \strong{label-value convention} used by ONA
#' exports: a dummy sub-column contains the choice label (i.e. the column
#' suffix) when that choice is selected, and \code{NA}/blank when it is not.
#'
#' The target parent concat is the union of all unique choices selected across
#' the source questions (de-duplicated, space-separated, ordered by
#' \code{target_choices}). Each target dummy sub-column contains the choice
#' label when selected across ANY source, and \code{NA} when not selected.
#'
#' Choice labels in the source and target may differ (e.g. "Trafficking or
#' exploitation" vs "Trafficking and exploitation"). Use \code{choice_map} to
#' remap source labels to target labels. Any source choice not present in
#' \code{target_choices} after remapping is silently dropped.
#'
#' @param dataset A dataframe (ONA export). The ONA label row should already
#'   have been removed before calling this function.
#' @param source_questions Character vector of source parent column names,
#'   e.g. \code{c("QO100", "Q100", "Q104", "Q108", "Q112", "Q116")}.
#' @param target_question Name of the target parent column, e.g. \code{"Q118a"}.
#' @param target_choices Character vector of valid target choice labels exactly
#'   as they appear as suffixes in the target dummy column names (after the
#'   \code{sm_separator}). Determines which choices are kept and their order in
#'   the parent concat.
#' @param choice_map Named character vector remapping source choice labels to
#'   target choice labels. Names are source labels, values are target labels.
#'   E.g. \code{c("Trafficking or exploitation" = "Trafficking and exploitation")}.
#'   Default \code{NULL} (no remapping).
#' @param sm_separator Separator between a select-multiple parent column name
#'   and its dummy sub-columns. Default \code{"/"} (ONA export style).
#'
#' @return The dataset with the target parent column and all target dummy
#'   sub-columns added (or overwritten if they already exist). Target dummy
#'   sub-columns use label-value convention: the choice label when selected,
#'   \code{NA} when not selected.
#' @export
combine_sm_questions <- function(
  dataset,
  source_questions,
  target_question,
  target_choices,
  choice_map = NULL,
  sm_separator = "/"
) {
  # ---- internal helpers -------------------------------------------------------

  # Build a dummy sub-column name from parent + choice label.
  dummy_col <- function(parent, choice) paste0(parent, sm_separator, choice)

  # Is a cell value "selected" under the label-value convention?
  # Selected = non-NA and non-blank.
  is_selected <- function(x) !is.na(x) & nzchar(trimws(as.character(x)))

  # Extract the choice suffix from a dummy column name.
  # Uses fixed-string stripping — no regex — so any question name works
  # regardless of characters it contains (QO100, Q100, Q.1/a, etc.)
  get_suffix <- function(col_name, parent) {
    prefix <- paste0(parent, sm_separator)
    sub(prefix, "", col_name, fixed = TRUE)
  }

  # Find all dummy sub-columns for a given parent using a fixed prefix match.
  sm_sub_cols <- function(parent) {
    prefix <- paste0(parent, sm_separator)
    names(dataset)[startsWith(names(dataset), prefix)]
  }

  # ---- collect chosen choices per row across all source questions -------------

  n_rows <- nrow(dataset)
  all_chosen <- vector("list", n_rows) # all_chosen[[i]] = character vector

  for (src in source_questions) {
    src_dummies <- sm_sub_cols(src)

    if (length(src_dummies) > 0) {
      # ---- label-value dummy sub-columns are present -------------------------
      for (dc in src_dummies) {
        src_label <- get_suffix(dc, src)

        # Remap to target label if a mapping exists, otherwise keep as-is
        tgt_label <- if (
          !is.null(choice_map) && src_label %in% names(choice_map)
        ) {
          choice_map[[src_label]]
        } else {
          src_label
        }

        # Drop choices that are not valid in the target
        if (!(tgt_label %in% target_choices)) {
          next
        }

        # A cell is "selected" when it is non-NA and non-blank
        selected_rows <- which(is_selected(dataset[[dc]]))
        for (i in selected_rows) {
          all_chosen[[i]] <- unique(c(all_chosen[[i]], tgt_label))
        }
      }
    } else if (src %in% names(dataset)) {
      # ---- fallback: parse the parent concat column --------------------------
      # Build a vocabulary of all source labels (pre-remap) + target labels so
      # the greedy longest-match tokeniser can handle multi-word choice labels.
      src_vocab <- unique(c(
        if (!is.null(choice_map)) names(choice_map) else character(0),
        target_choices
      ))

      vocab_words <- strsplit(src_vocab, "\\s+")
      ord <- order(-lengths(vocab_words)) # descending word count
      src_vocab_o <- src_vocab[ord]
      src_vocab_lc <- lapply(vocab_words[ord], tolower)

      split_concat_greedy <- function(concat) {
        if (is.na(concat) || !nzchar(trimws(concat))) {
          return(character(0))
        }
        toks <- strsplit(trimws(concat), "\\s+")[[1]]
        toks <- toks[nzchar(toks)]
        toks_lc <- tolower(toks)
        out <- character(0)
        i <- 1L
        n <- length(toks)
        while (i <= n) {
          matched <- NA_character_
          for (j in seq_along(src_vocab_o)) {
            L <- length(src_vocab_lc[[j]])
            if (
              i + L - 1L <= n &&
                identical(toks_lc[i:(i + L - 1L)], src_vocab_lc[[j]])
            ) {
              matched <- src_vocab_o[j]
              i <- i + L
              break
            }
          }
          if (is.na(matched)) {
            out <- c(out, toks[i]) # unknown token: keep as-is
            i <- i + 1L
          } else {
            out <- c(out, matched)
          }
        }
        out
      }

      for (i in seq_len(n_rows)) {
        raw_tokens <- split_concat_greedy(as.character(dataset[[src]][i]))

        mapped <- vapply(
          raw_tokens,
          function(tok) {
            if (!is.null(choice_map) && tok %in% names(choice_map)) {
              choice_map[[tok]]
            } else {
              tok
            }
          },
          character(1)
        )

        valid <- mapped[mapped %in% target_choices]
        all_chosen[[i]] <- unique(c(all_chosen[[i]], valid))
      }
    } else {
      warning(
        "combine_sm_questions: source question '",
        src,
        "' not found in the dataset (no parent column, no dummy sub-columns). Skipping."
      )
    }
  }

  # ---- write target parent concat column -------------------------------------
  # Tokens are ordered by their position in target_choices (canonical order).
  dataset[[target_question]] <- vapply(
    all_chosen,
    function(choices) {
      ordered <- target_choices[target_choices %in% choices]
      if (length(ordered) == 0L) {
        return(NA_character_)
      }
      paste(ordered, collapse = " ")
    },
    character(1)
  )

  # ---- write target dummy sub-columns (label-value convention) ---------------
  # Selected     → cell value = the choice label (the column suffix)
  # Not selected → NA
  for (tc in target_choices) {
    col_name <- dummy_col(target_question, tc)
    dataset[[col_name]] <- vapply(
      all_chosen,
      function(choices) if (tc %in% choices) tc else NA_character_,
      character(1)
    )
  }

  dataset
}


#' Rename a Choice Label in a Select-Multiple Question
#'
#' Renames a choice label across all four places where it appears in an ONA
#' export: the dummy sub-column \emph{name}, the parent concat column
#' \emph{values}, the dummy sub-column \emph{values} (label-value convention),
#' and the ONA \emph{label row} (row 1 of the dataset). Only the column whose
#' name starts with \code{<question_col><sm_separator>} and ends with
#' \code{old_choice} is renamed; all other column names in the dataset are
#' left unchanged.
#'
#' The function handles the \strong{label-value convention} used by ONA exports:
#' a dummy sub-column holds the choice label as its cell value when selected and
#' \code{NA}/blank when not selected. The parent concat column stores selected
#' choices as a space-separated string of labels; renaming replaces every
#' occurrence of \code{old_choice} in that string with \code{new_choice}.
#'
#' @param dataset A dataframe (ONA export, label row still present as row 1).
#' @param question_col Name of the select-multiple parent column whose choice
#'   is being renamed, e.g. \code{"Q100"}.
#' @param old_choice The current choice label as it appears in the dataset,
#'   e.g. \code{"Trafficking or exploitation"}. Must match exactly (case-sensitive).
#' @param new_choice The new choice label to use, e.g.
#'   \code{"Trafficking and exploitation"}.
#' @param sm_separator Separator between the parent column name and the choice
#'   label in dummy sub-column names. Default \code{"/"} (ONA export style).
#' @param skip_label_row Logical. If \code{TRUE} (the default), row 1 of the
#'   dataset is treated as the ONA label/description row and is also updated
#'   (any occurrence of \code{old_choice} in that row is replaced with
#'   \code{new_choice}). Set to \code{FALSE} if the label row has already been
#'   removed.
#'
#' @return The dataset with the choice label renamed in all four locations.
#'   Column order is preserved; the renamed dummy sub-column occupies the same
#'   position as before.
#'
#' @examples
#' \dontrun{
#' dataset <- rename_sm_choice_label(
#'   dataset      = dataset,
#'   question_col = "Q100",
#'   old_choice   = "Trafficking or exploitation",
#'   new_choice   = "Trafficking and exploitation"
#' )
#' }
#'
#' @importFrom stringr str_replace_all fixed
#' @export
rename_sm_choice_label <- function(
  dataset,
  question_col,
  old_choice,
  new_choice,
  sm_separator = "/",
  skip_label_row = TRUE
) {
  # ---- input validation -------------------------------------------------------
  if (!is.data.frame(dataset)) {
    stop("`dataset` must be a dataframe.")
  }
  if (
    !is.character(question_col) ||
      length(question_col) != 1L ||
      !nzchar(question_col)
  ) {
    stop("`question_col` must be a single non-empty string.")
  }
  if (
    !is.character(old_choice) || length(old_choice) != 1L || !nzchar(old_choice)
  ) {
    stop("`old_choice` must be a single non-empty string.")
  }
  if (
    !is.character(new_choice) || length(new_choice) != 1L || !nzchar(new_choice)
  ) {
    stop("`new_choice` must be a single non-empty string.")
  }

  # ---- derive column names ----------------------------------------------------
  old_dummy_col <- paste0(question_col, sm_separator, old_choice)
  new_dummy_col <- paste0(question_col, sm_separator, new_choice)

  # Warn if neither the parent column nor its expected dummy sub-column exist
  if (
    !(question_col %in% names(dataset)) &&
      !(old_dummy_col %in% names(dataset))
  ) {
    warning(
      "rename_choice: neither '",
      question_col,
      "' nor '",
      old_dummy_col,
      "' were found in the dataset. No changes made."
    )
    return(dataset)
  }

  # Warn if the specific dummy sub-column for old_choice does not exist
  if (!(old_dummy_col %in% names(dataset))) {
    warning(
      "rename_choice: dummy sub-column '",
      old_dummy_col,
      "' not found in the dataset. ",
      "Column names will not be renamed, but parent concat and label row ",
      "will still be updated if present."
    )
  }

  # ---- 1. Rename the dummy sub-column name ------------------------------------
  # Only rename the exact dummy column for this question + choice.
  # Use fixed = TRUE so special characters in choice labels (e.g. parentheses,
  # slashes) are matched literally — not as regex patterns.
  col_idx <- match(old_dummy_col, names(dataset))
  if (!is.na(col_idx)) {
    names(dataset)[col_idx] <- new_dummy_col
  }

  # ---- 2. Update the parent concat column values ------------------------------
  # The concat stores choices as space-separated labels; replace every
  # occurrence of old_choice with new_choice using a fixed (literal) match.
  if (question_col %in% names(dataset)) {
    dataset[[question_col]] <- stringr::str_replace_all(
      as.character(dataset[[question_col]]),
      stringr::fixed(old_choice),
      new_choice
    )
  }

  # ---- 3. Update the dummy sub-column values (label-value convention) ---------
  # Under this convention the cell value equals the choice label when selected.
  # After renaming the column in step 1, the column is now at new_dummy_col.
  if (new_dummy_col %in% names(dataset)) {
    dataset[[new_dummy_col]] <- stringr::str_replace_all(
      as.character(dataset[[new_dummy_col]]),
      stringr::fixed(old_choice),
      new_choice
    )
  }

  # ---- 4. Update the ONA label row -------------------------------------------
  # Row 1 of an ONA export is a human-readable label/description row. Any cell
  # in that row that contains old_choice (e.g. the dummy column header text) is
  # updated to new_choice. Operates on ALL columns so label-row text in
  # unrelated columns is not accidentally modified — str_replace_all with
  # fixed() will only touch cells that actually contain old_choice.
  if (isTRUE(skip_label_row) && nrow(dataset) >= 1L) {
    dataset[1L, ] <- lapply(dataset[1L, ], function(x) {
      stringr::str_replace_all(
        as.character(x),
        stringr::fixed(old_choice),
        new_choice
      )
    })
  }

  dataset
}

# NOTE: get_ref_question(), get_value_from_uuid() and get_label_from_name()
# used to be defined twice in this file. The early, non-vectorized copies were
# dead code: R evaluates the file top to bottom, so the later definitions
# below always overwrote them. They have been removed so there is exactly one
# definition of each. See the vectorized versions further down this file.

#' Get Numeric Column Names from XLSForm Survey
#'
#' Extracts the names of columns that are integer or decimal types
#' from the XLSForm survey sheet.
#'
#' @param tool_survey A dataframe containing the XLSForm survey sheet.
#' @return A character vector of column names with numeric types.
get_cols_numeric <- function(tool_survey) {
  tool_survey %>%
    filter(type %in% c("integer", "decimal")) %>%
    pull(name)
}

#' Load Required Packages
#'
#' This function installs (if necessary) and loads all packages required
#' for the cleaningkit package to run. It uses the `pak` package for efficient
#' installation and dependency management.
#'
#' @export
load_packages <- function() {
  # List of core packages required
  core_pkgs <- c(
    "dplyr",
    "stringr",
    "tidyr",
    "openxlsx",
    "srvyr",
    "uuid",
    "rlang",
    "crayon",
    "readxl",
    "purrr",
    "httr",
    "jsonlite",
    "keyring",
    "magrittr",
    "cluster"
  )

  # Install pak if not installed
  if (!requireNamespace("pak", quietly = TRUE)) {
    install.packages("pak")
  }

  # Use pak to install any missing packages
  cat(crayon::yellow(
    "Checking and installing missing packages using 'pak'...\n"
  ))
  pak::pkg_install(core_pkgs)

  # Load all packages
  cat(crayon::yellow("Loading required packages...\n"))
  invisible(lapply(core_pkgs, function(pkg) {
    suppressPackageStartupMessages(do.call(
      library,
      list(pkg, character.only = TRUE)
    ))
  }))

  cat(crayon::green("All required packages loaded successfully!\n"))
}

#' Get Choice Name from Choice Label
#'
#' Looks up the name for a given choice label within a specific list
#' in the XLSForm choices sheet. Automatically looks up the choices sheet
#' in the environment if not explicitly provided.
#'
#' @param list_name The \code{list_name} value to filter by.
#' @param label The choice \code{label} value to look up.
#' @param tool_choices Optional dataframe containing the XLSForm choices sheet.
#'   If \code{NULL}, looks for \code{tool_choices} in the environment.
#' @return The name string for the matching choice, or \code{NA} if not found.
#' @export
get_name_from_label <- function(list_name, label, tool_choices = NULL) {
  # Resolve tool_choices dynamically if NULL
  if (is.null(tool_choices)) {
    if (exists("tool_choices", envir = parent.frame())) {
      tool_choices <- get("tool_choices", envir = parent.frame())
    } else if (exists("tool_choices", envir = .GlobalEnv)) {
      tool_choices <- get("tool_choices", envir = .GlobalEnv)
    } else {
      stop(
        "tool_choices dataframe is not provided and was not found in the environment."
      )
    }
  }

  if (
    !is.data.frame(tool_choices) ||
      !all(c("list_name", "label", "name") %in% colnames(tool_choices))
  ) {
    stop(
      "tool_choices must be a dataframe containing 'list_name', 'label', and 'name' columns."
    )
  }

  match_idx <- which(
    tool_choices$list_name == list_name & tool_choices$label == label
  )
  if (length(match_idx) == 0) {
    return(NA_character_)
  }
  return(tool_choices$name[match_idx[1]])
}

################################################################################

#' Get Choice Label from Choice Name
#'
#' Looks up the label for a given choice name within a specific list
#' in the XLSForm choices sheet. Automatically looks up the choices sheet
#' in the environment if not explicitly provided.
#'
#' @param list.name The \code{list_name} value to filter by.
#' @param name The choice \code{name} value to look up.
#' @param tool_choices Optional dataframe containing the XLSForm choices sheet.
#'   If \code{NULL}, looks for \code{tool_choices} in the environment.
#' @return The label string for the matching choice, or \code{NA} if not found.
#' @export
get_label_from_name <- function(list.name, name, tool_choices = NULL) {
  # Resolve tool_choices dynamically if NULL
  if (is.null(tool_choices)) {
    if (exists("tool_choices", envir = parent.frame())) {
      tool_choices <- get("tool_choices", envir = parent.frame())
    } else if (exists("tool_choices", envir = .GlobalEnv)) {
      tool_choices <- get("tool_choices", envir = .GlobalEnv)
    } else {
      stop(
        "tool_choices dataframe is not provided and was not found in the environment."
      )
    }
  }

  if (
    !is.data.frame(tool_choices) ||
      !all(c("list_name", "label", "name") %in% colnames(tool_choices))
  ) {
    stop(
      "tool_choices must be a dataframe containing 'list_name', 'label', and 'name' columns."
    )
  }

  match_idx <- which(
    tool_choices$list_name == list.name & tool_choices$name == name
  )
  if (length(match_idx) == 0) {
    return(NA_character_)
  }
  return(tool_choices$label[match_idx[1]])
}

################################################################################

#' Get Column Value by UUID
#'
#' Retrieves a value from a specific column for a given UUID. If the UUID
#' contains an underscore (indicating a loop/roster entry), it searches the loop
#' dataset; otherwise it searches the main dataset. This function is fully vectorized,
#' handles missing/empty values gracefully, and automatically looks up datasets
#' in the environment if not explicitly provided.
#'
#' @param uuid A character vector of UUIDs to look up.
#' @param column The column name (scalar character) to retrieve the value from.
#' @param raw_data The main raw dataset dataframe. If \code{NULL}, looks for \code{raw_data} in the environment.
#' @param raw_roster Optional roster dataset dataframe. If \code{NULL}, looks for \code{raw_roster} or \code{raw_loop} in the environment.
#' @param raw_loop Optional loop dataset dataframe. Synonym for \code{raw_roster}.
#' @return A vector of values from the specified column for the matching UUIDs.
#' @export
get_value_from_uuid <- function(
  uuid,
  column,
  raw_data = NULL,
  raw_roster = NULL,
  raw_loop = NULL
) {
  # 1. Validate column argument
  if (
    missing(column) ||
      is.null(column) ||
      is.na(column) ||
      length(column) != 1 ||
      !is.character(column)
  ) {
    stop("The 'column' parameter must be a single, non-empty character string.")
  }

  # 2. Resolve raw_data
  if (is.null(raw_data)) {
    if (exists("raw_data", envir = parent.frame())) {
      raw_data <- get("raw_data", envir = parent.frame())
    } else if (exists("raw_data", envir = .GlobalEnv)) {
      raw_data <- get("raw_data", envir = .GlobalEnv)
    } else {
      stop(
        "raw_data dataframe is not provided and was not found in the environment."
      )
    }
  }

  if (!is.data.frame(raw_data)) {
    stop("raw_data must be a data frame.")
  }

  # 3. Resolve loop/roster dataset
  loop_dataset <- NULL
  if (!is.null(raw_roster)) {
    loop_dataset <- raw_roster
  } else if (!is.null(raw_loop)) {
    loop_dataset <- raw_loop
  } else {
    # Look in parent frame or global environment for raw_roster then raw_loop
    if (exists("raw_roster", envir = parent.frame())) {
      loop_dataset <- get("raw_roster", envir = parent.frame())
    } else if (exists("raw_loop", envir = parent.frame())) {
      loop_dataset <- get("raw_loop", envir = parent.frame())
    } else if (exists("raw_roster", envir = .GlobalEnv)) {
      loop_dataset <- get("raw_roster", envir = .GlobalEnv)
    } else if (exists("raw_loop", envir = .GlobalEnv)) {
      loop_dataset <- get("raw_loop", envir = .GlobalEnv)
    }
  }

  # 4. Helper function to get value for a single UUID
  get_single_value <- function(id, col) {
    if (is.null(id) || is.na(id) || id == "") {
      return(NA)
    }

    # Determine if it's a loop entry
    is_loop <- stringr::str_detect(id, "_")

    if (is_loop) {
      if (is.null(loop_dataset)) {
        stop(
          "UUID '",
          id,
          "' indicates a loop/roster entry, but no raw_roster or raw_loop dataset is available."
        )
      }
      if (!"uuid" %in% colnames(loop_dataset)) {
        stop("The loop/roster dataset does not have a 'uuid' column.")
      }
      if (!col %in% colnames(loop_dataset)) {
        warning(
          "Column '",
          col,
          "' not found in the loop/roster dataset. Returning NA."
        )
        return(NA)
      }
      val <- loop_dataset[[col]][loop_dataset$uuid == id]
      if (length(val) == 0) {
        return(NA)
      }
      return(val[1]) # Return the first match if duplicate UUIDs exist
    } else {
      if (!"uuid" %in% colnames(raw_data)) {
        stop("The raw_data dataset does not have a 'uuid' column.")
      }
      if (!col %in% colnames(raw_data)) {
        warning("Column '", col, "' not found in raw_data. Returning NA.")
        return(NA)
      }
      val <- raw_data[[col]][raw_data$uuid == id]
      if (length(val) == 0) {
        return(NA)
      }
      return(val[1])
    }
  }

  # 5. Vectorized execution
  results <- sapply(
    uuid,
    function(id) get_single_value(id, column),
    USE.NAMES = FALSE
  )
  return(results)
}

################################################################################

#' Add a Choice to a Space-Separated Select Multiple String
#'
#' Vector-safe utility to add a specific choice to a space-separated string of choices.
#' Automatically handles duplicate entries, empty strings, and missing values.
#'
#' @param concat_value A character vector containing space-separated choices.
#' @param choice A character vector of the choice(s) to add.
#' @return A character vector with the choice added.
#' @export
add_choice <- function(concat_value, choice) {
  add_single <- function(cv, ch) {
    if (is.null(ch) || is.na(ch) || ch == "") {
      return(if (is.null(cv) || is.na(cv)) NA_character_ else as.character(cv))
    }
    if (is.null(cv) || is.na(cv) || cv == "") {
      return(as.character(ch))
    }
    l <- stringr::str_split(cv, "\\s+")[[1]]
    l <- sort(unique(c(l, ch)))
    l <- l[l != "" & !is.na(l)]
    if (length(l) == 0) {
      return("")
    }
    return(paste(l, collapse = " "))
  }

  # Ensure character inputs
  concat_value <- if (is.null(concat_value)) {
    NA_character_
  } else {
    as.character(concat_value)
  }
  choice <- if (is.null(choice)) NA_character_ else as.character(choice)

  # Fully vectorized over both vectors
  res <- as.character(mapply(
    add_single,
    concat_value,
    choice,
    USE.NAMES = FALSE
  ))
  return(res)
}

################################################################################

#' Remove a Choice from a Space-Separated Select Multiple String
#'
#' Vector-safe utility to remove a specific choice from a space-separated string of choices.
#' Automatically handles empty strings and missing values.
#'
#' @param concat_value A character vector containing space-separated choices.
#' @param choice A character vector of the choice(s) to remove.
#' @return A character vector with the choice removed.
#' @export
remove_choice <- function(concat_value, choice) {
  remove_single <- function(cv, ch) {
    if (is.null(ch) || is.na(ch) || ch == "") {
      return(if (is.null(cv) || is.na(cv)) NA_character_ else as.character(cv))
    }
    if (is.null(cv) || is.na(cv) || cv == "") {
      return("")
    }
    l <- stringr::str_split(cv, "\\s+")[[1]]
    l <- l[l != ch & l != "" & !is.na(l)]
    if (length(l) == 0) {
      return("")
    }
    return(paste(l, collapse = " "))
  }

  # Ensure character inputs
  concat_value <- if (is.null(concat_value)) {
    NA_character_
  } else {
    as.character(concat_value)
  }
  choice <- if (is.null(choice)) NA_character_ else as.character(choice)

  # Fully vectorized over both vectors
  res <- as.character(mapply(
    remove_single,
    concat_value,
    choice,
    USE.NAMES = FALSE
  ))
  return(res)
}

################################################################################

#' Extract Referenced Question Name from Relevance Expression
#'
#' Parses a relevance expression string to extract the \strong{first} referenced
#' question name enclosed in curly braces (e.g., \code{${question_name}}).
#' This function is fully vectorized.
#'
#' Note that a compound relevance expression references more than one question,
#' e.g. \code{${Q31} = 'kenya' and selected(${Q32}, 'other')} returns
#' \code{"Q31"} because that is the first reference. To list every reference use
#' \code{.relevant_refs()}, and to work out which reference is the parent of an
#' "other" text question use \code{.resolve_ref_question()}.
#'
#' @param x A character vector containing relevance expressions.
#' @return A character vector of the extracted question names, or \code{NA} if not found.
#' @export
get_ref_question <- function(x) {
  if (is.null(x)) {
    return(NA_character_)
  }
  return(stringr::str_extract(as.character(x), "(?<=\\{)[^}]+"))
}

################################################################################

#' All Question References in a Relevance Expression
#'
#' Returns every \code{${question}} reference found in a single relevance
#' expression, in the order they appear.
#'
#' @param x A single relevance expression (length-1 character vector).
#' @return A character vector of question names, possibly empty.
#' @keywords internal
.relevant_refs <- function(x) {
  if (is.null(x) || length(x) == 0) {
    return(character(0))
  }
  x <- as.character(x)[1]
  if (is.na(x) || !nzchar(x)) {
    return(character(0))
  }
  m <- stringr::str_match_all(x, "\\$\\{([^}]+)\\}")[[1]]
  if (nrow(m) == 0) {
    return(character(0))
  }
  trimws(m[, 2])
}

################################################################################

#' Pair Each Question Reference in a Relevance Expression With Its Option
#'
#' Splits a relevance expression into \code{(question, option)} pairs by
#' matching each \code{${question}} reference with the value it is compared
#' against. Handles the common XLSForm shapes:
#' \code{selected(${Q32}, 'other')}, \code{${Q32} = 'other'} and
#' \code{${Q32} = 96}. Compound expressions joined with \code{and}/\code{or}
#' return one row per clause, which is what makes it possible to pick the
#' clause that belongs to a given parent question instead of blindly taking
#' the first quoted string in the expression.
#'
#' @param x A single relevance expression (length-1 character vector).
#' @return A dataframe with columns \code{ref} and \code{option} (0 rows when
#'   nothing matches).
#' @keywords internal
.relevant_ref_options <- function(x) {
  empty <- data.frame(
    ref = character(0),
    option = character(0),
    stringsAsFactors = FALSE
  )
  if (is.null(x) || length(x) == 0) {
    return(empty)
  }
  x <- as.character(x)[1]
  if (is.na(x) || !nzchar(x)) {
    return(empty)
  }

  # Quoted comparisons: ${Q32} = 'other' / selected(${Q32}, 'other')
  # [^$]*? stops the match from running past the next ${...} reference, so each
  # question is paired with the nearest quoted value that follows it.
  m <- stringr::str_match_all(
    x,
    "\\$\\{([^}]+)\\}[^$]*?['\"]([^'\"]*)['\"]"
  )[[1]]
  pairs <- if (nrow(m) > 0) {
    data.frame(
      ref = trimws(m[, 2]),
      option = m[, 3],
      stringsAsFactors = FALSE
    )
  } else {
    empty
  }

  # Unquoted numeric comparisons: ${Q32} = 96 / selected(${Q32}, 96)
  m_num <- stringr::str_match_all(
    x,
    "\\$\\{([^}]+)\\}\\s*(?:,|!?=|==)\\s*(-?[0-9]+(?:\\.[0-9]+)?)"
  )[[1]]
  if (nrow(m_num) > 0) {
    num_pairs <- data.frame(
      ref = trimws(m_num[, 2]),
      option = m_num[, 3],
      stringsAsFactors = FALSE
    )
    # quoted matches win when the same reference appears in both passes
    num_pairs <- num_pairs[!(num_pairs$ref %in% pairs$ref), , drop = FALSE]
    pairs <- rbind(pairs, num_pairs)
  }

  pairs
}

################################################################################

#' Candidate Parent Question Names for an "Other" Text Question
#'
#' In the 4Mi tools an "other" text question is named after its parent question
#' with a numeric suffix appended, so the parent of \code{Q32_1} is \code{Q32}
#' and the parent of \code{Q86_b_1} is \code{Q86_b}. This strips trailing
#' \code{_<digits>} suffixes one at a time and returns the candidates from the
#' closest to the furthest (\code{Q45_3_1} -> \code{Q45_3}, \code{Q45}).
#'
#' @param name A single question name.
#' @param max_depth Maximum number of suffixes to strip. Default \code{3}.
#' @return A character vector of candidate parent names, possibly empty.
#' @keywords internal
.parent_name_candidates <- function(name, max_depth = 3) {
  out <- character(0)
  if (is.null(name) || length(name) == 0) {
    return(out)
  }
  cur <- as.character(name)[1]
  if (is.na(cur)) {
    return(out)
  }
  for (i in seq_len(max_depth)) {
    nxt <- sub("_[0-9]+$", "", cur)
    if (identical(nxt, cur) || !nzchar(nxt)) {
      break
    }
    out <- c(out, nxt)
    cur <- nxt
  }
  out
}

################################################################################

#' Resolve the Parent Question of an "Other" Text Question
#'
#' Works out which question an "other" text question belongs to. The naming
#' convention is treated as the primary source of truth (\code{Q32_1} ->
#' \code{Q32}, \code{Q86_b_1} -> \code{Q86_b}) and the relevance expression is
#' only consulted when the convention does not resolve to a question that
#' actually exists in the survey sheet.
#'
#' This exists because reading the relevance expression alone is unreliable:
#' compound expressions such as
#' \code{${Q31} = 'kenya' and selected(${Q32}, 'other')} reference several
#' questions and the first one is usually a filter, not the parent.
#'
#' Resolution order, per row:
#' \enumerate{
#'   \item a name-convention candidate that is a \code{select_one} /
#'     \code{select_multiple} question and is also referenced in the relevance
#'     expression (\code{"name_and_relevance"});
#'   \item a name-convention candidate that is a \code{select_*} question in
#'     the survey sheet (\code{"name"});
#'   \item a \code{select_*} question that the relevance expression compares
#'     against an "other"-looking option (\code{"relevance"});
#'   \item a name-convention candidate, not a select question, that the
#'     relevance expression also references (\code{"name_and_relevance"});
#'   \item a name-convention candidate that exists in the survey sheet
#'     (\code{"name"});
#'   \item any question referenced by the relevance expression, preferring an
#'     "other"-looking clause, then a \code{select_*} question, then the last
#'     reference (\code{"relevance"});
#'   \item the question's own name (\code{"self"}).
#' }
#'
#' Steps 1-3 are what put a select question ahead of a same-named non-select
#' one: \code{Q90_1} sitting under an integer \code{Q90} but relevant on
#' \code{selected(${Q78}, 'other')} resolves to \code{Q78}, because only a
#' select question has choices to recode an "other" response into.
#'
#' @param name Character vector of "other" text question names.
#' @param relevant Character vector of relevance expressions, same length as
#'   \code{name}. \code{NULL} is treated as all missing.
#' @param tool_survey The XLSForm survey sheet, used to check that a candidate
#'   parent exists and to read \code{q_type} when available.
#' @return A dataframe with one row per input: \code{name},
#'   \code{ref_question}, \code{resolved_via} and \code{option_other} (the
#'   option the parent is compared against in the relevance expression).
#' @keywords internal
.resolve_ref_question <- function(name, relevant, tool_survey) {
  name <- as.character(name)
  n <- length(name)

  if (is.null(relevant)) {
    relevant <- rep(NA_character_, n)
  }
  relevant <- as.character(relevant)
  length(relevant) <- n

  survey_names <- as.character(tool_survey$name)
  q_types <- if ("q_type" %in% names(tool_survey)) {
    as.character(tool_survey$q_type)
  } else {
    rep(NA_character_, length(survey_names))
  }

  is_select <- function(nm) {
    idx <- match(nm, survey_names)
    !is.na(idx) &
      !is.na(q_types[idx]) &
      grepl("^select", q_types[idx], ignore.case = TRUE)
  }

  ref <- rep(NA_character_, n)
  via <- rep(NA_character_, n)
  opt <- rep(NA_character_, n)

  for (i in seq_len(n)) {
    nm <- name[i]
    refs <- .relevant_refs(relevant[i])
    pairs <- .relevant_ref_options(relevant[i])
    cands <- .parent_name_candidates(nm)

    chosen <- NA_character_
    how <- NA_character_

    agree <- cands[cands %in% refs]
    known_cands <- cands[cands %in% survey_names]
    known_refs <- refs[refs %in% survey_names]
    other_like <- pairs$ref[grepl("other", pairs$option, ignore.case = TRUE)]

    # 1. naming convention and relevance expression agree on a select_*
    if (length(agree) > 0) {
      selects <- agree[vapply(agree, is_select, logical(1))]
      if (length(selects) > 0) {
        chosen <- selects[1]
        how <- "name_and_relevance"
      }
    }

    # 2. naming convention alone, when it points at a select_* question
    if (is.na(chosen) && length(known_cands) > 0) {
      selects <- known_cands[vapply(known_cands, is_select, logical(1))]
      if (length(selects) > 0) {
        chosen <- selects[1]
        how <- "name"
      }
    }

    # 3. a select_* question the relevance expression tests for an "other"
    #    option - this beats a name candidate that exists but is not a select,
    #    since only a select question has choices to recode into
    if (is.na(chosen) && length(other_like) > 0) {
      selects <- other_like[vapply(other_like, is_select, logical(1))]
      if (length(selects) > 0) {
        chosen <- selects[length(selects)]
        how <- "relevance"
      }
    }

    # 4. naming convention and relevance agree on a non-select question
    #    (also the path taken when the sheet has no q_type column)
    if (is.na(chosen) && length(agree) > 0) {
      chosen <- agree[1]
      how <- "name_and_relevance"
    }

    # 5. naming convention pointing at a non-select question
    if (is.na(chosen) && length(known_cands) > 0) {
      chosen <- known_cands[1]
      how <- "name"
    }

    # 6. any question referenced by the relevance expression
    if (is.na(chosen) && length(refs) > 0) {
      pool <- if (length(known_refs) > 0) known_refs else refs
      others <- other_like[other_like %in% pool]
      selects <- pool[vapply(pool, is_select, logical(1))]
      chosen <- if (length(others) > 0) {
        others[length(others)]
      } else if (length(selects) > 0) {
        selects[length(selects)]
      } else {
        pool[length(pool)]
      }
      how <- "relevance"
    }

    # 7. last resort: the question is its own reference
    if (is.na(chosen)) {
      chosen <- nm
      how <- "self"
    }

    ref[i] <- chosen
    via[i] <- how

    if (nrow(pairs) > 0) {
      hit <- which(pairs$ref == chosen)
      if (length(hit) > 0) {
        opt[i] <- pairs$option[hit[length(hit)]]
      }
    }
  }

  data.frame(
    name = name,
    ref_question = ref,
    resolved_via = via,
    option_other = opt,
    stringsAsFactors = FALSE
  )
}

################################################################################

#' Option a Parent Question Is Compared Against in a Relevance Expression
#'
#' Returns the choice name that \code{ref} is compared against inside
#' \code{relevant} - i.e. the "other" option that should be dropped from the
#' recoding dropdown. Anchoring on \code{ref} avoids the greedy
#' \code{str_extract(relevant, "'.*'")} behaviour, which over-captures on
#' compound expressions (returning \code{kenya' and selected(${Q32}, 'other}
#' instead of \code{other}).
#'
#' @param relevant Character vector of relevance expressions.
#' @param ref Character vector of parent question names, recycled to the length
#'   of \code{relevant}.
#' @return A character vector of option names, \code{NA} where none is found.
#' @keywords internal
.relevant_option_for_ref <- function(relevant, ref) {
  n <- max(length(relevant), length(ref))
  if (n == 0) {
    return(character(0))
  }
  relevant <- as.character(relevant)
  ref <- as.character(ref)
  length(relevant) <- n
  length(ref) <- n

  out <- rep(NA_character_, n)
  for (i in seq_len(n)) {
    pairs <- .relevant_ref_options(relevant[i])
    if (nrow(pairs) == 0) {
      next
    }
    hit <- which(pairs$ref == ref[i])
    if (length(hit) > 0) {
      out[i] <- pairs$option[hit[length(hit)]]
      next
    }
    other_like <- which(grepl("other", pairs$option, ignore.case = TRUE))
    out[i] <- if (length(other_like) > 0) {
      pairs$option[other_like[length(other_like)]]
    } else {
      pairs$option[1]
    }
  }
  out
}

################################################################################

#' Apply Tool Labels
#'
#' Renames the analysis output options columns using an XLSForm tool choices dictionary before a user can save the analysis.
#'
#' @param dataset The dataset to modify
#' @param column_name The name of the column to relabel
#' @param tool_choices The XLSForm choices sheet dataframe
#' @return The updated dataset
#' @export
apply_tool_labels <- function(dataset, column_name, tool_choices) {
  # 1. Check if the column actually exists in the dataset
  if (!column_name %in% colnames(dataset)) {
    stop(paste(
      "Error: The column",
      column_name,
      "does not exist in the dataset."
    ))
  }

  # 2. Create the dictionary from the choices sheet
  label_lookup <- tool_choices %>%
    select(name, label) %>%
    mutate(
      name = as.character(name),
      label = as.character(label)
    ) %>%
    filter(!is.na(name) & name != "") %>%
    # Ensure there is only one entry per machine name globally
    distinct(name, .keep_all = TRUE)

  # Create a named vector: c("machine_name" = "Readable Label")
  dict_vector <- setNames(label_lookup$label, label_lookup$name)

  # 3. Apply the dictionary to the target column in the dataset
  dataset_updated <- dataset %>%
    mutate(
      # Temporarily ensure the column is a character vector for safe matching
      !!sym(column_name) := as.character(!!sym(column_name)),

      # Replace names with labels. coalesce() keeps the original value if no match is found.
      !!sym(column_name) := coalesce(
        dict_vector[!!sym(column_name)],
        !!sym(column_name)
      )
    )

  return(dataset_updated)
}

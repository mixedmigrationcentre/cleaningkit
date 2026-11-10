#' Default question sets for validate_repeated_entries()
#'
#' Returns the three looped question sets of the 4Mi XLSForm that
#' \code{\link{validate_repeated_entries}} checks by default. Use it as a
#' starting point when your tool numbers the questions differently: change,
#' add or drop sets and pass the result to the \code{sections} argument.
#'
#' @details
#' Each set is a list with:
#' \describe{
#'   \item{\code{label}}{Name used in the issue message, e.g.
#'     \code{"Main stops"}.}
#'   \item{\code{item}}{What one entry is called in the issue message, e.g.
#'     \code{"stop"} gives "stop 2 (Q59/Q60)".}
#'   \item{\code{slots}}{A list with one named character vector per entry, in
#'     the order they are asked. Every slot of a set must have the same length
#'     and its columns in the same order, so the columns of one entry can move
#'     into the entry above it.}
#' }
#'
#' The names inside a slot decide which columns are compared:
#' \describe{
#'   \item{\code{country}}{Required. The country question. An entry whose
#'     country is blank or one of \code{stop_values} ends the list.}
#'   \item{\code{place}}{Optional. When present, an entry only counts as a
#'     repeat if both country and place match the entry before it.}
#'   \item{\code{country_other}, \code{place_other}}{Optional. The
#'     "please specify" text. It is compared too (ignoring case and spaces), so
#'     two "Other" answers only match when the typed text matches.}
#' }
#' Columns without a name (e.g. why_stop, risks, perpetrators and their
#' "please specify" texts) are not compared but move with their entry.
#' Select-multiple sub-columns (\code{Q58/1}, \code{Q58/2}, ...) are found
#' automatically and move with their parent column.
#'
#' The defaults are:
#' \describe{
#'   \item{\code{countries_transited}}{Q47 to Q54, compared on country.}
#'   \item{\code{main_stops}}{Q56 to Q70 in five blocks of country, place and
#'     why_stop, compared on country + place.}
#'   \item{\code{dangerous_locations}}{Q98 to Q117 in five blocks of country,
#'     place, risks and perpetrators, compared on country + place. Q98/Q99 is
#'     the first dangerous location, so Q102 is checked against it.}
#' }
#'
#' @return A named list of question sets.
#' @examples
#' sets <- ck_repeated_entries_sections()
#' names(sets)
#'
#' # run only the countries transited check
#' sets <- sets["countries_transited"]
#' @export
ck_repeated_entries_sections <- function() {
  q <- function(n, suffix = "") paste0("Q", n, suffix)

  countries <- lapply(47:54, function(n) {
    c(country = q(n), country_other = q(n, "_1"))
  })

  main_stops <- lapply(c(56, 59, 62, 65, 68), function(n) {
    c(
      country = q(n),
      country_other = q(n, "_1"),
      place = q(n + 1),
      place_other = q(n + 1, "_1"),
      q(n + 2),
      q(n + 2, "_1")
    )
  })

  dangerous <- lapply(c(98, 102, 106, 110, 114), function(n) {
    c(
      country = q(n),
      place = q(n + 1),
      place_other = q(n + 1, "_1"),
      q(n + 1, "_2"),
      q(n + 2),
      q(n + 2, "_1"),
      q(n + 3),
      q(n + 3, "_1")
    )
  })

  list(
    countries_transited = list(
      label = "Countries transited",
      item = "country",
      slots = countries
    ),
    main_stops = list(
      label = "Main stops",
      item = "stop",
      slots = main_stops
    ),
    dangerous_locations = list(
      label = "Dangerous locations",
      item = "location",
      slots = dangerous
    )
  )
}

#' Validate Back-to-Back Repeated Entries in Looped Questions
#'
#' Flags looped journey questions where an entry repeats the one asked just
#' before it, and writes the fix to the log: remove the repeat, move the later
#' entries up one place and close the list with None.
#'
#' @details
#' By default three question sets are checked (see
#' \code{\link{ck_repeated_entries_sections}}):
#' \itemize{
#'   \item \strong{Countries transited} (Q47 to Q54): the next country is the
#'     same as the one before.
#'   \item \strong{Main stops} (Q56 to Q70): the next stop has the same
#'     country \emph{and} place as the one before. Same country with a
#'     different place is kept.
#'   \item \strong{Dangerous locations} (Q98 to Q117): same rule as main stops.
#' }
#'
#' Only entries that follow each other count. \code{Kenya, Kenya, Uganda}
#' becomes \code{Kenya, Uganda, None}; \code{Kenya, Uganda, Tanzania, Kenya}
#' is left as it is. A run such as \code{Kenya, Kenya, Kenya} collapses to one
#' \code{Kenya}.
#'
#' The form only opens the next entry when the one before is not None or
#' Refused, so blanking a repeat in the middle would leave the record breaking
#' the form's own skip logic. Every column of the later entries is therefore
#' moved up - the "please specify" texts, calculates and select-multiple
#' sub-columns included. If the list ended in a closing answer (None, Refused)
#' that answer moves up too; if every slot was filled, the freed slot gets
#' \code{none_value} and its other columns become blank.
#'
#' Blank values and \code{stop_values} are never treated as repeats.
#'
#' The function only writes a log - the data is not changed. Each log row is
#' one cell that has to change, and its issue says what was repeated and the
#' suggested new value, so the reviewer can fill in \code{New value} and
#' \code{Action taken} on the cleaning log and \code{apply_cleaning_log()}
#' applies it. All rows from one record and question set share a
#' \code{check_binding}, so they get one colour on the cleaning log.
#'
#' @param dataset A dataframe or a list containing a dataframe named
#'   \code{checked_dataset}.
#' @param uuid_column Name of the uuid column. Default \code{"_uuid"}.
#' @param sections The question sets to check, in the shape returned by
#'   \code{\link{ck_repeated_entries_sections}} (the default). Pass a subset
#'   to run fewer sets, or your own list for a tool with other question
#'   names.
#' @param none_value The value that means None. Written into the freed slot
#'   when the list had no closing answer. Default \code{"996"}.
#' @param stop_values Values that end the list (None, Don't know, Refused).
#'   They are never treated as repeats. \code{none_value} is always included.
#'   Default \code{c("996", "998", "999")}.
#' @param sm_separator The separator between a select-multiple question and
#'   its choice in the sub-column names. Default \code{"/"}.
#' @param log_name Name of the log in the returned list. Default
#'   \code{"repeated_entries_log"}.
#' @param skip_label_row Logical. If \code{TRUE} (the default), the first row
#'   of the dataset is removed before validation. ONA exports include a
#'   label/description row immediately after the header that should not be
#'   treated as survey data.
#'
#' @return A list containing:
#'   \item{checked_dataset}{The original dataset with one logical flag column
#'     per question set (\code{repeated_<set name>}, \code{TRUE} = flagged).}
#'   \item{<log_name>}{The log, with columns \code{uuid}, \code{old_value},
#'     \code{question}, \code{issue} and \code{check_binding}.}
#' @examples
#' \dontrun{
#' repeated_entries_log <- cleaningkit::validate_repeated_entries(
#'   dataset = raw_data,
#'   uuid_column = "_uuid",
#'   log_name = "repeated_entries_log",
#'   skip_label_row = TRUE
#' )
#'
#' # only the main stops
#' sets <- cleaningkit::ck_repeated_entries_sections()["main_stops"]
#' repeated_entries_log <- cleaningkit::validate_repeated_entries(
#'   dataset = raw_data,
#'   sections = sets
#' )
#' }
#' @export
validate_repeated_entries <- function(
  dataset,
  uuid_column = "_uuid",
  sections = ck_repeated_entries_sections(),
  none_value = "996",
  stop_values = c("996", "998", "999"),
  sm_separator = "/",
  log_name = "repeated_entries_log",
  skip_label_row = TRUE
) {
  # ---- input validation ----
  if (is.data.frame(dataset)) {
    dataset <- list(checked_dataset = dataset)
  }
  if (!("checked_dataset" %in% names(dataset))) {
    stop("Cannot identify the dataset in the list.")
  }
  full_df <- dataset[["checked_dataset"]]
  if (!(uuid_column %in% names(full_df))) {
    stop(paste0("Cannot find ", uuid_column, " in the names of the dataset"))
  }
  sections <- .ck_check_sections(sections)
  none_value <- as.character(none_value)
  stop_norm <- .ck_norm_entry(unique(c(none_value, stop_values)))

  df <- full_df
  if (skip_label_row && nrow(df) > 0) {
    df <- df[-1, , drop = FALSE]
  }

  # ---- warn once about columns the dataset does not have ----
  all_cols <- unique(unlist(lapply(sections, function(s) unlist(s$slots))))
  missing_cols <- setdiff(all_cols, names(df))
  if (length(missing_cols) > 0) {
    warning(
      "validate_repeated_entries: these columns are not in the dataset and ",
      "are treated as blank: ",
      paste(missing_cols, collapse = ", ")
    )
  }

  logs <- list()
  for (sid in names(sections)) {
    res <- .ck_repeated_section(
      df = df,
      uuid_column = uuid_column,
      section_id = sid,
      section = sections[[sid]],
      none_value = none_value,
      stop_norm = stop_norm,
      sm_separator = sm_separator
    )
    logs[[sid]] <- res$log

    flag_col <- rep(FALSE, nrow(full_df))
    if (skip_label_row && nrow(full_df) > 0) {
      flag_col[-1] <- res$flag
    } else {
      flag_col <- res$flag
    }
    full_df[[paste0("repeated_", sid)]] <- flag_col
  }

  log <- do.call(rbind, c(list(.ck_empty_repeated_log()), unname(logs)))
  rownames(log) <- NULL

  message(
    "validate_repeated_entries: checked ",
    length(sections),
    " question set(s); ",
    nrow(log),
    " log row(s) produced across ",
    length(unique(log$uuid)),
    " unique record(s)."
  )

  dataset[["checked_dataset"]] <- full_df
  dataset[[log_name]] <- log
  dataset
}

#' Empty log in the repeated-entries shape
#' @keywords internal
#' @noRd
.ck_empty_repeated_log <- function() {
  data.frame(
    uuid = character(0),
    old_value = character(0),
    question = character(0),
    issue = character(0),
    check_binding = character(0),
    stringsAsFactors = FALSE
  )
}

#' Check and complete the `sections` argument
#' @keywords internal
#' @noRd
.ck_check_sections <- function(sections) {
  if (!is.list(sections) || length(sections) == 0) {
    stop("`sections` must be a non-empty list of question sets.")
  }
  if (is.null(names(sections)) || any(!nzchar(names(sections)))) {
    stop("Every question set in `sections` must be named.")
  }
  for (sid in names(sections)) {
    s <- sections[[sid]]
    slots <- s$slots
    if (!is.list(slots) || length(slots) < 2) {
      stop("Question set '", sid, "' needs at least two slots in `slots`.")
    }
    lens <- vapply(slots, length, integer(1))
    if (length(unique(lens)) != 1) {
      stop(
        "Every slot of question set '",
        sid,
        "' must have the same number of columns."
      )
    }
    has_country <- vapply(
      slots,
      function(x) "country" %in% names(x),
      logical(1)
    )
    if (!all(has_country)) {
      stop("Every slot of question set '", sid, "' needs a `country` column.")
    }
    roles <- lapply(slots, function(x) {
      nm <- names(x)
      nm[is.na(nm)] <- ""
      nm
    })
    if (!all(vapply(roles, identical, logical(1), roles[[1]]))) {
      stop(
        "Every slot of question set '",
        sid,
        "' must name its columns in the same order."
      )
    }
    if (is.null(s$label)) {
      s$label <- sid
    }
    if (is.null(s$item)) {
      s$item <- "entry"
    }
    sections[[sid]] <- s
  }
  sections
}

#' Normalise values before comparing entries
#'
#' Blank and NA become "", case and repeated spaces are ignored, and a whole
#' number read as "996.0" compares equal to "996".
#' @keywords internal
#' @noRd
.ck_norm_entry <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  x <- tolower(trimws(gsub("\\s+", " ", x)))
  sub("^([0-9]+)\\.0+$", "\\1", x)
}

#' Read a column as character, all NA when the dataset does not have it
#' @keywords internal
#' @noRd
.ck_get_col <- function(df, col) {
  if (col %in% names(df)) {
    as.character(df[[col]])
  } else {
    rep(NA_character_, nrow(df))
  }
}

#' Check one question set
#' @keywords internal
#' @noRd
.ck_repeated_section <- function(
  df,
  uuid_column,
  section_id,
  section,
  none_value,
  stop_norm,
  sm_separator
) {
  slots <- section$slots
  n_slots <- length(slots)
  n_rows <- nrow(df)
  key_roles <- intersect(
    c("country", "country_other", "place", "place_other"),
    names(slots[[1]])
  )

  # ---- per-slot comparison key and status, vectorised over records ----
  key <- matrix("", n_rows, n_slots)
  country <- matrix("", n_rows, n_slots)
  for (j in seq_len(n_slots)) {
    parts <- lapply(key_roles, function(r) {
      .ck_norm_entry(.ck_get_col(df, slots[[j]][[r]]))
    })
    key[, j] <- do.call(paste, c(parts, sep = "\u001f"))
    country[, j] <- .ck_norm_entry(.ck_get_col(df, slots[[j]][["country"]]))
  }
  is_real <- country != "" & !(country %in% stop_norm)
  dim(is_real) <- dim(country)

  # number of real entries before the first blank / closing answer
  chain_len <- integer(n_rows)
  alive <- rep(TRUE, n_rows)
  for (j in seq_len(n_slots)) {
    alive <- alive & is_real[, j]
    chain_len <- chain_len + alive
  }

  # an entry is a repeat when it equals the one straight before it
  dup <- matrix(FALSE, n_rows, n_slots)
  for (j in 2:n_slots) {
    dup[, j] <- j <= chain_len & key[, j] == key[, j - 1]
  }
  flag <- rowSums(dup) > 0
  if (!any(flag)) {
    return(list(flag = flag, log = .ck_empty_repeated_log()))
  }

  # ---- every column of a slot, with its select-multiple sub-columns ----
  slot_cols <- lapply(slots, function(s) {
    lapply(unname(s), function(col) {
      subs <- .sm_sub_cols(df, col, sm_separator)
      list(
        col = col,
        subs = stats::setNames(
          subs,
          substring(subs, nchar(col) + nchar(sm_separator) + 1)
        )
      )
    })
  })
  ref <- function(j) {
    cols <- slots[[j]][intersect(c("country", "place"), names(slots[[j]]))]
    paste(cols, collapse = "/")
  }
  show <- function(i, j) {
    v <- vapply(
      slots[[j]][key_roles],
      function(col) .ck_get_col(df, col)[i],
      character(1)
    )
    v <- trimws(v[!is.na(v) & nzchar(trimws(v))])
    paste0("'", paste(v, collapse = " / "), "'")
  }
  value_at <- function(i, j, p, sub = NULL) {
    if (is.null(sub)) {
      return(.ck_get_col(df, slot_cols[[j]][[p]]$col)[i])
    }
    src <- slot_cols[[j]][[p]]$subs[sub]
    if (is.na(src)) NA_character_ else .ck_get_col(df, src)[i]
  }

  uuids <- as.character(df[[uuid_column]])
  rows <- list()

  for (i in which(flag)) {
    len <- chain_len[i]
    kept <- c(1L, which(!dup[i, seq_len(len)][-1]) + 1L)
    has_closing <- len < n_slots && country[i, len + 1] %in% stop_norm
    sources <- if (has_closing) c(kept, len + 1L) else kept
    region_end <- if (has_closing) len + 1L else len
    first_dup <- which(dup[i, ])[1]

    # one line naming every repeat in this record
    dropped <- which(dup[i, ])
    what <- vapply(
      dropped,
      function(j) {
        paste0(
          section$item,
          " ",
          j,
          " (",
          ref(j),
          ") is the same as ",
          section$item,
          " ",
          j - 1,
          " (",
          ref(j - 1),
          ") ",
          show(i, j)
        )
      },
      character(1)
    )
    closing <- if (
      has_closing && country[i, len + 1] != .ck_norm_entry(none_value)
    ) {
      paste0(
        "keep the closing answer (",
        trimws(.ck_get_col(df, slots[[len + 1]][["country"]])[i]),
        ")"
      )
    } else {
      paste0("close the list with None (", none_value, ")")
    }
    base_issue <- paste0(
      "[",
      section$label,
      "] Back-to-back repeat: ",
      paste(what, collapse = "; "),
      ". Remove the repeat, move the later entries up one place and ",
      closing,
      "."
    )
    binding <- paste(paste0("repeated_", section_id), uuids[i], sep = " ~/~ ")

    for (t in first_dup:region_end) {
      src <- if (t <= length(sources)) sources[t] else NA_integer_
      is_none_slot <- is.na(src) && t == length(sources) + 1L && !has_closing

      for (p in seq_along(slot_cols[[t]])) {
        target <- slot_cols[[t]][[p]]
        is_country <- identical(target$col, slots[[t]][["country"]])
        cells <- c(
          list(list(col = target$col, sub = NULL)),
          lapply(names(target$subs), function(sf) {
            list(col = target$subs[[sf]], sub = sf)
          })
        )
        for (cell in cells) {
          if (!(cell$col %in% names(df))) {
            next
          }
          old <- .ck_get_col(df, cell$col)[i]
          new <- if (!is.na(src)) {
            value_at(i, src, p, cell$sub)
          } else if (is_none_slot && is_country && is.null(cell$sub)) {
            none_value
          } else {
            NA_character_
          }
          if (identical(.ck_norm_entry(old), .ck_norm_entry(new))) {
            next
          }
          rows[[length(rows) + 1]] <- data.frame(
            uuid = uuids[i],
            old_value = old,
            question = cell$col,
            issue = paste0(
              base_issue,
              " Suggested new value: ",
              if (is.na(new) || !nzchar(trimws(new))) {
                "blank"
              } else {
                paste0("'", new, "'")
              },
              "."
            ),
            check_binding = binding,
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }

  log <- if (length(rows) > 0) {
    do.call(rbind, rows)
  } else {
    .ck_empty_repeated_log()
  }
  list(flag = flag, log = log)
}

#' Fill in the repeated-entry rows of a reviewed cleaning log
#'
#' Used by \code{apply_cleaning_log()} when
#' \code{apply_repeated_entries = TRUE}. Finds the rows written by
#' \code{validate_repeated_entries()} - from the issue text, and the
#' \code{repeated_*} check binding when the column is there - and sets their
#' action and new value to the suggestion in the issue, whatever the reviewer
#' filled in. Rows whose action is in \code{keep_actions} (discard) are left
#' alone.
#'
#' @return A list with \code{cleaning_log}, \code{n} (rows filled in) and
#'   \code{n_changed} (of those, rows where the reviewer had put something
#'   else).
#' @keywords internal
#' @noRd
.ck_force_repeated_entries <- function(
  cleaning_log,
  action_col,
  new_value_col,
  issue_col,
  binding_col,
  change_action,
  blank_action,
  keep_actions
) {
  none <- list(cleaning_log = cleaning_log, n = 0L, n_changed = 0L)
  if (!(issue_col %in% names(cleaning_log)) || nrow(cleaning_log) == 0) {
    return(none)
  }

  issue <- as.character(cleaning_log[[issue_col]])
  issue[is.na(issue)] <- ""
  pattern <- paste0(
    "^\\[[^]]+\\] Back-to-back repeat: .* ",
    "Suggested new value: ('.*'|blank)\\.$"
  )
  is_rep <- grepl(pattern, issue)

  if (binding_col %in% names(cleaning_log)) {
    binding <- trimws(as.character(cleaning_log[[binding_col]]))
    no_binding <- is.na(binding) | binding %in% c("", "NA")
    is_rep <- is_rep & (no_binding | startsWith(binding, "repeated_"))
  }

  action <- trimws(tolower(as.character(cleaning_log[[action_col]])))
  action[is.na(action)] <- ""
  is_rep <- is_rep & !(action %in% tolower(keep_actions))
  if (!any(is_rep)) {
    return(none)
  }

  suggested <- sub(pattern, "\\1", issue[is_rep])
  is_blank <- suggested == "blank"
  value <- ifelse(
    is_blank,
    NA_character_,
    sub("^'(.*)'$", "\\1", suggested)
  )
  new_action <- ifelse(is_blank, blank_action, change_action)

  old_value <- as.character(cleaning_log[[new_value_col]])[is_rep]
  old_value[is.na(old_value)] <- ""
  cmp_value <- ifelse(is.na(value), "", value)
  n_changed <- sum(
    action[is_rep] != tolower(new_action) | trimws(old_value) != cmp_value
  )

  cleaning_log[[action_col]] <- as.character(cleaning_log[[action_col]])
  cleaning_log[[new_value_col]] <- as.character(cleaning_log[[new_value_col]])
  cleaning_log[[action_col]][is_rep] <- new_action
  cleaning_log[[new_value_col]][is_rep] <- value

  list(
    cleaning_log = cleaning_log,
    n = sum(is_rep),
    n_changed = n_changed
  )
}

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
#'   \item{\code{scope}}{\code{"adjacent"} (the default) compares each entry
#'     with the one straight before it. \code{"any"} compares it with every
#'     earlier entry, so the same location cannot appear twice anywhere in the
#'     loop.}
#'   \item{\code{country_lists}, \code{place_lists}}{Optional. Names of the
#'     XLSForm choice lists the country and place questions use. With
#'     \code{tool_choices}, typed "Other" answers are matched against every
#'     label of these lists, in every language of the form.}
#'   \item{\code{place_filter}}{Optional. The choices column that links a place
#'     to its country (the \code{choice_filter} column), \code{"cf"} in 4Mi.}
#' }
#'
#' The names inside a slot decide which columns are compared:
#' \describe{
#'   \item{\code{country}}{Required. The country question. An entry whose
#'     country is blank or one of \code{stop_values} ends the list.}
#'   \item{\code{place}}{Optional. When present, an entry only counts as a
#'     repeat if both country and place match.}
#'   \item{\code{country_other}, \code{place_other}}{Optional. The
#'     "please specify" answer. It is compared too, so two "Other" answers only
#'     match when what was typed or picked matches.}
#' }
#' Columns without a name (e.g. why_stop, risks, perpetrators and their
#' "please specify" texts) are not compared but move with their entry.
#' Select-multiple sub-columns (\code{Q58/1}, \code{Q58/2}, ...) are found
#' automatically and move with their parent column.
#'
#' The defaults are:
#' \describe{
#'   \item{\code{countries_transited}}{Q47 to Q54, compared on country, next
#'     to each other only.}
#'   \item{\code{main_stops}}{Q56 to Q70 in five blocks of country, place and
#'     why_stop, compared on country + place, next to each other only.}
#'   \item{\code{dangerous_locations}}{Q98 to Q117 in five blocks of country,
#'     place, risks and perpetrators, compared on country + place across the
#'     whole loop. Q98/Q99 is the first dangerous location.}
#' }
#' A journey can pass through the same country or stop twice, so countries
#' and stops are only checked next to each other. A dangerous location should
#' only be listed once.
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
  country_lists <- c(
    "country_transited_1",
    "country_transited_2",
    "country_transited_3"
  )

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
      slots = countries,
      scope = "adjacent",
      country_lists = country_lists
    ),
    main_stops = list(
      label = "Main stops",
      item = "stop",
      slots = main_stops,
      scope = "adjacent",
      country_lists = country_lists,
      place_lists = "places_stop",
      place_filter = "cf"
    ),
    dangerous_locations = list(
      label = "Dangerous locations",
      item = "location",
      slots = dangerous,
      scope = "any",
      country_lists = country_lists,
      place_lists = "places_stop",
      place_filter = "cf"
    )
  )
}

#' Other spellings of country names
#'
#' Names an "Other" answer may be typed as that are not a label in the
#' XLSForm, mapped to the label (or choice name) they mean.
#' \code{\link{validate_repeated_entries}} uses them, with \code{tool_choices},
#' to see that a typed "Turkey" is the same country as a picked "Turkiye".
#' Labels in every language of the form are already used, as are small
#' typos, so only add names that are really different.
#'
#' @return A named character vector: names are the typed spellings, values
#'   the label they mean.
#' @examples
#' aliases <- c(ck_country_aliases(), "Persia" = "Iran")
#' @export
ck_country_aliases <- function() {
  # "Turkiye" with u-umlaut, built from code points to keep the source ASCII
  turkiye <- intToUtf8(c(84, 252, 114, 107, 105, 121, 101))
  c(
    "Turkey" = turkiye,
    "Turkiya" = turkiye,
    "Turkei" = turkiye,
    "Turquie" = turkiye,
    "Republic of Turkey" = turkiye,
    "Islamic Republic of Iran" = "Iran",
    "Iran (Islamic Republic of)" = "Iran",
    "Syrian Arab Republic" = "Syria",
    "Russian Federation" = "Russia",
    "UAE" = "United Arab Emirates",
    "Emirates" = "United Arab Emirates",
    "Dubai" = "United Arab Emirates",
    "KSA" = "Saudi Arabia",
    "Saudi" = "Saudi Arabia",
    "UK" = "United Kingdom",
    "Britain" = "United Kingdom",
    "Great Britain" = "United Kingdom",
    "England" = "United Kingdom",
    "USA" = "United States of America",
    "United States" = "United States of America",
    "America" = "United States of America"
  )
}

#' Validate Repeated Entries in Looped Questions
#'
#' Flags looped journey questions where an entry repeats an earlier one, and
#' writes the fix to the log: remove the repeat, move the later entries up one
#' place and close the list with None.
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
#'   \item \strong{Dangerous locations} (Q98 to Q117): any location with the
#'     same country and place as an earlier one, wherever it is in the loop.
#' }
#'
#' For countries and stops only entries that follow each other count.
#' \code{Kenya, Kenya, Uganda} becomes \code{Kenya, Uganda, None};
#' \code{Kenya, Uganda, Tanzania, Kenya} is left as it is. A run such as
#' \code{Kenya, Kenya, Kenya} collapses to one \code{Kenya}.
#'
#' The form only opens the next entry when the one before is not None or
#' Refused, so blanking a repeat in the middle would leave the record breaking
#' the form's own skip logic. Every column of the later entries is therefore
#' moved up - the "please specify" texts, calculates and select-multiple
#' sub-columns included. If the list ended in a closing answer (None, Refused)
#' that answer moves up too; if every slot was filled, the freed slot gets
#' \code{none_value} and its other columns become blank.
#'
#' Blank values and \code{stop_values} are never treated as repeats. Both the
#' codes (\code{996}) and the labels (\code{None}) of the closing answers are
#' recognised, so the check works on coded and labelled exports.
#'
#' \strong{Certain and possible repeats.} A repeat is \emph{certain} when the
#' same answer is given twice in a row. Its log rows start with
#' "Back-to-back repeat" and \code{apply_cleaning_log()} applies them
#' whatever the reviewer filled in. A repeat is only \emph{possible} when
#' \itemize{
#'   \item the two entries are not next to each other (dangerous locations),
#'     because the removed entry's own answers, such as its risks, go with it;
#'     or
#'   \item they only match through a typed "Other" answer: the text names the
#'     same country or place as the other entry (in any language of the form,
#'     through \code{aliases}, or with a small typo), or two typed texts are
#'     nearly the same (\code{similarity}).
#' }
#' Possible repeats start with "Possible repeat" and are only applied when the
#' reviewer accepts them: set \strong{Action taken} to \code{recoded} on any
#' one row of the record and copy its suggested value into \strong{New value};
#' \code{apply_cleaning_log()} then applies all of that record's rows. Rows
#' left as \code{no_action} keep the answers as they are.
#'
#' Typed answers are only matched to the form's choices when
#' \code{tool_choices} is given; without it, two typed texts are still
#' compared with each other.
#'
#' The function only writes a log - the data is not changed. Each log row is
#' one cell that has to change, and its issue says what was repeated and the
#' suggested new value. All rows from one record and question set share a
#' \code{check_binding}, so they get one colour on the cleaning log.
#'
#' @param dataset A dataframe or a list containing a dataframe named
#'   \code{checked_dataset}.
#' @param uuid_column Name of the uuid column. Default \code{"_uuid"}.
#' @param sections The question sets to check, in the shape returned by
#'   \code{\link{ck_repeated_entries_sections}} (the default). Pass a subset
#'   to run fewer sets, or your own list for a tool with other question
#'   names.
#' @param tool_choices Optional. The XLSForm choices, as returned by
#'   \code{read_tool_choices()}. Used to match typed "Other" answers to the
#'   form's countries and places. Default \code{NULL}.
#' @param none_value The value that means None, written into the freed slot
#'   when the list had no closing answer. \code{NULL} (the default) uses
#'   \code{"None"} for a labelled export and \code{"996"} for a coded one,
#'   judged from the country columns.
#' @param stop_values Values that end the list (None, Don't know, Refused),
#'   as codes or labels. They are never treated as repeats.
#'   \code{none_value} is always included. Default
#'   \code{c("996", "998", "999", "None", "Don't know", "Refused")}.
#' @param other_values Values of the country or place question that mean
#'   "Other", as codes or labels. Default
#'   \code{c("997", "9997", "Other", "Other country")}.
#' @param aliases Other spellings of country names, see
#'   \code{\link{ck_country_aliases}}. Only used with \code{tool_choices}.
#' @param similarity A number above 0 and up to 1. Two typed texts that are at
#'   least this similar (1 minus the edit distance over the longer length)
#'   count as a possible repeat. Default \code{0.85}. With \code{1}, only
#'   texts that differ in case, spacing or punctuation match.
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
#'   tool_choices = tool_choices,
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
  tool_choices = NULL,
  none_value = NULL,
  stop_values = c("996", "998", "999", "None", "Don't know", "Refused"),
  other_values = c("997", "9997", "Other", "Other country"),
  aliases = ck_country_aliases(),
  similarity = 0.85,
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
  if (
    !is.numeric(similarity) ||
      length(similarity) != 1 ||
      is.na(similarity) ||
      similarity <= 0 ||
      similarity > 1
  ) {
    stop("`similarity` must be a single number above 0 and up to 1.")
  }
  if (!is.null(tool_choices) && !is.data.frame(tool_choices)) {
    stop("`tool_choices` must be a dataframe, see read_tool_choices().")
  }
  sections <- .ck_check_sections(sections)

  df <- full_df
  if (skip_label_row && nrow(df) > 0) {
    df <- df[-1, , drop = FALSE]
  }

  if (is.null(none_value)) {
    none_value <- .ck_detect_none(df, sections)
  }
  none_value <- as.character(none_value)
  stop_norm <- .ck_norm_entry(unique(c(none_value, stop_values)))
  other_norm <- .ck_norm_entry(other_values)

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
    s <- sections[[sid]]
    lookups <- list(
      country = .ck_choice_lookup(
        tool_choices,
        s$country_lists,
        filter_col = NULL,
        aliases = aliases,
        drop = c(stop_norm, other_norm)
      ),
      place = .ck_choice_lookup(
        tool_choices,
        s$place_lists,
        filter_col = s$place_filter,
        aliases = NULL,
        drop = c(stop_norm, other_norm)
      )
    )
    res <- .ck_repeated_section(
      df = df,
      uuid_column = uuid_column,
      section_id = sid,
      section = s,
      none_value = none_value,
      stop_norm = stop_norm,
      other_norm = other_norm,
      lookups = lookups,
      similarity = similarity,
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

  n_possible <- length(unique(log$check_binding[grepl(
    "^\\[[^]]+\\] Possible repeat: ",
    log$issue
  )]))
  message(
    "validate_repeated_entries: checked ",
    length(sections),
    " question set(s); ",
    nrow(log),
    " log row(s) produced across ",
    length(unique(log$uuid)),
    " unique record(s)",
    if (n_possible > 0) {
      paste0(
        "; ",
        n_possible,
        " record(s) have a possible repeat for the reviewer to accept"
      )
    },
    "."
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
    if (is.null(s$scope)) {
      s$scope <- "adjacent"
    }
    if (length(s$scope) != 1 || !(s$scope %in% c("adjacent", "any"))) {
      stop(
        "The `scope` of question set '",
        sid,
        "' must be \"adjacent\" or \"any\"."
      )
    }
    sections[[sid]] <- s
  }
  sections
}

#' Normalise values before comparing entries
#'
#' Blank and NA become "", case, repeated spaces and curly apostrophes are
#' ignored, and a whole number read as "996.0" compares equal to "996".
#' @keywords internal
#' @noRd
.ck_norm_entry <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  # curly apostrophes (U+2018, U+2019) and backticks become a plain one
  x <- gsub(paste0("[", intToUtf8(c(0x2018, 0x2019)), "`]"), "'", x)
  x <- tolower(trimws(gsub("\\s+", " ", x)))
  sub("^([0-9]+)\\.0+$", "\\1", x)
}

#' Normalise free text before matching it to choices or other text
#'
#' Goes further than .ck_norm_entry(): accents are dropped (u-umlaut -> u),
#' Arabic letter forms are folded into their Persian ones (yeh,
#' alef maksura, kaf, teh marbuta and hamza/madda alefs), diacritics, tatweel
#' and zero-width joiners are removed, and punctuation becomes a space.
#' @keywords internal
#' @noRd
.ck_norm_text <- function(x) {
  x <- as.character(x)
  x[is.na(x)] <- ""
  x <- stringi::stri_trans_general(x, "Latin-ASCII")
  x <- tolower(x)
  # code points, so the source stays ASCII: Arabic yeh, alef maksura, kaf,
  # teh marbuta, alef with hamza above / below / madda -> Persian yeh, keheh,
  # heh, alef
  x <- chartr(
    intToUtf8(c(0x064a, 0x0649, 0x0643, 0x0629, 0x0623, 0x0625, 0x0622)),
    intToUtf8(c(0x06cc, 0x06cc, 0x06a9, 0x0647, 0x0627, 0x0627, 0x0627)),
    x
  )
  # harakat (U+064B to U+0652) and tatweel (U+0640) are dropped
  x <- gsub(
    paste0("[", intToUtf8(c(0x064b, 0x2d, 0x0652, 0x0640)), "]"),
    "",
    x
  )
  # zero-width non-joiner / joiner become a space
  x <- gsub(paste0("[", intToUtf8(c(0x200c, 0x200d)), "]"), " ", x)
  x <- gsub("[\\p{P}\\p{S}]", " ", x, perl = TRUE)
  trimws(gsub("\\s+", " ", x))
}

#' Similarity of two texts: 1 minus edit distance over the longer length
#' @keywords internal
#' @noRd
.ck_similar <- function(a, b) {
  a <- .ck_norm_text(a)
  b <- .ck_norm_text(b)
  if (!nzchar(a) || !nzchar(b)) {
    return(0)
  }
  1 - drop(utils::adist(a, b)) / max(nchar(a), nchar(b))
}

#' Pick None's form from the data: "None" for labels, "996" for codes
#' @keywords internal
#' @noRd
.ck_detect_none <- function(df, sections) {
  cols <- unique(unlist(lapply(sections, function(s) {
    vapply(s$slots, function(x) x[["country"]], character(1))
  })))
  cols <- intersect(cols, names(df))
  v <- .ck_norm_entry(unlist(
    lapply(cols, function(col) as.character(df[[col]])),
    use.names = FALSE
  ))
  v <- v[nzchar(v)]
  if ("none" %in% v) {
    return("None")
  }
  if ("996" %in% v) {
    return("996")
  }
  if (length(v) > 0 && mean(grepl("^[0-9]+$", v)) < 0.5) "None" else "996"
}

#' Lookup of every way a choice can be written
#'
#' One row per spelling: the choice name, each label column (every language)
#' with and without a trailing "(city)"-style note, and the aliases. Choices
#' in `drop` (None, Other, ...) are left out.
#' @return A data frame with `variant` (normalised text), `name` and `filter`
#'   (the choice-filter value, NA when there is none), or NULL.
#' @keywords internal
#' @noRd
.ck_choice_lookup <- function(
  tool_choices,
  list_names,
  filter_col = NULL,
  aliases = NULL,
  drop = character(0)
) {
  if (is.null(tool_choices) || length(list_names) == 0) {
    return(NULL)
  }
  tc <- as.data.frame(tool_choices, stringsAsFactors = FALSE)
  names(tc) <- tolower(names(tc))
  if (!all(c("list_name", "name") %in% names(tc))) {
    stop("`tool_choices` needs the columns list_name and name.")
  }
  tc <- tc[
    !is.na(tc$list_name) & tc$list_name %in% list_names & !is.na(tc$name),
    ,
    drop = FALSE
  ]
  tc <- tc[!(.ck_norm_entry(tc$name) %in% drop), , drop = FALSE]
  if (nrow(tc) == 0) {
    return(NULL)
  }

  lab_cols <- grep("^label", names(tc), value = TRUE)
  flt <- if (!is.null(filter_col) && tolower(filter_col) %in% names(tc)) {
    .ck_norm_entry(tc[[tolower(filter_col)]])
  } else {
    rep(NA_character_, nrow(tc))
  }
  flt[!is.na(flt) & !nzchar(flt)] <- NA_character_
  nm <- as.character(tc$name)

  texts <- c(list(nm), lapply(lab_cols, function(l) as.character(tc[[l]])))
  lk <- do.call(
    rbind,
    lapply(texts, function(v) {
      data.frame(
        variant = c(v, sub("\\s*\\([^)]*\\)\\s*$", "", v)),
        name = c(nm, nm),
        filter = c(flt, flt),
        stringsAsFactors = FALSE
      )
    })
  )
  lk$variant <- .ck_norm_text(lk$variant)
  lk <- lk[nzchar(lk$variant), , drop = FALSE]

  if (length(aliases) > 0) {
    a_from <- .ck_norm_text(names(aliases))
    a_to <- .ck_norm_text(aliases)
    extra <- lapply(seq_along(aliases), function(x) {
      hit <- unique(lk[lk$variant == a_to[x], c("name", "filter")])
      if (nrow(hit) == 0 || !nzchar(a_from[x])) {
        return(NULL)
      }
      data.frame(
        variant = a_from[x],
        name = hit$name,
        filter = hit$filter,
        stringsAsFactors = FALSE
      )
    })
    lk <- do.call(rbind, c(list(lk), extra))
  }
  lk <- unique(lk)
  rownames(lk) <- NULL
  lk
}

#' Match one text to a choice name
#'
#' Exact match on any spelling first. With `fuzzy`, a text of four or more
#' characters may also be one edit away (two for texts over six characters)
#' from a spelling, as long as only one choice is that close.
#' @return The choice name, or NA when there is no single match.
#' @keywords internal
#' @noRd
.ck_resolve_choice <- function(text, lookup, filter = NA, fuzzy = TRUE) {
  t <- .ck_norm_text(text)
  if (is.null(lookup) || !nzchar(t)) {
    return(NA_character_)
  }
  if (!is.na(filter)) {
    keep <- is.na(lookup$filter) | lookup$filter == filter
    if (any(keep)) {
      lookup <- lookup[keep, , drop = FALSE]
    }
  }
  hit <- unique(lookup$name[lookup$variant == t])
  if (length(hit) == 1) {
    return(hit)
  }
  if (length(hit) > 1 || !fuzzy || nchar(t) < 4) {
    return(NA_character_)
  }
  max_d <- if (nchar(t) <= 6) 1L else 2L
  cand <- lookup[abs(nchar(lookup$variant) - nchar(t)) <= max_d, , drop = FALSE]
  if (nrow(cand) == 0) {
    return(NA_character_)
  }
  d <- drop(utils::adist(t, cand$variant))
  if (min(d) > max_d) {
    return(NA_character_)
  }
  hit <- unique(cand$name[d == min(d)])
  if (length(hit) == 1) hit else NA_character_
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
  other_norm,
  lookups,
  similarity,
  sm_separator
) {
  slots <- section$slots
  n_slots <- length(slots)
  n_rows <- nrow(df)
  roles <- names(slots[[1]])
  key_roles <- intersect(
    c("country", "country_other", "place", "place_other"),
    roles
  )
  has_place <- any(c("place", "place_other") %in% roles)

  # ---- raw and normalised answers, one matrix per role ----
  raw_m <- function(role) {
    m <- matrix(NA_character_, n_rows, n_slots)
    if (role %in% roles) {
      for (j in seq_len(n_slots)) {
        m[, j] <- .ck_get_col(df, slots[[j]][[role]])
      }
    }
    m
  }
  norm_m <- function(m) matrix(.ck_norm_entry(m), n_rows, n_slots)
  c_raw <- raw_m("country")
  co_raw <- raw_m("country_other")
  p_raw <- raw_m("place")
  po_raw <- raw_m("place_other")
  country <- norm_m(c_raw)
  c_key <- matrix(paste(country, norm_m(co_raw), sep = "\u001f"), n_rows)
  p_norm <- norm_m(p_raw)
  p_key <- matrix(paste(p_norm, norm_m(po_raw), sep = "\u001f"), n_rows)

  is_real <- country != "" & !(country %in% stop_norm)
  dim(is_real) <- dim(country)

  # number of real entries before the first blank / closing answer
  chain_len <- integer(n_rows)
  alive <- rep(TRUE, n_rows)
  for (j in seq_len(n_slots)) {
    alive <- alive & is_real[, j]
    chain_len <- chain_len + alive
  }

  # ---- what one entry is: its keys, typed text and matched choice ----
  cache <- new.env(parent = emptyenv())
  resolve <- function(text, which, filter = NA_character_, fuzzy = TRUE) {
    if (is.null(lookups[[which]]) || is.na(text) || !nzchar(trimws(text))) {
      return(NA_character_)
    }
    k <- paste(which, filter, fuzzy, text, sep = "\u001f")
    if (!exists(k, envir = cache, inherits = FALSE)) {
      assign(
        k,
        .ck_resolve_choice(text, lookups[[which]], filter, fuzzy),
        envir = cache
      )
    }
    get(k, envir = cache, inherits = FALSE)
  }
  filled <- function(x) !is.na(x) && nzchar(trimws(x))

  entry <- function(i, j) {
    c_other <- country[i, j] %in% other_norm
    co <- co_raw[i, j]
    c_text <- if (c_other && filled(co)) co else NA_character_
    c_canon <- if (c_other) {
      resolve(co, "country")
    } else {
      resolve(c_raw[i, j], "country", fuzzy = FALSE)
    }
    e <- list(
      c_key = c_key[i, j],
      c_text = c_text,
      c_canon = c_canon,
      c_show = if (filled(c_text)) c_text else c_raw[i, j]
    )
    if (has_place) {
      po <- po_raw[i, j]
      p_other <- p_norm[i, j] == "" || p_norm[i, j] %in% other_norm
      e$p_text <- if (p_other && filled(po)) po else NA_character_
      e$p_canon <- if (filled(e$p_text)) {
        resolve(po, "place", c_canon)
      } else if (p_norm[i, j] != "") {
        resolve(p_raw[i, j], "place", c_canon, fuzzy = FALSE)
      } else {
        NA_character_
      }
      e$p_key <- p_key[i, j]
      e$p_show <- if (filled(e$p_text)) e$p_text else p_raw[i, j]
    }
    e
  }

  # 2 = same answer, 1 = same through a typed answer, 0 = different
  comp <- function(key_a, key_b, canon_a, canon_b, text_a, text_b, sa, sb) {
    if (identical(key_a, key_b)) {
      return(2L)
    }
    if (!is.na(canon_a) && !is.na(canon_b) && canon_a == canon_b) {
      return(1L)
    }
    if (
      (filled(text_a) || filled(text_b)) && .ck_similar(sa, sb) >= similarity
    ) {
      return(1L)
    }
    0L
  }
  match_entries <- function(a, b) {
    lv <- comp(
      a$c_key,
      b$c_key,
      a$c_canon,
      b$c_canon,
      a$c_text,
      b$c_text,
      a$c_show,
      b$c_show
    )
    if (lv > 0L && has_place) {
      lv <- min(
        lv,
        comp(
          a$p_key,
          b$p_key,
          a$p_canon,
          b$p_canon,
          a$p_text,
          b$p_text,
          a$p_show,
          b$p_show
        )
      )
    }
    lv
  }

  # ---- find the repeats ----
  dup <- matrix(FALSE, n_rows, n_slots)
  details <- vector("list", n_rows)
  for (i in which(chain_len >= 2)) {
    ents <- lapply(seq_len(chain_len[i]), function(j) entry(i, j))
    d <- list()
    for (j in 2:chain_len[i]) {
      cands <- if (section$scope == "any") rev(seq_len(j - 1)) else j - 1
      best <- 0L
      best_k <- NA_integer_
      for (k in cands) {
        lv <- match_entries(ents[[j]], ents[[k]])
        if (lv > best) {
          best <- lv
          best_k <- k
        }
        if (best == 2L) break
      }
      if (best > 0L) {
        dup[i, j] <- TRUE
        d[[length(d) + 1]] <- list(
          j = j,
          k = best_k,
          sure = best == 2L && best_k == j - 1,
          typed = best == 1L
        )
      }
    }
    details[[i]] <- d
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
  item <- section$item
  none_label <- if (.ck_norm_entry(none_value) == "none") {
    "None"
  } else {
    paste0("None (", none_value, ")")
  }
  rows <- list()

  for (i in which(flag)) {
    len <- chain_len[i]
    kept <- c(1L, which(!dup[i, seq_len(len)][-1]) + 1L)
    has_closing <- len < n_slots && country[i, len + 1] %in% stop_norm
    sources <- if (has_closing) c(kept, len + 1L) else kept
    region_end <- if (has_closing) len + 1L else len
    first_dup <- which(dup[i, ])[1]
    sure <- all(vapply(details[[i]], `[[`, logical(1), "sure"))

    # one line naming every repeat in this record
    what <- vapply(
      details[[i]],
      function(x) {
        if (sure) {
          return(paste0(
            item,
            " ",
            x$j,
            " (",
            ref(x$j),
            ") is the same as ",
            item,
            " ",
            x$k,
            " (",
            ref(x$k),
            ") ",
            show(i, x$j)
          ))
        }
        why <- if (x$typed) {
          " (through the typed answer)"
        } else if (x$k != x$j - 1) {
          " (not next to each other)"
        } else {
          ""
        }
        paste0(
          item,
          " ",
          x$j,
          " (",
          ref(x$j),
          ") ",
          show(i, x$j),
          if (x$typed) " looks like " else " repeats ",
          item,
          " ",
          x$k,
          " (",
          ref(x$k),
          ") ",
          show(i, x$k),
          why
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
      paste0("close the list with ", none_label)
    }
    base_issue <- if (sure) {
      paste0(
        "[",
        section$label,
        "] Back-to-back repeat: ",
        paste(what, collapse = "; "),
        ". Remove the repeat, move the later entries up one place and ",
        closing,
        "."
      )
    } else {
      paste0(
        "[",
        section$label,
        "] Possible repeat: ",
        paste(what, collapse = "; "),
        ". If it is a repeat, remove it, move the later entries up one place ",
        "and ",
        closing,
        "; the removed ",
        item,
        "'s other answers go with it, so add any that differ to the one that ",
        "stays. To accept, set Action taken to recoded on one row of this ",
        "record and copy its suggested value into New value - the other rows ",
        "follow. Leave as no_action to keep the answers."
      )
    }
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
#' action and new value to the suggestion in the issue.
#'
#' "Back-to-back repeat" rows are always filled in, whatever the reviewer put.
#' "Possible repeat" rows are filled in only for a record the reviewer
#' accepted: one of its rows (same check binding, or same uuid and question
#' set) has an action in \code{accept_actions}. Rows whose action is in
#' \code{keep_actions} (discard) are left alone.
#'
#' @return A list with \code{cleaning_log}, \code{n} (rows filled in),
#'   \code{n_changed} (of those, rows where the reviewer had put something
#'   else), \code{n_accepted} and \code{n_possible} (possible-repeat records
#'   accepted, and in total).
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
  keep_actions,
  uuid_col = NULL,
  accept_actions = change_action
) {
  none <- list(
    cleaning_log = cleaning_log,
    n = 0L,
    n_changed = 0L,
    n_accepted = 0L,
    n_possible = 0L
  )
  if (!(issue_col %in% names(cleaning_log)) || nrow(cleaning_log) == 0) {
    return(none)
  }

  issue <- as.character(cleaning_log[[issue_col]])
  issue[is.na(issue)] <- ""
  pattern <- paste0(
    "^\\[([^]]+)\\] (Back-to-back|Possible) repeat: .* ",
    "Suggested new value: ('.*'|blank)\\.$"
  )
  is_any <- grepl(pattern, issue)
  is_possible <- is_any & sub(pattern, "\\2", issue) == "Possible"

  binding <- rep("", nrow(cleaning_log))
  if (binding_col %in% names(cleaning_log)) {
    binding <- trimws(as.character(cleaning_log[[binding_col]]))
    binding[is.na(binding) | binding == "NA"] <- ""
    is_any <- is_any & (binding == "" | startsWith(binding, "repeated_"))
    is_possible <- is_possible & is_any
  }

  action <- trimws(tolower(as.character(cleaning_log[[action_col]])))
  action[is.na(action)] <- ""

  # ---- possible repeats: only the records the reviewer accepted ----
  uuid <- if (!is.null(uuid_col) && uuid_col %in% names(cleaning_log)) {
    as.character(cleaning_log[[uuid_col]])
  } else {
    rep("", nrow(cleaning_log))
  }
  group <- ifelse(
    binding != "",
    binding,
    paste(uuid, sub(pattern, "\\1", issue), sep = " ~/~ ")
  )
  accepted <- unique(group[
    is_possible & action %in% tolower(accept_actions)
  ])
  is_rep <- is_any & (!is_possible | group %in% accepted)
  is_rep <- is_rep & !(action %in% tolower(keep_actions))

  out <- none
  out$n_possible <- length(unique(group[is_possible]))
  out$n_accepted <- length(accepted)
  if (!any(is_rep)) {
    return(out)
  }

  suggested <- sub(pattern, "\\3", issue[is_rep])
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

  out$cleaning_log <- cleaning_log
  out$n <- sum(is_rep)
  out$n_changed <- n_changed
  out
}

#!/usr/bin/env Rscript
# ai-written
#'
#' The INSP bed tables, read into the same capacity series as the WHO AFRO
#' reports.
#'
#' `R/30_capacity.R` reads bed capacity and occupancy from the WHO AFRO
#' weekly reports, from 28 June onward. The INSP situation reports carried
#' the same figures earlier and at a finer level: `patients au lit (j-1)`
#' runs 2 June to 2 August, `taux d'occupation global` to 11 July, and for
#' the earliest reports the tables give a bed count per named facility. This
#' script reads those tables and writes them into `data/capacity_indicators.csv`
#' with `source = insp`, so the two sources sit in the same table under the
#' same fixed vocabulary from `R/30_capacity.R`.
#'
#' No model call. `data/indicators.csv` already surveyed every label these
#' tables use, and the labels are a closed set: `registry/insp_capacity_labels.csv`
#' maps each one, by hand, onto the fixed vocabulary or onto nothing, with a
#' note either way. A label the registry does not carry is not guessed at;
#' the row is skipped and logged.
#'
#' The tables take three shapes over the corpus:
#'
#'   * SitReps up to about 017: one row a label, one column a named
#'     facility or a subtotal, sometimes with the bed count folded into the
#'     column header (`HGR BUNIA (12 Lits: 08 S et 03 C)`) or into an
#'     unlabelled first data row (`28 lits`). SitRep 007 alone splits the
#'     label across two columns (`Indicateurs 1`, `Indicateurs 2`) rather
#'     than one.
#'   * SitReps from about 018: one column a province (`Ituri`, `Nord-Kivu`,
#'     ...) plus `Ensemble` for the national total.
#'   * A handful of tables (080) carry a trailing column the extraction
#'     misaligned; it is dropped rather than guessed at, and every row it
#'     touches is logged.
#'
#' `ND`, a blank cell and `-` are not reported and get no row: absence is
#' data, never zero. A value that needed stripping non-numeric text
#' (`28 lits`, `93,9 %`) is written with `confidence = "low"`.
#'
#' `evidence_quote` is the header line and the data line the value came
#' from, joined by a newline, both copied verbatim from the CSV so that
#' `R/03_checks.R` can find the data line as a literal line of the file
#' named in `url`.
#'
#' This script writes `ambiguous_key` but not `preferred`, exactly as
#' `R/30_capacity.R` does: run `R/31_capacity_preferred.R` afterwards so the
#' new rows (and any AFRO row they now share a key with) get a `preferred`
#' value. This script's own end-of-run summary calls the same rule to report
#' on the run, without writing the result, for the same reason.
#'
#' Usage:
#'     Rscript R/32_capacity_insp.R
#'     Rscript R/31_capacity_preferred.R

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))
source(here::here("R", "lib", "capacity_preferred.R"))

INSP_CSV_DIR <- file.path(sitreps_root(), "data", "csv")
PUBLISHER <- "Institut National de Santé Publique"
LICENCE <- "CC BY 4.0"
COUNTRY <- "Democratic Republic of the Congo"

# --------------------------------------------------------------- vocabulary

INDICATORS <- c("beds_capacity", "beds_occupied", "bed_occupancy_pct",
    "patients_in_isolation", "admissions", "discharges_recovered",
    "deaths_in_facility", "escapes", "facilities_operational",
    "laboratories_testing")

#' Six canonical provinces, matching `data/reference/grid3_places.csv` and
#' `R/30_capacity.R`'s own lookup. Keyed on a folded spelling so that
#' `Ituri1`, `Nord-Kivu*` and `Haut-Uélé` all land on the same six values.
fold_ascii <- function(x) {
    x <- tolower(trimws(x))
    x <- chartr("éèêëàâäîïôöùûüç",
        "eeeeaaaiioouuuc", x)
    x
}
#' A trailing footnote marker (`*`, a digit) on a province or facility
#' column header, e.g. `Ituri1`, `Nord-Kivu*`.
strip_footnote <- function(x) sub("[*†¹²³[:digit:]]+$", "", x)

PROVINCE_LOOKUP <- c(
    "ituri" = "Ituri",
    "nord-kivu" = "Nord-Kivu", "nord kivu" = "Nord-Kivu",
    "sud-kivu" = "Sud-Kivu", "sud kivu" = "Sud-Kivu",
    "haut-uele" = "Haut-Uele", "haut uele" = "Haut-Uele",
    "bas-uele" = "Bas-Uele", "bas uele" = "Bas-Uele",
    "tshopo" = "Tshopo")

NATIONAL_KEYS <- c("ensemble", "total general", "total")

canonical_province <- function(colname) {
    key <- fold_ascii(strip_footnote(colname))
    unname(PROVINCE_LOOKUP[key])
}

# ------------------------------------------------------------------ labels

labels <- fread(insp_capacity_labels_path(), colClasses = "character",
    na.strings = NULL)
setkey(labels, label_key)

#' The registry's own two documentation rows for the header- and
#' first-row-embedded bed counts are handled in code, never looked up by
#' label text, so they are dropped from the lookup table itself.
labels <- labels[!label_key %in%
    c("(header bed count)", "(blank first row, facility bed counts)")]

label_lookup <- function(label) {
    hit <- labels[label_key == label]
    if (!nrow(hit)) return(NULL)
    hit[1]
}

# -------------------------------------------------------------- report dates

#' `sitrep` -> `report_date`, exactly as `R/02_resolve.R` wrote it. INSP
#' table filenames carry the same sitrep id (`006_v2`, `080`), so this is the
#' one lookup both the facility pipeline and this script use.
sitrep_dates <- unique(fread(events_path(),
    colClasses = "character")[, .(sitrep, report_date)])
report_date_of <- setNames(as.Date(sitrep_dates$report_date), sitrep_dates$sitrep)

# --------------------------------------------------------------------- I/O

insp_table_files <- function() {
    files <- list.files(INSP_CSV_DIR,
        pattern = "(?i)mouvement|occupation", full.names = FALSE)
    sort(files)
}

doc_id_of <- function(filename) sub("^([0-9]+(_v[0-9]+)?)_.*", "\\1", filename)

# ------------------------------------------------------------- value parsing

NOT_REPORTED <- c("", "ND", "N.D", "N.D.", "n.d", "n.d.", "-", "–", "NA")

#' A cell's raw text to a number, or `NA` where it is not reported.
#' `low` is TRUE where non-numeric text had to be stripped to read it, which
#' is the confidence hedge the brief asks for: `28 lits`, `93,9 %`.
parse_value <- function(raw, is_percent) {
    x <- trimws(raw)
    if (toupper(trimws(x)) %in% toupper(NOT_REPORTED)) {
        return(list(value = NA_real_, low = FALSE))
    }
    low <- FALSE
    if (is_percent) {
        #' A percent cell sometimes carries the numerator/denominator behind
        #' it, e.g. `75,2% (237/315)`: the fraction is evidence for the
        #' percent, not a second value, so it is dropped rather than parsed.
        x <- sub("\\s*\\([^)]*\\)\\s*$", "", x)
        x <- gsub("[% [:space:]]", "", x)
        if (grepl(",", x, fixed = TRUE)) {
            x <- gsub(",", ".", x, fixed = TRUE)
            low <- TRUE
        }
    } else if (grepl("[Ll]its?", x)) {
        x <- gsub("[^0-9]", "", x)
        low <- TRUE
    } else {
        x <- gsub("[ [:space:]]", "", x)
    }
    val <- suppressWarnings(as.numeric(x))
    list(value = val, low = low)
}

#' The bed count folded into a facility column header, e.g.
#' `HGR BUNIA (12 Lits: 08 S et 03 C)`, `CT HEAL AFRICA (Nord-kivu) 19 lits`.
extract_header_beds <- function(colname) {
    m <- regmatches(colname, regexpr("([0-9]+)\\s*[Ll]its?", colname))
    if (!length(m) || !nzchar(m)) return(NA_real_)
    as.numeric(gsub("[^0-9]", "", m))
}

#' The facility name a column header prints, with a bed count or footnote
#' stripped out.
clean_facility_name <- function(colname) {
    x <- sub("\\s*\\([^)]*\\)\\s*$", "", colname)
    x <- sub("\\s*[0-9]+\\s*[Ll]its?\\s*$", "", x)
    trimws(x)
}

title_case_word <- function(x) {
    paste0(toupper(substr(x, 1, 1)), tolower(substr(x, 2, nchar(x))))
}

# --------------------------------------------------------- column classifier

#' What one table column means: `national`, `province`, `health_zone`,
#' `facility`, or `skip` with a reason. Order matters: national and province
#' names are checked before anything is assumed to be a facility, because a
#' facility name can otherwise collide with a province's own name inside a
#' parenthetical (`CT HEAL AFRICA (Nord-kivu) 19 lits` is a facility, not a
#' province column).
classify_column <- function(colname, all_names) {
    folded <- fold_ascii(strip_footnote(colname))
    if (folded %in% NATIONAL_KEYS) {
        return(list(level = "national", place = "", place_raw = colname))
    }
    prov <- canonical_province(colname)
    if (!is.na(prov)) {
        return(list(level = "province", place = prov, place_raw = colname))
    }
    if (grepl("^ZS\\s+", colname, ignore.case = TRUE)) {
        zone <- title_case_word(trimws(sub("^ZS\\s+", "", colname,
            ignore.case = TRUE)))
        return(list(level = "health_zone", place = zone, place_raw = colname))
    }
    #' A column the extraction gave a numeric suffix because its name repeats
    #' another column's: the source table distinguished two facilities this
    #' way and the extraction lost which was which. Neither this column nor
    #' its unsuffixed twin can be trusted.
    if (grepl("_[0-9]+$", colname) ||
        paste0(colname, "_1") %in% all_names) {
        return(list(level = "skip",
            reason = "duplicate column name from extraction; source facility identity lost"))
    }
    if (identical(colname, "col")) {
        return(list(level = "skip",
            reason = "trailing column the extraction misaligned; contents do not line up with a place"))
    }
    if (grepl("total", folded, fixed = TRUE)) {
        return(list(level = "skip",
            reason = "subtotal across a cluster of facilities or a mixed total/occupancy column, not a formal place level"))
    }
    list(level = "facility", place = clean_facility_name(colname),
        place_raw = colname)
}

# ---------------------------------------------------------------- one table

#' Read one INSP table and return its rows in the target schema, plus a list
#' of what it skipped.
read_insp_table <- function(filename) {
    path <- file.path(INSP_CSV_DIR, filename)
    lines <- readLines(path, warn = FALSE)
    dt <- tryCatch(fread(path, header = TRUE, colClasses = "character",
        na.strings = NULL), error = function(e) NULL)
    id <- doc_id_of(filename)
    report_date <- report_date_of[[id]]
    skipped <- list()
    skip <- function(row_label, place_raw, reason, value_raw = "") {
        skipped[[length(skipped) + 1]] <<- data.table(
            url = file.path("data", "csv", filename), doc_id = id,
            row_label = row_label, place_raw = place_raw, value_raw = value_raw,
            reason = reason)
    }

    if (is.null(dt) || is.na(report_date) || nrow(dt) != length(lines) - 1L) {
        skip("", "", paste0("could not read the table as one row a data line",
            " (embedded newline or unreadable date); table skipped whole"))
        return(list(rows = data.table(), skipped = rbindlist(skipped)))
    }

    header_line <- lines[1]
    all_cols <- names(dt)

    #' SitRep 007 alone splits the row label across the first two columns
    #' (`Indicateurs 1`, `Indicateurs 2`) instead of one. Combine them into
    #' one label and treat the rest of the row exactly as any other table's.
    two_col_label <- length(all_cols) >= 2 &&
        all(c("Indicateurs 1", "Indicateurs 2") == all_cols[1:2])
    if (two_col_label) {
        lab1 <- trimws(dt[[1]]); lab2 <- trimws(dt[[2]])
        row_label <- ifelse(lab1 == lab2, lab1, trimws(paste(lab1, lab2)))
        data_cols <- all_cols[-(1:2)]
    } else {
        row_label <- trimws(dt[[1]])
        data_cols <- all_cols[-1]
    }

    classified <- lapply(data_cols, classify_column, all_names = data_cols)
    names(classified) <- data_cols
    for (col in data_cols) {
        cl <- classified[[col]]
        if (identical(cl$level, "skip")) {
            vals <- dt[[col]]
            nonblank <- which(nzchar(trimws(vals)) &
                !toupper(trimws(vals)) %in% toupper(NOT_REPORTED))
            for (i in nonblank) {
                skip(row_label[i], col, cl$reason, vals[i])
            }
        }
    }

    #' The first data row of a facility table is sometimes an unlabelled bed
    #' count (SitReps 006, 006_v2): `""` in the label column, `28 lits` /
    #' `126 Lits` in the facility columns.
    blank_first_row <- nrow(dt) >= 1L && !nzchar(row_label[1])

    out <- list()
    emit <- function(place_level, place, place_raw, indicator, unit, period,
        value, confidence, as_of_date, evidence_quote) {
        out[[length(out) + 1L]] <<- data.table(
            source = "insp", doc_id = id, report_date = as.character(report_date),
            as_of_date = as.character(as_of_date), indicator = indicator,
            level = place_level, country = COUNTRY, place = place,
            place_raw = place_raw, value = value, unit = unit, period = period,
            confidence = confidence, evidence_quote = evidence_quote,
            publisher = PUBLISHER, licence = LICENCE,
            url = file.path("data", "csv", filename))
    }

    if (blank_first_row) {
        for (col in data_cols) {
            cl <- classified[[col]]
            if (!identical(cl$level, "facility")) next
            raw <- dt[[col]][1]
            if (toupper(trimws(raw)) %in% toupper(NOT_REPORTED)) next
            beds <- extract_header_beds(paste(raw))
            pv <- parse_value(raw, is_percent = FALSE)
            if (is.na(pv$value)) {
                skip(row_label[1], col, "bed count in the blank first row is not a number", raw)
                next
            }
            emit(cl$level, cl$place, cl$place_raw, "beds_capacity", "beds",
                "point", pv$value, "low", report_date,
                paste(header_line, lines[2], sep = "\n"))
        }
    }
    data_start <- if (blank_first_row) 2L else 1L

    #' `Total admissions`, bare, means two different things depending on
    #' what else is in the table. In SitRep 018 it is the only admissions
    #' total there is, and it is the 24h figure the surrounding rows are all
    #' in. From SitRep 064 the table also carries an explicit
    #' `Total admissions (24 h)` row, and the bare row is roughly seven
    #' times its size: a running cumulative total, not a second 24h figure.
    #' `registry/insp_capacity_labels.csv` maps the bare label as period
    #' `24h`, its meaning where it appears alone; this overrides that to
    #' `cumulative` wherever an explicit 24h admissions row sits alongside it.
    bare_admissions_is_cumulative <- any(row_label %in%
        c("Total admissions (24h)", "Total admissions (24 h)"))

    for (col in data_cols) {
        cl <- classified[[col]]
        if (identical(cl$level, "skip")) next
        #' A facility column header sometimes states the bed count itself:
        #' `HGR BUNIA (12 Lits: 08 S et 03 C)`. One `beds_capacity` row a
        #' table a column, dated to the report itself.
        if (identical(cl$level, "facility")) {
            hb <- extract_header_beds(col)
            if (!is.na(hb)) {
                emit(cl$level, cl$place, cl$place_raw, "beds_capacity", "beds",
                    "point", hb, "low", report_date, header_line)
            }
        }
        for (i in data_start:nrow(dt)) {
            label <- row_label[i]
            if (!nzchar(label)) next
            m <- label_lookup(label)
            if (is.null(m)) {
                skip(label, col, "unmapped label; not in registry/insp_capacity_labels.csv",
                    dt[[col]][i])
                next
            }
            if (!nzchar(m$indicator)) next
            raw <- dt[[col]][i]
            is_pct <- identical(m$unit, "percent")
            pv <- parse_value(raw, is_pct)
            if (is.na(pv$value)) {
                if (!toupper(trimws(raw)) %in% toupper(NOT_REPORTED)) {
                    skip(label, col, "value is not a number", raw)
                }
                next
            }
            as_of <- if (identical(m$indicator, "beds_occupied")) {
                report_date - 1L
            } else {
                report_date
            }
            period <- if (identical(label, "Total admissions") &&
                bare_admissions_is_cumulative) "cumulative" else m$period
            emit(cl$level, cl$place, cl$place_raw, m$indicator, m$unit,
                period, pv$value, if (pv$low) "low" else "high", as_of,
                paste(header_line, lines[i + 1L], sep = "\n"))
        }
    }

    list(rows = if (length(out)) rbindlist(out) else data.table(),
        skipped = if (length(skipped)) rbindlist(skipped) else data.table())
}

# ------------------------------------------------------------------- run it

files <- insp_table_files()
message("Reading ", length(files), " INSP mouvement/occupation tables.")

results <- lapply(files, read_insp_table)
rows <- rbindlist(lapply(results, `[[`, "rows"), fill = TRUE)
skipped <- rbindlist(lapply(results, `[[`, "skipped"), fill = TRUE)

fwrite(skipped, insp_capacity_skipped_path())
message("Skipped ", nrow(skipped), " table rows, logged to ",
    insp_capacity_skipped_path())
if (nrow(skipped)) print(skipped[, .N, by = reason][order(-N)])

if (!nrow(rows)) stop("No INSP capacity rows extracted.", call. = FALSE)

setorder(rows, as_of_date, indicator, level, place, doc_id)

# ---------------------------------------------- merge into capacity_indicators

existing <- read_capacity_csv(capacity_path())
existing[, value := as.numeric(value)]
existing <- existing[source != "insp"]
if ("preferred" %in% names(existing)) existing[, preferred := NULL]
if ("ambiguous_key" %in% names(existing)) existing[, ambiguous_key := NULL]

rows[, value := as.numeric(value)]

target_cols <- c("source", "doc_id", "report_date", "as_of_date", "indicator",
    "level", "country", "place", "place_raw", "value", "unit", "period",
    "confidence", "evidence_quote", "publisher", "licence", "url")
combined <- rbindlist(list(existing[, ..target_cols], rows[, ..target_cols]),
    use.names = TRUE)

mark_capacity_ambiguous(combined)
setcolorder(combined, c("source", "doc_id", "report_date", "as_of_date",
    "indicator", "level", "country", "place", "place_raw", "value", "unit",
    "period", "ambiguous_key", "confidence", "evidence_quote", "publisher",
    "licence", "url"))
setorder(combined, as_of_date, indicator, level, place)
fwrite(combined, capacity_path())

message("\nWritten: ", capacity_path(), " (", nrow(rows), " insp rows added, ",
    nrow(combined), " total). Run R/31_capacity_preferred.R next.")

print(rows[, .(figures = .N, first = min(as_of_date), last = max(as_of_date)),
    keyby = .(indicator, level)])

# ----------------------------------------------------- insp vs afro check

#' Where INSP and WHO AFRO both give a national figure for the same
#' indicator, in the same unit and over the same kind of period (both `24h`,
#' or both `point`, or both `cumulative`), within three days of each other.
#' AFRO reports weekly so an exact date match is not expected. A `24h` INSP
#' figure against a `7d` or `cumulative` AFRO figure is not a disagreement
#' worth reporting, so the two are never compared unless their periods match.
#' WHO AFRO's national rows cover both the Democratic Republic of the Congo
#' and Uganda (the outbreak reached a handful of patients there); INSP's
#' national figures are DRC only, so the comparison is restricted to the
#' same country or a Ugandan figure of 1 patient gets compared against a
#' DRC figure in the hundreds.
afro_national <- combined[source == "who_afro" & level == "national" &
    country == COUNTRY &
    indicator %in% c("beds_capacity", "beds_occupied", "bed_occupancy_pct",
        "patients_in_isolation", "admissions", "discharges_recovered",
        "deaths_in_facility", "escapes")]
insp_national <- combined[source == "insp" & level == "national"]

pairs <- list()
if (nrow(afro_national) && nrow(insp_national)) {
    for (ind in intersect(unique(afro_national$indicator), unique(insp_national$indicator))) {
        for (per in intersect(afro_national[indicator == ind, unique(period)],
            insp_national[indicator == ind, unique(period)])) {
            a <- afro_national[indicator == ind & period == per]
            b <- insp_national[indicator == ind & period == per]
            for (i in seq_len(nrow(b))) {
                d <- abs(as.Date(a$as_of_date) - as.Date(b$as_of_date[i]))
                j <- which(d <= 3L)
                if (!length(j)) next
                j <- j[which.min(d[j])]
                pairs[[length(pairs) + 1L]] <- data.table(
                    indicator = ind, period = per, insp_date = b$as_of_date[i],
                    afro_date = a$as_of_date[j], insp_value = b$value[i],
                    afro_value = a$value[j],
                    diff = b$value[i] - a$value[j],
                    ratio = b$value[i] / a$value[j])
            }
        }
    }
}
insp_vs_afro <- if (length(pairs)) rbindlist(pairs) else data.table(
    indicator = character(), period = character(), insp_date = character(),
    afro_date = character(), insp_value = numeric(), afro_value = numeric(),
    diff = numeric(), ratio = numeric())
setorder(insp_vs_afro, indicator, insp_date)

#' Where the earliest tables give a bed count per facility, the sum of those
#' facility counts against the national total the same report gives, as a
#' check of how complete the facility columns are.
facility_beds <- combined[source == "insp" & level == "facility" &
    indicator == "beds_capacity"]
if (nrow(facility_beds)) {
    by_doc <- facility_beds[, .(facility_sum = sum(value)), by = doc_id]
    national_beds <- combined[source == "insp" & level == "national" &
        indicator == "beds_capacity", .(doc_id, national_value = value)]
    vs_national <- merge(by_doc, national_beds, by = "doc_id", all.x = TRUE)
    vs_national[, `:=`(indicator = "beds_capacity (facility sum vs national)",
        period = "point", insp_date = doc_id, afro_date = NA_character_,
        insp_value = facility_sum, afro_value = national_value,
        diff = facility_sum - national_value,
        ratio = facility_sum / national_value)]
    insp_vs_afro <- rbindlist(list(insp_vs_afro,
        vs_national[, .(indicator, period, insp_date, afro_date, insp_value,
            afro_value, diff, ratio)]), use.names = TRUE)
}

fwrite(insp_vs_afro, capacity_insp_vs_afro_path())
message("\nWritten: ", capacity_insp_vs_afro_path(), " (", nrow(insp_vs_afro),
    " comparisons).")
if (nrow(insp_vs_afro)) print(insp_vs_afro)

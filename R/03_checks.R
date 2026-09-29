#!/usr/bin/env Rscript
# ai-written
#'
#' Refuse to let a broken build pass for a finished one.
#'
#' Every check here is about internal consistency, not about whether the model
#' read the report well. That question is settled upstream, by the quote gate
#' in R/02_resolve.R, and cannot be reopened here. What this script asks is
#' narrower and answerable: does every event name a facility the registry
#' knows, does every facility's summary follow from its own events, is every
#' date one the corpus could have produced.
#'
#' The facilities table is recomputed from the events table by a second,
#' independent implementation and compared column by column. Two
#' implementations agreeing is weak evidence and one disagreeing is strong
#' evidence, which is the useful direction: a silent change to the derivation
#' shows up as a mismatch rather than as a number nobody checks.
#'
#' Exit 1 on any failure, 0 otherwise. Counts print either way.
#'
#' Usage:
#'     Rscript R/03_checks.R

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))
source(here::here("R", "lib", "corpus.R"))
source(here::here("R", "lib", "capacity_preferred.R"))

#' The fixed capacity vocabulary, mirrored from `R/30_capacity.R`: both
#' sources, WHO AFRO and INSP, write into `data/capacity_indicators.csv`
#' under these same values.
INDICATORS <- c("beds_capacity", "beds_occupied", "bed_occupancy_pct",
    "patients_in_isolation", "admissions", "discharges_recovered",
    "deaths_in_facility", "escapes", "facilities_operational",
    "laboratories_testing")
LEVELS <- c("national", "province", "health_zone", "facility")
UNITS <- c("beds", "patients", "percent", "facilities", "laboratories")
PERIODS <- c("point", "24h", "7d", "cumulative")

EVENTS <- c("planned", "under_construction", "opened", "operating", "expanded",
    "strained", "incident", "closed", "mention_only")
IN_SERVICE <- c("operating", "expanded", "strained", "incident")

failures <- character()
fail <- function(...) failures <<- c(failures, paste0(...))

#' Prints the first few offending rows so a failure names what to look at
#' rather than only how many there are.
show <- function(dt, n = 6L) {
    if (!nrow(dt)) return(invisible(NULL))
    print(head(dt, n))
    if (nrow(dt) > n) message("  ... and ", nrow(dt) - n, " more")
}

events <- fread(events_path())
facilities <- fread(facilities_path())
registry <- fread(registry_path())

# ------------------------------------------------------------- rejections

#' A reject is a quote that is not a span of the report, or one that does not
#' name what it evidences. Either way the event is out of the data. The first
#' fix is to reread that report: over the corpus that cleared 13 of 14.
#'
#' What remains is a paraphrase the model repeats. Acknowledging one in
#' `checks/rejected_acknowledged.csv` says a person read it against the report
#' and expects no rerun to fix it. It admits nothing: the event stays out of
#' the data exactly as before, and only the build's exit code changes, so that
#' a fresh reject is visible against a clean run rather than lost in a count
#' that was never zero.
if (file.exists(rejected_path())) {
    rej <- fread(rejected_path())
    known <- if (file.exists(acknowledged_path())) {
        fread(acknowledged_path(), colClasses = "character")
    } else {
        data.table(sitrep = character(), facility_raw = character(),
            reason = character())
    }
    if (nrow(rej)) {
        key <- function(d) paste(as.integer(d$sitrep), d$facility_raw, d$reason)
        rej[, acknowledged := key(rej) %in% key(known)]
        if (rej[!(acknowledged), .N]) {
            fail(rej[!(acknowledged), .N], " rejected events not acknowledged in ",
                acknowledged_path())
            print(rej[!(acknowledged), .N, by = reason])
        }
        if (rej[(acknowledged), .N]) {
            message(rej[(acknowledged), .N], " rejected events acknowledged, ",
                "still excluded from the data.")
        }
    }
}

# ----------------------------------------------------------------- events

bad_event <- events[!event %in% EVENTS]
if (nrow(bad_event)) {
    fail(nrow(bad_event), " events outside the closed vocabulary")
    show(bad_event[, .(sitrep, facility_raw, event)])
}

#' A named facility that resolved to nothing is a keying failure, not a
#' property of the report. Unnamed and ambiguous entries are meant to have no
#' facility_id.
orphan_named <- events[name_status == "named" & !nzchar(facility_id)]
if (nrow(orphan_named)) {
    fail(nrow(orphan_named), " named events with no facility_id")
    show(orphan_named[, .(sitrep, facility_raw, site_kind, event)])
}

unnamed_with_id <- events[name_status != "named" & nzchar(facility_id)]
if (nrow(unnamed_with_id)) {
    fail(nrow(unnamed_with_id), " unnamed or ambiguous events carrying a facility_id")
    show(unnamed_with_id[, .(sitrep, facility_raw, name_status, facility_id)])
}

# --------------------------------------------------------------- registry

unknown_id <- setdiff(events[nzchar(facility_id), unique(facility_id)],
    registry$facility_id)
if (length(unknown_id)) {
    fail(length(unknown_id), " facility_ids in the events not in the registry")
    message("  ", paste(head(unknown_id, 6), collapse = ", "))
}

#' One id, one kind of site. An id claimed by two kinds means the prefix and
#' the column disagree, and every count by site_kind is then wrong.
split_kind <- registry[, .(kinds = uniqueN(site_kind)), by = facility_id][kinds > 1]
if (nrow(split_kind)) {
    fail(nrow(split_kind), " registry facility_ids claimed by two site_kinds")
    show(registry[facility_id %in% split_kind$facility_id,
        .(facility_id, facility_raw, site_kind)])
}

dup_alias <- registry[, .N, by = .(facility_raw, site_kind)][N > 1]
if (nrow(dup_alias)) {
    fail(nrow(dup_alias), " spellings listed twice in the registry")
    show(dup_alias)
}

# ------------------------------------------------------------------ dates

#' The report date comes from the corpus, so any date outside its range is a
#' merge that went wrong rather than a report that is late.
meta <- rbindlist(lapply(corpus_ids(), function(id) {
    m <- read_report(id)$meta
    data.table(sitrep = id, report_date = as.Date(m$report_date))
}))
span <- range(meta$report_date, na.rm = TRUE)

out_of_range <- events[is.na(report_date) | report_date < span[1] | report_date > span[2]]
if (nrow(out_of_range)) {
    fail(nrow(out_of_range), " events with a report_date outside the corpus (",
        span[1], " to ", span[2], ")")
    show(out_of_range[, .(sitrep, facility_raw, report_date)])
}

wrong_date <- merge(events[, .(sitrep, report_date)], meta,
    by = "sitrep", suffixes = c("", "_corpus"))[report_date != report_date_corpus]
if (nrow(wrong_date)) {
    fail(nrow(unique(wrong_date)), " events whose report_date is not the corpus's")
    show(unique(wrong_date))
}

#' An event dated after the report that carries it is a model reading a
#' forecast as a fact, or a year parsed wrongly.
future_event <- events[!is.na(event_date) & event_date > report_date + 1L]
if (nrow(future_event)) {
    fail(nrow(future_event), " events dated after the report that carries them")
    show(future_event[, .(sitrep, facility_raw, event, event_date, report_date)])
}

# ----------------------------------------------- facilities, recomputed

#' as.Date throughout: fread returns IDate, which is integer, and a group
#' with no matching date would otherwise return a double NA and break the
#' column type partway down the table.
#' Dates come back as character. fread returns IDate, whose storage is
#' integer, while an empty group's NA is a double, and data.table refuses a
#' column whose type changes partway down the table. The comparison below is
#' on character anyway.
first_of <- function(dates, keep) {
    d <- dates[keep & !is.na(dates)]
    if (!length(d)) NA_character_ else as.character(min(d))
}
published <- sort(unique(as.integer(sub("_v.*", "", corpus_ids()))))

res <- events[nzchar(facility_id)]
setorder(res, report_date, facility_id, event)
check <- res[, {
    real <- which(event != "mention_only")
    opened <- which(event == "opened")
    bedded <- which(!is.na(beds))
    last_real <- if (length(real)) real[which.max(report_date[real])] else NA_integer_
    .(
        site_kind_r = site_kind[which.max(tabulate(match(site_kind, unique(site_kind))))],
        date_first_mentioned_r = as.character(min(report_date)),
        first_mention_after_gap_r =
            !(min(as.integer(sub("_v.*", "", sitrep))) - 1L) %in% published &&
            min(as.integer(sub("_v.*", "", sitrep))) > 1L,
        date_first_planned_r = first_of(report_date,
            event %in% c("planned", "under_construction")),
        date_opening_announced_r = first_of(report_date, event == "opened"),
        date_opening_stated_r = first_of(event_date, seq_along(event) %in% opened),
        date_first_in_service_r = first_of(report_date, event %in% IN_SERVICE),
        status_latest_r = if (is.na(last_real)) "mention_only" else event[last_real],
        beds_latest_r = if (length(bedded))
            as.integer(beds[bedded[which.max(report_date[bedded])]]) else NA_integer_,
        date_last_mentioned_r = as.character(max(report_date)),
        n_sitreps_r = uniqueN(sitrep),
        n_events_r = .N
    )
}, by = facility_id]

missing_rows <- setdiff(check$facility_id, facilities$facility_id)
extra_rows <- setdiff(facilities$facility_id, check$facility_id)
if (length(missing_rows)) {
    fail(length(missing_rows), " facilities with events but no row")
    message("  ", paste(head(missing_rows, 6), collapse = ", "))
}
if (length(extra_rows)) {
    fail(length(extra_rows), " facilities rows with no events")
    message("  ", paste(head(extra_rows, 6), collapse = ", "))
}

cmp <- merge(facilities, check, by = "facility_id")
pairs <- sub("_r$", "", grep("_r$", names(check), value = TRUE))
for (col in pairs) {
    a <- cmp[[col]]
    b <- cmp[[paste0(col, "_r")]]
    #' Dates read back from CSV as IDate, so compare as character and treat
    #' NA as its own value rather than as a mismatch with itself.
    differs <- which(!(is.na(a) & is.na(b)) &
        (is.na(a) | is.na(b) | as.character(a) != as.character(b)))
    if (length(differs)) {
        fail(length(differs), " facilities rows where ", col,
            " does not follow from the events")
        show(cmp[differs, c("facility_id", col, paste0(col, "_r")), with = FALSE])
    }
}

# --------------------------------------------------------------- capacity

#' `preferred` says which of two figures sharing a key a series should read.
#' Two things can go wrong once that column exists: a key with two rows both
#' marked `preferred`, which would leave a series unable to choose, and a
#' key with no `preferred` row at all that is not accounted for in
#' `checks/capacity_conflicts.csv`, which would hide an unsettled conflict
#' rather than record it. Both are failures; neither is about whether the
#' model read a report well.
if (file.exists(capacity_path())) {
    capacity <- read_capacity_csv(capacity_path())
    if ("preferred" %in% names(capacity)) {
        key_cols <- c("source", "doc_id", "as_of_date", "indicator", "level",
            "country", "place", "period", "unit")
        capacity[, preferred := preferred == "TRUE"]

        two_preferred <- capacity[, .(n_preferred = sum(preferred)), by = key_cols][
            n_preferred > 1L]
        if (nrow(two_preferred)) {
            fail(nrow(two_preferred), " capacity_indicators.csv keys with more than one preferred row")
            show(two_preferred)
        }

        no_preferred <- unique(capacity[, .(n_preferred = sum(preferred)), by = key_cols][
            n_preferred == 0L, ..key_cols])
        if (nrow(no_preferred)) {
            conflicts <- if (file.exists(capacity_conflicts_path())) {
                fread(capacity_conflicts_path(), colClasses = "character")
            } else {
                data.table()
            }
            listed <- if (nrow(conflicts)) unique(conflicts[, ..key_cols]) else
                no_preferred[0]
            unlisted <- fsetdiff(no_preferred, listed)
            if (nrow(unlisted)) {
                fail(nrow(unlisted), " capacity_indicators.csv keys with no preferred row, ",
                    "not listed in ", capacity_conflicts_path())
                show(unlisted)
            }
        }
        message("\nCapacity figures ", nrow(capacity), ", ",
            capacity[(preferred), .N], " preferred, ",
            capacity[ambiguous_key == "TRUE" & !(preferred), .N],
            " left unpreferred inside a conflicting key.")
    } else {
        message("\ncapacity_indicators.csv has no preferred column yet; ",
            "run R/31_capacity_preferred.R.")
    }

    #' `source == "insp"` rows are read from a table cell, not a model call,
    #' but the same three things can still go wrong: a value outside the
    #' fixed vocabulary, a value that could not be a real count or rate, and
    #' an `evidence_quote` whose data line is not actually in the file `url`
    #' names. The last of these needs a bvd-sitreps checkout; where one is
    #' not on hand, that sub-check is skipped and says so, rather than
    #' failing the whole build over a corpus that was never fetched here.
    insp <- capacity[source == "insp"]
    if (nrow(insp)) {
        insp[, value := as.numeric(value)]

        bad_indicator <- insp[!indicator %in% INDICATORS]
        if (nrow(bad_indicator)) {
            fail(nrow(bad_indicator), " insp capacity rows with an indicator ",
                "outside the fixed vocabulary")
            show(bad_indicator[, .(doc_id, indicator, level, value)])
        }

        bad_level <- insp[!level %in% LEVELS]
        if (nrow(bad_level)) {
            fail(nrow(bad_level), " insp capacity rows with a level outside ",
                "national, province, health_zone, facility")
            show(bad_level[, .(doc_id, indicator, level, value)])
        }

        bad_unit <- insp[!unit %in% UNITS]
        if (nrow(bad_unit)) {
            fail(nrow(bad_unit), " insp capacity rows with a unit outside ",
                "the fixed vocabulary")
            show(bad_unit[, .(doc_id, indicator, unit, value)])
        }

        bad_period <- insp[!period %in% PERIODS]
        if (nrow(bad_period)) {
            fail(nrow(bad_period), " insp capacity rows with a period outside ",
                "point, 24h, 7d, cumulative")
            show(bad_period[, .(doc_id, indicator, period, value)])
        }

        negative <- insp[!is.na(value) & value < 0]
        if (nrow(negative)) {
            fail(nrow(negative), " insp capacity rows with a negative value")
            show(negative[, .(doc_id, indicator, level, value)])
        }

        bad_occupancy <- insp[indicator == "bed_occupancy_pct" &
            !is.na(value) & (value < 0 | value > 300)]
        if (nrow(bad_occupancy)) {
            fail(nrow(bad_occupancy), " insp bed_occupancy_pct rows outside 0-300")
            show(bad_occupancy[, .(doc_id, level, place, value)])
        }

        sitreps_root_dir <- sitreps_root()
        if (!dir.exists(sitreps_root_dir)) {
            message("\nNo bvd-sitreps checkout at ", sitreps_root_dir,
                " (set BVD_SITREPS); skipping the insp evidence_quote line check.")
        } else {
            #' Only the last line of the quote needs to be a literal line of
            #' the file: a header-embedded bed count's quote is one line
            #' (the header itself), and a row value's quote is two (header,
            #' then data line). Either way the line the value came from must
            #' be checkable as a span of the file.
            insp[, quote_line := vapply(strsplit(evidence_quote, "\n", fixed = TRUE),
                function(x) x[length(x)], character(1))]
            by_url <- unique(insp[, .(url)])
            by_url[, path := file.path(sitreps_root_dir, url)]
            missing_file <- by_url[!file.exists(path)]
            if (nrow(missing_file)) {
                fail(nrow(missing_file), " insp capacity urls with no file at ",
                    "that path under ", sitreps_root_dir)
                show(missing_file)
            }
            found_lines <- by_url[file.exists(path), .(url,
                lines = list(readLines(path, warn = FALSE))), by = url]
            insp2 <- merge(insp, found_lines[, .(url, lines)], by = "url")
            bad_quote <- insp2[!vapply(seq_len(.N), function(i)
                quote_line[i] %in% lines[[i]], logical(1))]
            if (nrow(bad_quote)) {
                fail(nrow(bad_quote), " insp capacity rows whose evidence_quote ",
                    "data line is not a line of the file named in url")
                show(bad_quote[, .(doc_id, indicator, url, quote_line)])
            }
        }
        message("\nInsp capacity rows ", nrow(insp), ".")
    }
}

# ------------------------------------------------------- corroboration

GUESS_BASIS <- c("only_candidate", "name_word", "most_events")
GUESS_WITHHELD <- c("no_place", "several_places", "pre_opening", "host_unmatched", "tie")

#' A `facility_id` in the corroboration tables means a second publisher named
#' that facility. A match on place and kind alone is a guess and must sit in
#' `facility_id_guess`, or a join on `facility_id` counts it as confirmation.
for (path in Sys.glob(here::here("data", "external_corroboration_*.csv"))) {
    corr <- fread(path, colClasses = list(character = c("facility_id",
        "facility_id_guess", "guess_basis", "guess_withheld")))
    over_read <- corr[match_kind != "id" & nzchar(facility_id)]
    if (nrow(over_read)) {
        show(over_read[, .(doc_id, facility_raw, match_kind, facility_id)])
        fail(nrow(over_read), " rows in ", basename(path),
            " carry a facility_id without matching it by name")
    }
    unfilled <- corr[(match_kind == "id" & !nzchar(facility_id)) |
        (match_kind == "place_kind" & !nzchar(facility_id_guess))]
    if (nrow(unfilled)) {
        show(unfilled[, .(doc_id, facility_raw, match_kind)])
        fail(nrow(unfilled), " matched rows in ", basename(path), " name no facility")
    }
    unknown <- setdiff(c(corr$facility_id, corr$facility_id_guess), c("", registry$facility_id))
    if (length(unknown)) fail(length(unknown), " facility ids in ", basename(path),
        " not in the registry: ", paste(head(unknown, 3), collapse = ", "))

    #' `guess_basis` says how a `place_kind` row's facility was guessed, and
    #' carries nothing anywhere else.
    bad_basis <- corr[nzchar(guess_basis) & !guess_basis %in% GUESS_BASIS]
    if (nrow(bad_basis)) {
        show(bad_basis[, .(doc_id, facility_raw, match_kind, guess_basis)])
        fail(nrow(bad_basis), " rows in ", basename(path),
            " carry a guess_basis outside the closed vocabulary")
    }
    basis_mismatch <- corr[nzchar(guess_basis) != (match_kind == "place_kind")]
    if (nrow(basis_mismatch)) {
        show(basis_mismatch[, .(doc_id, facility_raw, match_kind, guess_basis)])
        fail(nrow(basis_mismatch), " rows in ", basename(path),
            " have a guess_basis that disagrees with match_kind")
    }

    #' `guess_withheld` says why a guess was not made, so it never sits on a
    #' row that already has one, by name or by place and kind.
    bad_withheld <- corr[nzchar(guess_withheld) & !guess_withheld %in% GUESS_WITHHELD]
    if (nrow(bad_withheld)) {
        show(bad_withheld[, .(doc_id, facility_raw, match_kind, guess_withheld)])
        fail(nrow(bad_withheld), " rows in ", basename(path),
            " carry a guess_withheld outside the closed vocabulary")
    }
    withheld_on_matched <- corr[match_kind %in% c("id", "place_kind") & nzchar(guess_withheld)]
    if (nrow(withheld_on_matched)) {
        show(withheld_on_matched[, .(doc_id, facility_raw, match_kind, guess_withheld)])
        fail(nrow(withheld_on_matched), " rows in ", basename(path),
            " carry a guess_withheld on a row already matched")
    }

    guess_mismatch <- corr[nzchar(facility_id_guess) != nzchar(guess_basis)]
    if (nrow(guess_mismatch)) {
        show(guess_mismatch[, .(doc_id, facility_raw, facility_id_guess, guess_basis)])
        fail(nrow(guess_mismatch), " rows in ", basename(path),
            " have a facility_id_guess that disagrees with guess_basis")
    }
}

# ----------------------------------------------------------------- counts

message("\nEvents ", nrow(events), " over ", uniqueN(events$sitrep),
    " reports, ", span[1], " to ", span[2], ".")
print(events[, .N, by = event][order(-N)])

message("\nFacilities ", nrow(facilities), ".")
print(dcast(facilities, site_kind ~ ifelse(nzchar(province), province, "(none)"),
    fun.aggregate = length, value.var = "facility_id"))

message("\nIn more than two reports, by kind:")
print(facilities[n_sitreps >= 3L, .N, by = site_kind][order(-N)])

message("\nRegistry ", nrow(registry), " spellings, ",
    sum(!registry$reviewed), " unreviewed.")
message("Flagged facilities ", sum(nzchar(facilities$flags)), ":")
print(facilities[nzchar(flags), .N, by = flags][order(-N)])
message("Events with no facility_id ", events[!nzchar(facility_id), .N],
    " (", events[!nzchar(facility_id), uniqueN(place_key)], " places).")

# ----------------------------------------------------------------- verdict

if (length(failures)) {
    message("\nFAILED ", length(failures), ":")
    for (f in failures) message("  - ", f)
    quit(status = 1L)
}
message("\nAll checks passed.")

# ai-written
#' Which figure a capacity series should read, when a document gives more
#' than one for the same thing.
#'
#' `R/30_capacity.R` flags `ambiguous_key` where a document states more than
#' one figure for the same indicator, level, place and date. Two things
#' happen here, shared between that script's own end-of-run summary and
#' `R/31_capacity_preferred.R`, which is the one that writes the result:
#'
#'   1. The key is corrected. The original key left out `country` and
#'      `unit`. Without `country`, a national total for Uganda collided with
#'      the national total for the Democratic Republic of the Congo under
#'      one key (`afro-05`, 14 June: DRC 48 recoveries, Uganda 5), and a
#'      total collided with its own confirmed/suspected breakdown taken from
#'      the same sentence. Neither is a disagreement about one quantity, so
#'      neither belongs under `ambiguous_key`. Adding `country` and `unit`
#'      to the key resolves 12 of the 25 conflict groups the coarse key
#'      found, with no judgement involved; `unit` never actually differs
#'      within a surviving group, but the decision record asked for it to be
#'      checked and it is cheap to keep checking.
#'
#'   2. What remains is resolved in order: rule 1 ("increased/declined from
#'      A to B" wording, where the model split one sentence into two rows),
#'      rule 2 (an occupancy percentage consistent with a numerator and
#'      denominator stated in the same document, within 0.5 percentage
#'      points), rule 3 (a headline figure block, which reads like a
#'      flattened table fragment, over a narrative sentence), and finally a
#'      row in `registry/capacity_decisions.csv` for the groups those three
#'      do not settle. A group with no decision row and no rule match is
#'      left with every row `preferred = FALSE`, which is itself the record
#'      that it is still unsettled.
#'
#' The rules are `kathsherratt`'s, recorded as decision `capacity-rules` in
#' `registry/capacity_decisions.csv`; this file is their implementation.

suppressMessages(library(data.table))

#' `fread()` cannot correctly round-trip a field that mixes an embedded
#' newline with more than one quoted segment, which is exactly the shape of
#' an `evidence_quote` built from a header line and a data line where the
#' data line itself has comma-decimal values in quoted cells (`"93,9%"`):
#' each read through `fread` doubles the escaping further, so a value like
#' `"93,9%"` inside the quote turns into `""93,9%""`, then `""""93,9%""""`,
#' and so on every time the file is read and rewritten. `fwrite()` itself
#' writes standard, correctly escaped CSV; the corruption is `fread()`
#' failing to unescape it on the way back in. Base R's `read.csv()` parses
#' the same file correctly, so `capacity_indicators.csv` is read with this
#' wherever a script needs to read back what it or another script wrote,
#' rather than with `fread()` directly.
read_capacity_csv <- function(path) {
    data.table::as.data.table(utils::read.csv(path, colClasses = "character",
        check.names = FALSE, na.strings = NULL, encoding = "UTF-8"))
}

CAPACITY_KEY_COLS <- c("source", "doc_id", "as_of_date", "indicator",
    "level", "country", "place", "period", "unit")

#' Recompute `ambiguous_key` on the corrected key, in place.
mark_capacity_ambiguous <- function(dt) {
    #' Dropped and re-added rather than assigned in place: `data.table`
    #' otherwise coerces the logical result back into the column's existing
    #' storage type, which is `character` on a column just read from CSV.
    dt[, ambiguous_key := NULL]
    dt[, ambiguous_key := .N > 1L, by = CAPACITY_KEY_COLS]
    dt
}

#' The value after "to" in a "from A to B" sentence, whichever of A and B is
#' spelled as a digit. Only B is needed: A is the earlier figure and is
#' never preferred under rule 1. Returns NA where the sentence does not have
#' this shape, which includes any quote where "from" is not followed
#' anywhere by "to <number>" (`"absconded from care facilities"` has no
#' "to" at all and is correctly left unmatched).
extract_change_to_value <- function(quote) {
    if (!grepl("from", quote, ignore.case = TRUE)) return(NA_real_)
    after <- sub(".*?\\bfrom\\b", "", quote, ignore.case = TRUE, perl = TRUE)
    m <- regexec("\\bto\\s+([0-9][0-9 , \n\t]*[0-9]|[0-9])", after,
        perl = TRUE)
    g <- regmatches(after, m)[[1]]
    if (length(g) < 2) return(NA_real_)
    suppressWarnings(as.numeric(gsub("[ , \n\t]", "", g[2])))
}

#' Apply rules 1-3, then the decisions file, to every conflicting group.
#'
#' `dt` is `capacity_indicators.csv`, read as a data.table. `decisions` is
#' `registry/capacity_decisions.csv`, read as a data.table with the
#' `capacity-rules` row itself excluded (it documents the rules; it names no
#' single group). Returns a list of `dt` (with `preferred` and `rule` added,
#' placed by the caller) and `conflicts` (one row a conflicting row, for
#' `checks/capacity_conflicts.csv`).
resolve_capacity_preferred <- function(dt, decisions) {
    dt <- copy(dt)
    mark_capacity_ambiguous(dt)
    dt[, preferred := !ambiguous_key]
    dt[, rule := fifelse(ambiguous_key, NA_character_, "no_conflict")]

    if (!dt[(ambiguous_key), .N]) {
        return(list(dt = dt, conflicts = dt[0][, !"ambiguous_key", with = FALSE]))
    }

    group_ids <- unique(dt[(ambiguous_key), ..CAPACITY_KEY_COLS])
    conflicts_log <- vector("list", nrow(group_ids))

    for (i in seq_len(nrow(group_ids))) {
        gk <- group_ids[i]
        match <- rep(TRUE, nrow(dt))
        for (col in CAPACITY_KEY_COLS) match <- match & (dt[[col]] == gk[[col]])
        idx <- which(match)

        vals <- dt$value[idx]
        quotes <- dt$evidence_quote[idx]
        chosen <- NA_integer_
        rule_label <- NA_character_

        # ---- rule 1: "increased/declined from A to B" in one shared quote
        if (length(unique(quotes)) == 1L) {
            b <- extract_change_to_value(quotes[1])
            if (!is.na(b)) {
                hit <- which(abs(vals - b) < 1e-6)
                if (length(hit) == 1L) {
                    chosen <- idx[hit]
                    rule_label <- "rule1_change_wording"
                }
            }
        }

        # ---- rule 2: occupancy consistent with a stated numerator/denominator
        if (is.na(chosen) && dt$indicator[idx[1]] == "bed_occupancy_pct") {
            kr <- dt[idx[1]]
            same <- function(other) dt$doc_id == kr$doc_id &
                dt$level == kr$level & dt$country == kr$country &
                dt$place == kr$place & dt$as_of_date == kr$as_of_date &
                dt$indicator == other
            cap <- dt$value[same("beds_capacity")]
            occ <- dt$value[same("beds_occupied")]
            if (!length(occ)) occ <- dt$value[same("patients_in_isolation")]
            if (length(cap) == 1L && length(occ) == 1L) {
                calc <- occ / cap * 100
                hit <- which(abs(vals - calc) <= 0.5)
                if (length(hit) == 1L) {
                    chosen <- idx[hit]
                    rule_label <- "rule2_numerator_denominator"
                }
            }
        }

        # ---- rule 3: a headline block (a flattened table fragment, which
        # carries a newline the model kept) over a narrative sentence
        if (is.na(chosen)) {
            has_nl <- grepl("\n", quotes, fixed = TRUE)
            if (sum(has_nl) == 1L && length(unique(quotes)) > 1L) {
                chosen <- idx[which(has_nl)]
                rule_label <- "rule3_headline_over_narrative"
            }
        }

        # ---- a decision, read from the quotes by a person or claude-code
        if (is.na(chosen)) {
            kr <- dt[idx[1]]
            dmatch <- decisions[doc_id == kr$doc_id & as_of_date == kr$as_of_date &
                indicator == kr$indicator & level == kr$level &
                country == kr$country & place == kr$place & period == kr$period]
            if (nrow(dmatch) == 1L && nzchar(dmatch$preferred_value)) {
                pv <- suppressWarnings(as.numeric(dmatch$preferred_value))
                hit <- which(abs(vals - pv) < 1e-6)
                if (length(hit) == 1L) {
                    chosen <- idx[hit]
                    rule_label <- paste0("decision:", dmatch$decision_id)
                }
            } else if (nrow(dmatch) == 1L) {
                rule_label <- paste0("unsettled:", dmatch$decision_id)
            }
        }

        if (is.na(rule_label)) rule_label <- "unsettled"

        dt[idx, preferred := FALSE]
        dt[idx, rule := rule_label]
        if (!is.na(chosen)) dt[chosen, preferred := TRUE]

        conflicts_log[[i]] <- dt[idx, .(source, doc_id, as_of_date, indicator,
            level, country, place, period, unit, value, confidence, preferred,
            rule, evidence_quote)]
    }

    list(dt = dt, conflicts = rbindlist(conflicts_log, use.names = TRUE))
}

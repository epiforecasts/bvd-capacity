#!/usr/bin/env Rscript
# ai-written
#'
#' Which of two figures for the same thing a capacity series should read.
#'
#' `R/30_capacity.R` flags `ambiguous_key` where a document gives more than
#' one figure for the same indicator, level, place and date, and neither is
#' dropped: both are evidence. This script decides which one a series
#' consumer should use, without touching either value or its quote.
#'
#' It does three things, in order:
#'
#'   1. Corrects the key. `ambiguous_key` as `R/30_capacity.R` wrote it left
#'      out `country` and `unit`, so a national total for Uganda collided
#'      with the DRC national total under one key, and a total collided with
#'      its own confirmed/suspected breakdown taken from one sentence.
#'      Neither is a genuine conflict. Adding `country` and `unit` to the
#'      key (`R/lib/capacity_preferred.R`) drops 12 of the original 25
#'      conflict groups, with no judgement, and this script overwrites the
#'      committed `ambiguous_key` column with the corrected value.
#'   2. Applies rules 1-3 of decision `capacity-rules`
#'      (`registry/capacity_decisions.csv`) to every group the corrected key
#'      still flags: change wording, occupancy consistent with a stated
#'      numerator and denominator, then headline block over narrative.
#'   3. Applies the remaining rows of `registry/capacity_decisions.csv`:
#'      one settled by reading the quotes, two left `unsettled` because the
#'      quotes describe two different quantities or give no total to choose
#'      between.
#'
#' `preferred` is written back into `data/capacity_indicators.csv`, after
#' `ambiguous_key`. `checks/capacity_conflicts.csv` lists every row that ever
#' shared a key with another: its value, whether it is preferred, and which
#' rule or decision chose it (or `unsettled` if none did).
#'
#' No model call, so this runs from the committed
#' `data/capacity_indicators.csv` with no cache and no corpus checkout.
#' `R/30_capacity.R`'s own end-of-run summary depends on `preferred`, so a
#' rerun of that script should be followed by this one: see its usage
#' comment.
#'
#' Usage:
#'     Rscript R/31_capacity_preferred.R

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))
source(here::here("R", "lib", "capacity_preferred.R"))

dt <- read_capacity_csv(capacity_path())
# A rerun reads a file that already carries `preferred`; drop it so the
# column is recomputed and placed once.
if ("preferred" %in% names(dt)) dt[, preferred := NULL]
orig_cols <- names(dt)
dt[, value := as.numeric(value)]

decisions <- fread(capacity_decisions_path(), colClasses = "character")
decisions <- decisions[decision_id != "capacity-rules"]

before_ambiguous <- sum(dt$ambiguous_key == "TRUE")

res <- resolve_capacity_preferred(dt, decisions)
out <- res$dt

after_ambiguous <- out[(ambiguous_key), .N]

out[, ambiguous_key := as.character(ambiguous_key)]
out[, preferred := as.character(preferred)]
new_order <- append(orig_cols, "preferred", after = which(orig_cols == "ambiguous_key"))
setcolorder(out, new_order)
fwrite(out[, ..new_order], capacity_path())

fwrite(res$conflicts, capacity_conflicts_path())

# ----------------------------------------------------------------- report

message("ambiguous_key: ", before_ambiguous, " rows before the key correction, ",
    after_ambiguous, " after (country and unit added).")

if (nrow(res$conflicts)) {
    groups <- unique(res$conflicts[, .(doc_id, as_of_date, indicator)])
    message("\n", nrow(groups), " conflict groups over ", nrow(res$conflicts),
        " rows, resolved by:")
    by_rule <- res$conflicts[, .N, by = .(
        rule = fifelse(grepl("^decision:", rule), "decision (claude-code)",
            fifelse(grepl("^unsettled", rule), "unsettled", rule)))]
    print(by_rule[order(-N)])

    unresolved <- res$conflicts[grepl("^unsettled", rule)]
    if (nrow(unresolved)) {
        message("\nStill unsettled, preferred = FALSE for the whole group:")
        print(unique(unresolved[, .(doc_id, as_of_date, indicator)]))
    }
}

message("\nWritten: ", capacity_path())
message("Written: ", capacity_conflicts_path())

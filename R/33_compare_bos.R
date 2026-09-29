#!/usr/bin/env Rscript
# ai-written
#'
#' This repository's INSP province capacity rows against BVDOutbreakSize's
#' independent province-care reads.
#'
#' `R/32_capacity_insp.R` reads province-level bed and patient-flow figures
#' from the INSP occupation tables into `data/capacity_indicators.csv`.
#' BVDOutbreakSize reads the same tables independently, twice over:
#' `data/province_care_scanned.csv` is its deterministic scan,
#' `data/province_care_read.csv` a blind read of the same PDFs made without
#' sight of the scan (PR #969, branch `feat/province-admissions-forecast`).
#' Three independent reads of the same tables is worth comparing.
#'
#' Six quantities line up between the two vocabularies:
#'
#'   * `patients_in_isolation` <-> `patients_isolated`, both "Patients en
#'     isolement (Fin de journée)" as of the report date. Checked against
#'     SitRep 018 Ituri (158 both sides).
#'   * `beds_capacity` <-> `beds`
#'   * `bed_occupancy_pct` <-> `occupancy_rate_pct`
#'   * `admissions` (24h) <-> `admissions_24h`
#'   * `discharges_recovered` <-> `recovered_24h`. `registry/insp_capacity_labels.csv`
#'     maps `Sorties Guéris` alone (not the row total) to `discharges_recovered`,
#'     and BVDOutbreakSize's own README says `recovered_24h` is that same
#'     "Guéris" line; its `discharges_24h` is the total across every exit
#'     category (recovered, died, non-case, escaped, transferred), which this
#'     repository has no single indicator for (`Total sorties` is
#'     deliberately left unmapped in the registry as a sum, not a vocabulary
#'     indicator) and so is carried here as `only_bos`, never compared.
#'   * `deaths_in_facility` <-> `deaths_incare_24h`
#'
#' Two more of this repository's indicators appear with no BVDOutbreakSize
#' match, `only_ours`: `beds_occupied` and `escapes`. `beds_occupied` is not
#' `patients_in_isolation` under another name: it is "Patients présents au
#' lit (J-1)", dated to the day *before* the report
#' (`as_of_date = report_date - 1`, set in `R/32_capacity_insp.R`), a
#' narrower count of patients occupying a bed rather than every patient in
#' isolation. SitRep 018 Ituri gives 147 for `beds_occupied` and 158 for
#' `patients_in_isolation`; BVDOutbreakSize's `patients_isolated` for that
#' row is also 158, so the two INSP quantities are kept apart here rather
#' than reconciled into one.
#'
#' Matching is on (`doc_id` == `sitrep`, `place` == `province`), both as the
#' zero-padded SitRep number string; province names already agree between
#' the two vocabularies (`Ituri`, `Nord-Kivu`, ...). The overlap is
#' BVDOutbreakSize's table-era rows, SitRep 018 to 080, where this
#' repository's INSP tables stop; either side can have rows the other
#' lacks outside that stretch or where a province did not report that day.
#'
#' No model call. Needs a BVDOutbreakSize checkout: `bos_root()` in
#' `R/lib/paths.R` finds it by path, exactly as `sitreps_root()` finds
#' bvd-sitreps, and this script never fetches. With `BVD_OUTBREAKSIZE_REF`
#' set, the two BVDOutbreakSize CSVs are read from that ref via `git show`
#' rather than the working tree, so a comparison can be pinned to a PR
#' branch without checking it out; the resolved commit SHA is recorded in
#' every output row as `bos_commit`.
#'
#' Usage:
#'     Rscript R/33_compare_bos.R
#'     BVD_OUTBREAKSIZE_REF=origin/feat/province-admissions-forecast Rscript R/33_compare_bos.R

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))
source(here::here("R", "lib", "capacity_preferred.R"))

BOS_REF <- Sys.getenv("BVD_OUTBREAKSIZE_REF", unset = "")

#' `git show <ref>:<relpath>` inside the BVDOutbreakSize checkout, as lines.
#' Never a fetch: `ref` must already be reachable there.
git_show <- function(ref, relpath) {
    out <- suppressWarnings(system2("git",
        c("-C", bos_root(), "show", paste0(ref, ":", relpath)),
        stdout = TRUE, stderr = TRUE))
    status <- attr(out, "status")
    if (!is.null(status) && status != 0L) {
        stop("git -C ", bos_root(), " show ", ref, ":", relpath,
            " failed:\n", paste(out, collapse = "\n"), call. = FALSE)
    }
    out
}

#' `data/<file>` from the BVDOutbreakSize checkout: the working tree, or,
#' with `BVD_OUTBREAKSIZE_REF` set, that ref's blob.
read_bos_csv <- function(file) {
    relpath <- file.path("data", file)
    if (nzchar(BOS_REF)) {
        txt <- git_show(BOS_REF, relpath)
        fread(text = paste(txt, collapse = "\n"), colClasses = "character",
            na.strings = NULL)
    } else {
        fread(file.path(bos_root(), relpath), colClasses = "character",
            na.strings = NULL)
    }
}

#' The commit the comparison was actually run against, for the record: the
#' resolved ref, or `HEAD` of the working tree when no ref is set.
bos_commit <- function() {
    ref <- if (nzchar(BOS_REF)) BOS_REF else "HEAD"
    system2("git", c("-C", bos_root(), "rev-parse", ref), stdout = TRUE)[1]
}

as_num <- function(x) suppressWarnings(as.numeric(ifelse(nzchar(trimws(x)), x, NA)))

# ------------------------------------------------------------------- read it

message("Reading BVDOutbreakSize checkout at ", bos_root(),
    if (nzchar(BOS_REF)) paste0(" (ref ", BOS_REF, ")") else " (working tree)")
sha <- bos_commit()
message("BVDOutbreakSize commit: ", sha)

scanned <- read_bos_csv("province_care_scanned.csv")
blind <- read_bos_csv("province_care_read.csv")

ours_raw <- read_capacity_csv(capacity_path())
ours_raw[, value := as.numeric(value)]
ours_raw[, preferred := toupper(preferred) == "TRUE"]

OUR_MAPPED <- c("patients_in_isolation", "beds_capacity", "bed_occupancy_pct",
    "admissions", "discharges_recovered", "deaths_in_facility")
OUR_ONLY <- c("beds_occupied", "escapes")

#' `indicator` -> the BVDOutbreakSize column it lines up with, per the
#' mapping in the header comment.
MAPPING <- data.table(
    indicator = c("patients_in_isolation", "beds_capacity", "bed_occupancy_pct",
        "admissions", "discharges_recovered", "deaths_in_facility"),
    bos_col = c("patients_isolated", "beds", "occupancy_rate_pct",
        "admissions_24h", "recovered_24h", "deaths_incare_24h"))

#' `admissions` is the only mapped indicator with a `cumulative` variant
#' (from SitRep 064, where the bare "Total admissions" row is a running
#' total rather than a second 24h figure; see `R/32_capacity_insp.R`). The
#' brief asks for the 24h figure only, so `cumulative` rows are dropped
#' before anything else runs, or they would compare against
#' BVDOutbreakSize's `admissions_24h` as if they were the same quantity.
ours <- ours_raw[source == "insp" & level == "province" & (preferred) &
    indicator %in% c(OUR_MAPPED, OUR_ONLY) &
    !(indicator == "admissions" & period != "24h"),
    .(sitrep = doc_id, report_date, province = place, indicator, value)]

# ------------------------------------------------------------- bos, long form

BOS_COLS <- c("patients_isolated", "beds", "occupancy_rate_pct",
    "admissions_24h", "recovered_24h", "deaths_incare_24h", "discharges_24h")

melt_bos <- function(dt, value_name) {
    long <- melt(dt, id.vars = c("sitrep", "report_date", "province"),
        measure.vars = intersect(BOS_COLS, names(dt)),
        variable.name = "bos_col", value.name = value_name,
        variable.factor = FALSE)
    long[[value_name]] <- as_num(long[[value_name]])
    long
}

scan_long <- melt_bos(scanned, "bos_scan")
read_long <- melt_bos(blind, "bos_read")

bos_long <- merge(scan_long[, .(sitrep, province, bos_col, bos_scan)],
    read_long[, .(sitrep, province, bos_col, bos_read)],
    by = c("sitrep", "province", "bos_col"), all = TRUE)

#' The report date each sitrep carries, from whichever side has it; both
#' sides should agree where both have a row, and this is not itself checked.
report_dates <- unique(rbindlist(list(
    ours[, .(sitrep, report_date)],
    scanned[, .(sitrep, report_date)],
    blind[, .(sitrep, report_date)]), use.names = TRUE))
report_dates <- report_dates[!duplicated(sitrep)]

# ------------------------------------------------------------------ join it

ours_mapped <- merge(ours[indicator %in% OUR_MAPPED], MAPPING, by = "indicator")

#' `all = TRUE`: a `bos_col` with no `indicator` row (only ever true of
#' `discharges_24h`, which nothing here maps to) survives as `only_bos`
#' without any special-casing.
joined <- merge(ours_mapped[, .(sitrep, province, bos_col, indicator, value)],
    bos_long, by = c("sitrep", "province", "bos_col"), all = TRUE)
joined[, quantity := fifelse(is.na(indicator), bos_col, indicator)]
joined <- joined[, .(sitrep, province, quantity, ours = value, bos_scan, bos_read)]

ours_only <- ours[indicator %in% OUR_ONLY,
    .(sitrep, province, quantity = indicator, ours = value,
        bos_scan = NA_real_, bos_read = NA_real_)]

compare <- rbindlist(list(joined, ours_only), use.names = TRUE)
compare <- merge(compare, report_dates, by = "sitrep", all.x = TRUE)
compare <- compare[!(is.na(ours) & is.na(bos_scan) & is.na(bos_read))]

# --------------------------------------------------------- agreement, status

#' `bed_occupancy_pct` is compared to within 0.5 percentage points, the same
#' tolerance `R/lib/capacity_preferred.R`'s rule 2 uses for a stated
#' numerator and denominator; every other quantity is a patient or bed
#' count, compared exactly.
tol_of <- function(q) fifelse(q == "bed_occupancy_pct", 0.5, 1e-9)
close_enough <- function(a, b, tol) !is.na(a) & !is.na(b) & abs(a - b) <= tol

compare[, tol := tol_of(quantity)]
compare[, agree_scan := close_enough(ours, bos_scan, tol)]
compare[, agree_read := close_enough(ours, bos_read, tol)]
#' `NA` where that BVDOutbreakSize read has no figure for this cell at all,
#' as distinct from `FALSE` for a figure that disagrees.
compare[is.na(ours) | is.na(bos_scan), agree_scan := NA]
compare[is.na(ours) | is.na(bos_read), agree_read := NA]

status_of <- function(ours, bos_scan, bos_read, tol) {
    have_ours <- !is.na(ours)
    have_scan <- !is.na(bos_scan)
    have_read <- !is.na(bos_read)
    if (!have_ours) return("only_bos")
    if (!have_scan && !have_read) return("only_ours")
    if (have_scan && have_read) {
        if (abs(bos_scan - bos_read) > tol) return("bos_reads_differ")
        return(if (abs(ours - bos_scan) <= tol) "all_agree" else "ours_differs")
    }
    bos_val <- if (have_scan) bos_scan else bos_read
    if (abs(ours - bos_val) <= tol) "all_agree" else "ours_differs"
}
compare[, status := mapply(status_of, ours, bos_scan, bos_read, tol)]

#' The largest gap among whichever of the three readings a row has, for
#' ranking disagreements; `NA` where fewer than two readings exist to
#' disagree at all (`only_ours`, `only_bos`).
max_gap <- function(a, b, c) {
    v <- c(a, b, c)[!is.na(c(a, b, c))]
    if (length(v) < 2L) return(NA_real_)
    max(v) - min(v)
}
compare[, gap := mapply(max_gap, ours, bos_scan, bos_read)]

compare[, bos_commit := sha]
compare[, tol := NULL]

setcolorder(compare, c("sitrep", "report_date", "province", "quantity",
    "ours", "bos_scan", "bos_read", "agree_scan", "agree_read", "status",
    "bos_commit"))
setorder(compare, quantity, sitrep, province)

fwrite(compare[, !"gap", with = FALSE], compare_bos_path())
message("\nWritten: ", compare_bos_path(), " (", nrow(compare), " rows).")

# ---------------------------------------------------------------- summary

message("\nCounts by quantity x status:")
print(dcast(compare, quantity ~ status, fun.aggregate = length, value.var = "sitrep"))

message("\n15 largest disagreements:")
top <- compare[!is.na(gap)][order(-gap)][seq_len(min(15L, .N))]
print(top[, .(sitrep, province, quantity, ours, bos_scan, bos_read, status, gap)])

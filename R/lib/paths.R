#' Where everything lives.
#'
#' This repository reads the INSP situation reports only through the corpus
#' that bvd-sitreps publishes, and finds it by path. Nothing here opens a PDF,
#' and nothing sources code from bvd-sitreps: a change there reaches this
#' repository as changed files in the corpus, which the cache keys below see,
#' never as changed behaviour. If a question cannot be answered from
#' `data/corpus/`, the fix belongs in bvd-sitreps.
#'
#' `BVD_SITREPS` points at a bvd-sitreps checkout; the default is a sibling
#' clone.

sitreps_root <- function() {
    Sys.getenv("BVD_SITREPS",
        unset = file.path(dirname(here::here()), "bvd-sitreps"))
}

corpus_dir <- function(...) file.path(sitreps_root(), "data", "corpus", ...)

sitreps_manifest_path <- function() {
    file.path(sitreps_root(), "data", "manifest.csv")
}

#' One model reading per report. Committed, because each costs a model call
#' to remake.
cache_dir <- function(...) here::here("data", "cache", ...)

registry_path <- function() here::here("registry", "facility_aliases.csv")

#' The naming decisions a person made, with who made them and when.
#' `R/09_apply_decisions.R` carries them into the vocabulary above; this file
#' is the record, and the only place the reasoning is written down.
decisions_path <- function() here::here("registry", "decisions.csv")

events_path <- function() here::here("data", "facility_events.csv")

facilities_path <- function() here::here("data", "facilities.csv")

#' Derived from the events, one row a facility: the interval an opening falls
#' in, and what kind of evidence bounds it.
opening_path <- function() here::here("data", "facility_opening.csv")

#' What the pipeline could not settle by itself. Small, committed, and read by
#' a person: the events dropped for a bad quote, the facilities that may be
#' duplicates, the places GRID3 disagrees with. A run that changes any of
#' these should show it in the diff.
checks_dir <- function(...) here::here("checks", ...)

rejected_path <- function() checks_dir("rejected_events.csv")

#' The rejects a person has read against the report and expects to stay
#' rejected. Acknowledging one keeps it out of the data and out of the build's
#' failure count; it is never a route to admitting a row.
acknowledged_path <- function() checks_dir("rejected_acknowledged.csv")

review_queue_path <- function() checks_dir("review_queue.csv")

place_check_path <- function() checks_dir("place_check.csv")

#' Everything a run leaves behind that nothing downstream reads: logs, raw
#' model stdout, model comparisons, the spend ledger. Not committed; delete it
#' and rerun.
runs_dir <- function(...) here::here("runs", ...)

#' One row a facility a flag, with the group that put it there. The facilities
#' table carries only the flag names, which says that a row is a judgement but
#' not who it is a judgement against.
flags_path <- function() here::here("data", "facility_flags.csv")

#' Who the reports name alongside a facility. A keyword scan over the corpus,
#' no model call, so it costs nothing to regenerate.
organisations_path <- function() here::here("data", "organisations.csv")

#' GRID3's health zones, areas, localities and facility names for the six
#' provinces the outbreak reaches. Committed, and rebuilt by
#' tools/grid3-lexicon.R when the GRID3 release changes.
grid3_path <- function() here::here("data", "reference", "grid3_places.csv")

#' A survey of what the corpus measures, not a step of the facility pipeline.
#' Rebuilt from the tables alone, with no model call, so it costs nothing to
#' regenerate when the corpus changes.
indicators_path <- function() here::here("data", "indicators.csv")

indicator_appearances_path <- function() {
    here::here("data", "indicator_appearances.csv")
}

#' The capacity figures read from the WHO AFRO weekly reports, one row a
#' figure. Written by `R/30_capacity.R`, and `R/31_capacity_preferred.R` adds
#' `preferred` afterwards.
capacity_path <- function() here::here("data", "capacity_indicators.csv")

#' The rule for choosing among figures that share a key, and the conflict
#' groups it does not settle mechanically, decided by reading the quotes.
#' `R/09_apply_decisions.R` is the naming equivalent of this file.
capacity_decisions_path <- function() {
    here::here("registry", "capacity_decisions.csv")
}

#' Every row that shared a key with another: its value, whether it is
#' `preferred`, and which rule or decision chose it. Written by
#' `R/31_capacity_preferred.R`.
capacity_conflicts_path <- function() checks_dir("capacity_conflicts.csv")

#' The closed set of INSP bed-table row labels, mapped by hand onto the fixed
#' capacity vocabulary. `R/32_capacity_insp.R` reads this; a label it does not
#' find here is a label a person has not looked at yet.
insp_capacity_labels_path <- function() {
    here::here("registry", "insp_capacity_labels.csv")
}

#' Every INSP table row `R/32_capacity_insp.R` could not use, and why:
#' misaligned cells, an unmapped label, or a value it could not parse.
insp_capacity_skipped_path <- function() checks_dir("insp_capacity_skipped.csv")

#' Where INSP and WHO AFRO both give a national figure for the same
#' indicator within three days, the two values side by side. Written by
#' `R/32_capacity_insp.R`.
capacity_insp_vs_afro_path <- function() checks_dir("capacity_insp_vs_afro.csv")

ensure_dirs <- function() {
    for (d in c(cache_dir(), dirname(registry_path()), checks_dir(),
        runs_dir("logs"))) {
        dir.create(d, recursive = TRUE, showWarnings = FALSE)
    }
    invisible(NULL)
}

#!/usr/bin/env Rscript
# ai-written
#'
#' Run the pipeline in the order the steps actually depend on, not the order
#' a reader might remember.
#'
#' Each step is its own Rscript process rather than being `source()`d into
#' one session, so a step that leaves state behind cannot change how a later
#' one behaves, and each step's exit status means what it says.
#'
#' Stages, run in this order within `derive` and independently by name:
#'
#'   derive    no model, no network. 02_resolve, 09_apply_decisions,
#'             02_resolve again, 03_checks, 06_opening, 07_organisations,
#'             04_review, 05_places, 08_decisions.
#'   extract   model calls. 01_facilities. ~3 hours; see the warning below.
#'   external  model calls. 21_external_extract, 22_external_match,
#'             23_registers_suggest. Needs bvd-sitreps' R/06-fetch-who.R to
#'             have already fetched the WHO documents in that repository.
#'   capacity  model calls. 30_capacity, then R/31_capacity_preferred.R if
#'             that file exists (it is being added on another branch).
#'   report    quarto render reports/, if a reports/ directory exists (it is
#'             being added on another branch).
#'
#' `derive` is the default because it is the one stage that is safe to run
#' any time, on no budget and no network: two of its nine steps resolve the
#' registry, which is why they appear twice. Applying decisions edits the
#' name vocabulary that 02_resolve.R reads, so a decision reaches the data
#' only on the next resolve; running 09_apply_decisions.R without a following
#' resolve leaves events pointing at ids the registry no longer holds, and
#' 03_checks.R fails with "facility_ids in the events not in the registry".
#'
#' A step exiting 3 means a model call hit its quota. That stops the run
#' here too; rerunning resumes from the cache, so nothing already read is
#' lost.
#'
#' Usage:
#'     Rscript R/main.R [stage ...]
#'
#' With no argument, runs `derive`. Multiple stages run in the order given,
#' e.g. `Rscript R/main.R extract derive` extracts first, then derives.

stages <- list(
    derive = c(
        "02_resolve.R",
        "09_apply_decisions.R",
        "02_resolve.R",
        "03_checks.R",
        "06_opening.R",
        "07_organisations.R",
        "04_review.R",
        "05_places.R",
        "08_decisions.R"
    ),
    extract = c(
        "01_facilities.R"
    ),
    external = c(
        "21_external_extract.R",
        "22_external_match.R",
        "23_registers_suggest.R"
    ),
    capacity = c(
        "30_capacity.R"
    )
    # "report" is handled separately below: it runs quarto, not an Rscript step.
)

#' Run one Rscript step, print its name and elapsed time, and stop the whole
#' run on a non-zero exit. Exit 3 (a model quota stop) is reported and the
#' run stops without treating it as an error to fix.
run_step <- function(step) {
    message("\n==> ", step)
    start <- Sys.time()
    status <- system2("Rscript", here::here("R", step))
    elapsed <- round(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
    message(step, " (", elapsed, "s)")
    if (status == 3L) {
        message("\n", step, " stopped at the model quota. Rerunning resumes ",
            "from the cache; nothing already read is lost.")
        quit(status = 3L)
    }
    if (status != 0L) {
        stop(step, " exited with status ", status, "; stopping.", call. = FALSE)
    }
}

run_derive <- function() {
    for (step in stages$derive) run_step(step)
}

run_extract <- function() {
    message(
        "\nR/01_facilities.R makes one model call a report over 116 reports ",
        "and takes about 3 hours. Run it detached, not in this session:\n\n",
        "    mkdir -p runs/logs\n",
        "    nohup caffeinate -is Rscript R/main.R extract \\\n",
        "        > runs/logs/facilities_$(date +%F-%H%M).log 2>&1 &\n\n",
        "Continuing here anyway."
    )
    if (!nzchar(Sys.getenv("GEMINI_BACKEND"))) Sys.setenv(GEMINI_BACKEND = "agy")
    if (!nzchar(Sys.getenv("GEMINI_LEDGER"))) {
        Sys.setenv(GEMINI_LEDGER = here::here("..", "bvd-sitreps", "outputs", "gemini-ledger.csv"))
    }
    for (step in stages$extract) run_step(step)
}

run_external <- function() {
    message(
        "\nR/21_external_extract.R reads WHO documents that bvd-sitreps ",
        "fetches and renders. If it has not already run R/06-fetch-who.R in ",
        "that repository, this stage has nothing to read."
    )
    if (!nzchar(Sys.getenv("GEMINI_BACKEND"))) Sys.setenv(GEMINI_BACKEND = "agy")
    for (step in stages$external) run_step(step)
}

run_capacity <- function() {
    if (!nzchar(Sys.getenv("GEMINI_BACKEND"))) Sys.setenv(GEMINI_BACKEND = "agy")
    for (step in stages$capacity) run_step(step)

    preferred <- here::here("R", "31_capacity_preferred.R")
    if (file.exists(preferred)) {
        run_step("31_capacity_preferred.R")
    } else {
        message("\nR/31_capacity_preferred.R not found; skipping (it is ",
            "being added on another branch).")
    }
}

run_report <- function() {
    if (dir.exists(here::here("reports"))) {
        message("\n==> quarto render reports/")
        start <- Sys.time()
        status <- system2("quarto", c("render", here::here("reports")))
        elapsed <- round(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
        message("quarto render reports/ (", elapsed, "s)")
        if (status != 0L) {
            stop("quarto render exited with status ", status, "; stopping.", call. = FALSE)
        }
    } else {
        message("\nreports/ not found; skipping (it is being added on ",
            "another branch).")
    }
}

RUNNERS <- list(
    derive = run_derive,
    extract = run_extract,
    external = run_external,
    capacity = run_capacity,
    report = run_report
)

args <- commandArgs(trailingOnly = TRUE)
requested <- if (length(args) == 0) "derive" else args

unknown <- setdiff(requested, names(RUNNERS))
if (length(unknown) > 0) {
    stop("Unknown stage(s): ", paste(unknown, collapse = ", "),
        ". Known stages: ", paste(names(RUNNERS), collapse = ", "), ".",
        call. = FALSE)
}

for (stage in requested) {
    message("\n### ", stage, " ###")
    RUNNERS[[stage]]()
}

message("\nDone.")

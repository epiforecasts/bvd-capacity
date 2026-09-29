#!/usr/bin/env Rscript
# ai-written
#'
#' Check the external readings, then say what they corroborate.
#'
#' Two steps, in the order the corpus pipeline uses them.
#'
#' First the quote gate, unchanged: an event survives only if its quote is a
#' span of the document the model was shown and names the facility it claims
#' to evidence. A publisher's document earns no exemption from this.
#'
#' Then matching, which is deliberately weaker than the register's own
#' resolution. A WHO sentence saying "the Ebola treatment centre in Bunia" is
#' not the INSP name `CTE de Bunia`, and pretending the two are one string
#' would manufacture agreement. So a match is made on place and kind, through
#' the same folding the register uses, and every row says how it was made:
#'
#'   `id`          the external name folds to a register facility_id
#'   `place_kind`  a facility of the same place and kind is guessed; how, in
#'                 `guess_basis`
#'   `place_only`  the place is in the register but no facility is guessed;
#'                 why, where there were candidates, in `guess_withheld`
#'   `unmatched`   the external document names a facility the register lacks
#'
#' Only an `id` row carries a `facility_id`. A `place_kind` row's facility is
#' a guess from place and kind, and sits in `facility_id_guess` instead, so
#' that filtering or joining on `facility_id` cannot count a guess as a
#' second publisher naming that facility.
#'
#' `unmatched` is the interesting column. It is either a facility the reports
#' never named, or a name for one they named differently, and both are worth
#' a person's eye. Nothing here writes into the register.
#'
#' Usage:
#'     Rscript R/22_external_match.R [--source=who_don]

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))
source(here::here("R", "lib", "corpus.R"))
source(here::here("R", "lib", "gemini.R"))
source(here::here("R", "lib", "external.R"))

args <- commandArgs(trailingOnly = TRUE)
SOURCE <- {
    hit <- grep("^--source=", args, value = TRUE)
    if (length(hit)) sub("^--source=", "", hit[1]) else "who_don"
}

facilities <- fread(facilities_path())
registry <- fread(registry_path())

fold <- function(x) {
    x <- iconv(x, "UTF-8", "ASCII//TRANSLIT")
    x <- gsub("['`^~\"]", "", x)
    x <- tolower(trimws(gsub("[^A-Za-z0-9]+", " ", x)))
    trimws(gsub(" +", " ", x))
}

#' Type words in two languages, because these documents are English and the
#' register's keys were built from French.
TYPE_WORDS <- paste0("\\b(ebola|virus|disease|treatment|transit|isolation|",
    "centre|center|centres|centers|unit|units|facility|hospital|ward|",
    "general|referral|reference|the|at|in|of|de|du|des|la|le|les|d|l|",
    "centre de traitement|cte|ctc|ct|ci|hgr|hopital)\\b")

name_key_of <- function(x) {
    trimws(gsub(" +", " ", gsub(TYPE_WORDS, " ", fold(x))))
}

registry[, rk := name_key_of(facility_raw)]
facilities[, fk := name_key_of(facility_name)]

# ----------------------------------------------------------- read the cache

files <- list.files(external_cache_dir(),
    pattern = paste0("^", SOURCE, "-.*\\.json$"), full.names = TRUE)
if (!length(files)) {
    stop("No extractions for ", SOURCE, ". Run R/21_external_extract.R.",
        call. = FALSE)
}

raw <- rbindlist(lapply(files, function(f) {
    got <- jsonlite::fromJSON(f, simplifyVector = FALSE)
    if (!length(got$events)) return(NULL)
    rbindlist(lapply(got$events, function(e) {
        as.data.table(c(list(source = got$source, doc_id = got$id,
            report_date = got$report_date, url = got$url,
            publisher = got$publisher, licence = got$licence,
            model = got$model), e))
    }), fill = TRUE)
}), fill = TRUE)

message(nrow(raw), " events read from ", length(files), " ", SOURCE,
    " documents.")

# ------------------------------------------------------------- the quote gate

raw[, evidence_quote := unescape_model_string(evidence_quote)]
raw[, text := vapply(doc_id, function(id) read_external_text(SOURCE, id),
    character(1))]
raw[, quote_ok := mapply(quote_matches, evidence_quote, text)]
raw[, names_ok := mapply(function(q, f) {
    grepl(normalise_for_match(f), normalise_for_match(q), fixed = TRUE)
}, evidence_quote, facility_raw)]
raw[, reason := fcase(
    !quote_ok, "quote is not a span of the document",
    !names_ok, "quote does not name the facility",
    default = "")]

rejected <- raw[nzchar(reason)]
if (nrow(rejected)) {
    fwrite(rejected[, .(source, doc_id, facility_raw, event, evidence_quote,
        reason)], checks_dir(paste0("rejected_external_", SOURCE, ".csv")))
}
ev <- raw[!nzchar(reason)]
message(nrow(ev), " events pass the quote gate, ", nrow(rejected), " rejected.")

# ----------------------------------------------------------------- matching

ev[, ext_key := name_key_of(facility_raw)]
ev[, place_key := fifelse(nzchar(place_raw), fold(place_raw), ext_key)]

by_name <- registry[, .(facility_id = facility_id[1]), by = .(rk, site_kind)]
ev <- merge(ev, by_name[, .(ext_key = rk, site_kind, id_by_name = facility_id)],
    by = c("ext_key", "site_kind"), all.x = TRUE)

#' Where the name does not fold to an id, a facility at the same place and
#' of the same kind is guessed, in this order:
#'
#'   `only_candidate`  one facility of that kind at that place
#'   `name_word`       the WHO name carries a host word (CME, HGR, ISTM)
#'                     that exactly one candidate shares
#'   `most_events`     otherwise, the candidate the INSP reports mention most
#'
#' and withheld, with the reason in `guess_withheld`, where a guess would be
#' worse than none:
#'
#'   `no_place`        no place to match on; an empty key matches every
#'                     facility whose place is also empty
#'   `several_places`  one mention covering sites in more than one place
#'   `pre_opening`     planned or under construction; the register's busiest
#'                     centre at a place is the one least likely to be the
#'                     one still being built
#'   `host_unmatched`  the name carries a host word no candidate shares
#'   `tie`             the busiest candidates have equal events
host_words_of <- function(x) {
    x <- fold(x)
    hits <- c(
        cme = grepl("\\bcme\\b|medical evangelique|evangelical medical", x),
        hgr = grepl("\\bhgr\\b|general referral|hopital general|referral hospital", x),
        istm = grepl("\\bistm\\b", x),
        iste = grepl("\\biste\\b", x)
    )
    names(hits)[hits]
}

candidates <- facilities[, .(place_key, site_kind, facility_id, n_events,
    host = lapply(paste(facility_name, facility_id), host_words_of))]

pick_guess <- function(pk, kind, raw, event) {
    none <- function(why) list(guess = NA_character_, basis = NA_character_,
        withheld = why)
    if (!nzchar(pk)) return(none("no_place"))
    cand <- candidates[place_key == pk & site_kind == kind]
    if (!nrow(cand)) return(none(NA_character_))
    if (grepl("\\b(and|et)\\b|centres|centers|facilities|units|\\bctes\\b|\\betcs\\b",
        fold(raw))) return(none("several_places"))
    if (event %in% c("planned", "under_construction")) return(none("pre_opening"))
    if (nrow(cand) == 1L) {
        return(list(guess = cand$facility_id, basis = "only_candidate",
            withheld = NA_character_))
    }
    host <- host_words_of(raw)
    if (length(host)) {
        hit <- cand[vapply(cand$host, function(h) all(host %in% h), logical(1))]
        if (nrow(hit) == 1L) {
            return(list(guess = hit$facility_id, basis = "name_word",
                withheld = NA_character_))
        }
        return(none("host_unmatched"))
    }
    top <- cand[n_events == max(n_events)]
    if (nrow(top) > 1L) return(none("tie"))
    list(guess = top$facility_id, basis = "most_events", withheld = NA_character_)
}

ev[, c("id_by_place", "guess_basis", "guess_withheld") := {
    g <- Map(pick_guess, place_key, site_kind, facility_raw, event)
    list(vapply(g, `[[`, "", "guess"), vapply(g, `[[`, "", "basis"),
        vapply(g, `[[`, "", "withheld"))
}]
ev[!is.na(id_by_name), c("id_by_place", "guess_basis", "guess_withheld") :=
    NA_character_]

place_exists <- setdiff(unique(facilities$place_key), "")

ev[, facility_id := fifelse(!is.na(id_by_name), id_by_name, NA_character_)]
ev[, facility_id_guess := fifelse(is.na(id_by_name) & !is.na(id_by_place),
    id_by_place, NA_character_)]
ev[, match_kind := fcase(
    !is.na(id_by_name), "id",
    !is.na(id_by_place), "place_kind",
    place_key %in% place_exists, "place_only",
    default = "unmatched")]

out <- ev[, .(source, doc_id, report_date, publisher, licence, url,
    facility_raw, site_kind, name_status, place_raw, health_zone, province,
    event, beds, status_note, evidence_quote, confidence,
    facility_id, facility_id_guess, match_kind, guess_basis, guess_withheld)]
setorder(out, report_date, facility_raw)
#' One file a source. The AFRO reports and the DONs corroborate different
#' things and are worth reading apart.
fwrite(out, sub("\\.csv$", paste0("_", SOURCE, ".csv"), corroboration_path()))

# ----------------------------------------------------------------- report

message("\nHow each external mention met the register:")
print(out[, .N, keyby = match_kind])

matched <- out[match_kind == "id"]
if (nrow(matched)) {
    message("\nFacilities a second publisher also names:")
    print(matched[, .(site_kind = site_kind[1], docs = uniqueN(doc_id)),
        by = facility_id])
}

guessed <- out[match_kind == "place_kind"]
if (nrow(guessed)) {
    message("\nMatched on place and kind only, not confirmation:")
    print(guessed[, .(site_kind = site_kind[1], docs = uniqueN(doc_id)),
        by = .(facility_raw, facility_id_guess, guess_basis)])
}

if (out[match_kind == "unmatched", .N]) {
    message("\nNamed by ", SOURCE, " and absent from the register:")
    print(unique(out[match_kind == "unmatched",
        .(facility_raw, place_raw, site_kind, doc_id)]))
}

message("\nWritten: ", sub("\\.csv$", paste0("_", SOURCE, ".csv"), corroboration_path()))

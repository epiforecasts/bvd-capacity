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
#'   `place_kind`  same place key and same site_kind as exactly one facility
#'   `place_only`  the place is in the register but the kind is not there
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

by_place <- facilities[, .(n = .N, facility_id = facility_id[which.max(n_events)]),
    by = .(place_key, site_kind)]
ev <- merge(ev, by_place[n == 1L, .(place_key, site_kind,
    id_by_place = facility_id)], by = c("place_key", "site_kind"), all.x = TRUE)

place_exists <- unique(facilities$place_key)

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
    facility_id, facility_id_guess, match_kind)]
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
        by = .(facility_raw, facility_id_guess)])
}

if (out[match_kind == "unmatched", .N]) {
    message("\nNamed by ", SOURCE, " and absent from the register:")
    print(unique(out[match_kind == "unmatched",
        .(facility_raw, place_raw, site_kind, doc_id)]))
}

message("\nWritten: ", sub("\\.csv$", paste0("_", SOURCE, ".csv"), corroboration_path()))

#!/usr/bin/env Rscript
# ai-written
#'
#' Verify every quote, resolve names to facilities, derive the two datasets.
#'
#' The gate comes first and is not negotiable: a quote must still be a span of
#' the report as `render_report()` renders it today, and must still contain the
#' facility as the model wrote it. A failure is a rendering bug, a gap in
#' `normalise_for_match()` or a model that did not copy, and all three are
#' reasons to drop the event rather than to reason around it. Rejections go to
#' checks/rejected_events.csv with a reason, and R/03_checks.R fails while any
#' remain. Do not add an exemption file here.
#'
#' Two keys, not one. `name_key` identifies a facility, so `HGR Bunia` and
#' `CTE de l'HGR Bunia` stay apart. `place_key` identifies the locality both
#' sit at, and is what later passes over this corpus (laboratories,
#' vaccination, burials) can key on without building a second name vocabulary.
#'
#' Judgement is flagged, never applied. Rows in the registry marked
#' `reviewed = TRUE` are human decisions and win; everything else is a guess
#' this script made and may remake.
#'
#' Usage:
#'     Rscript R/02_resolve.R [--cache=DIR] [--out=DIR]

suppressMessages({
    library(data.table)
})
source(here::here("R", "lib", "paths.R"))
source(here::here("R", "lib", "corpus.R"))
source(here::here("R", "lib", "places.R"))

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag) {
    hit <- grep(paste0("^", flag, "="), args, value = TRUE)
    if (length(hit)) sub(paste0("^", flag, "="), "", hit[1]) else NULL
}
CACHE <- arg_value("--cache") %||% cache_dir()

#' `--out` sends every output somewhere other than the repository's own, so a
#' run over part of the cache cannot leave rows in the registry that a person
#' would then have to review and delete.
OUT <- arg_value("--out")
redirect <- function(f, name) if (is.null(OUT)) f() else file.path(OUT, name)
out_registry <- function() redirect(registry_path, "facility_aliases.csv")
out_events <- function() redirect(events_path, "facility_events.csv")
out_facilities <- function() redirect(facilities_path, "facilities.csv")
out_rejected <- function() redirect(rejected_path, "rejected_events.csv")
out_flags <- function() redirect(flags_path, "facility_flags.csv")
if (!is.null(OUT)) dir.create(OUT, recursive = TRUE, showWarnings = FALSE)

EVENTS <- c("planned", "under_construction", "opened", "operating", "expanded",
    "strained", "incident", "closed", "mention_only")

#' Events that show the facility in service, as against announced or planned.
IN_SERVICE <- c("operating", "expanded", "strained", "incident")

#' What `facility_id` starts with, by kind of site.
ID_PREFIX <- c(treatment_centre = "cte", transit_centre = "ct",
    isolation_centre = "ci", hospital_isolation = "hosp", other = "site")

#' Accents folded to ASCII, with the marks macOS leaves behind removed.
#'
#' iconv on this platform turns `é` into `'e` rather than `e`, so the stray
#' quote has to come out or every accented name keys differently from its
#' unaccented spelling.
#'
#' `sub` is not optional. Without it iconv returns NA for the whole string as
#' soon as one character has no transliteration, and the situation reports are
#' full of them: the bullets the INSP lists activities with, the em dash, the
#' superscript in `6ᵉ transversale`. A quote carrying any of those folded to
#' the empty string and matched nothing.
fold_accents <- function(x) {
    x <- iconv(x, "UTF-8", "ASCII//TRANSLIT", sub = " ")
    x[is.na(x)] <- ""
    gsub("[`'^~\"]", "", x, perl = TRUE)
}

#' Prefixes naming a kind of Ebola facility, in both their short and long
#' forms. Removed from `name_key` because `CTE de Nizi` and `CTE Nizi` are one
#' facility, and from `place_key` along with the hospital prefixes below.
#' `chantier d'isolement` is here because it names the same facility as
#' `unite d'isolement` at an earlier stage, and keeping them apart would give
#' Kabondo two records, one of which never opens.
TYPE_WORDS <- paste0(
    "centres? de traitement( ebola)?|centres? de transit|centres? d ?isolement|",
    "(unites?|chantiers?|blocs?|batiments?|pavillons?|tentes?|sites?|salles?)",
    " d ?isolement|",
    "\\bctes?\\b|\\bctcs?\\b|\\bctrs?\\b|\\bcts?\\b|\\bcis?\\b")

#' Prefixes naming a kind of health structure. These stay in `name_key`,
#' because HGR Bunia and CTE de l'HGR Bunia are two facilities, and come out of
#' `place_key`, because both stand at Bunia.
HOSPITAL_WORDS <- paste0(
    "hopital general de reference|hopital general|hopital|clinique universitaire|",
    "clinique|centre medical evangelique|centre medical|centre de sante|",
    "centre hospitalier|poste de sante|\\bhgrs?\\b|\\bchs?\\b|\\bcmes?\\b|",
    "\\bcms?\\b|\\bcss?\\b|\\bhcs?\\b|\\bistm\\b|\\bess\\b|\\bhg\\b")

#' Words that describe the state of a structure rather than name it. `CTE
#' norme CME Rwampara`, `CTE en construction a Katwa` and `futur centre de
#' traitement de Musienene` are the same three facilities as their plain
#' spellings, and keeping the qualifier gives each one a second record that
#' opens once and is never heard of again. `zone de sante` goes with them: it
#' places a facility, it does not name it.
QUALIFIERS <- paste0(
    "zones? de sante|\\ben construction\\b|\\bconstruction\\b|\\bfuture?\\b|",
    "\\bnormee?s?\\b|\\bprovisoires?\\b|\\btemporaires?\\b")

#' Words that only join a name to its place.
JOINERS <- "\\b(de la|de|du|des|d|le|la|les|l|a|au|aux|en|the)\\b"

#' An apostrophe separates two words and has to become a space before
#' `fold_accents()` deletes it. Deleting it first welds the elided article on:
#' `l'HGR Bunia` keys as `lhgr bunia`, `CTE d'Isiro` as `ctedisiro`, and each
#' one splits off from its own unelided spelling.
base_key <- function(x) {
    x <- gsub("['’‘`´]", " ", x, perl = TRUE)
    x <- tolower(fold_accents(x))
    x <- gsub("[^a-z0-9]+", " ", x, perl = TRUE)
    trimws(gsub("\\s+", " ", x, perl = TRUE))
}

#' Identifies the facility: the type of centre comes off, the host hospital
#' stays on.
name_key_of <- function(x) {
    k <- base_key(x)
    k <- gsub(QUALIFIERS, " ", k, perl = TRUE)
    k <- gsub(TYPE_WORDS, " ", k, perl = TRUE)
    k <- gsub(JOINERS, " ", k, perl = TRUE)
    trimws(gsub("\\s+", " ", k, perl = TRUE))
}

#' Identifies the locality: everything describing a kind of building comes off.
place_key_of <- function(place_raw, facility_raw) {
    x <- ifelse(nzchar(trimws(place_raw)), place_raw, facility_raw)
    k <- base_key(x)
    k <- gsub(QUALIFIERS, " ", k, perl = TRUE)
    k <- gsub(TYPE_WORDS, " ", k, perl = TRUE)
    k <- gsub(HOSPITAL_WORDS, " ", k, perl = TRUE)
    k <- gsub(JOINERS, " ", k, perl = TRUE)
    trimws(gsub("\\s+", " ", k, perl = TRUE))
}

slug <- function(x) gsub(" ", "-", trimws(x), fixed = TRUE)

# ---------------------------------------------------------------- read cache

files <- list.files(CACHE, pattern = "\\.json$", full.names = TRUE)
if (!length(files)) {
    stop("No extractions in ", CACHE, ". Run Rscript R/01_facilities.R first.",
        call. = FALSE)
}
message("Reading ", length(files), " cached extractions.")

cached <- lapply(files, jsonlite::fromJSON, simplifyVector = FALSE)
ev <- rbindlist(lapply(cached, function(d) {
    if (!length(d$events)) return(NULL)
    cbind(sitrep = d$id, extract_key = d$extract_key, model = d$model,
        rbindlist(lapply(d$events, as.data.table), fill = TRUE))
}), fill = TRUE)
if (!nrow(ev)) stop("The cache holds no events at all.", call. = FALSE)

for (col in c("facility_raw", "facility_type_raw", "site_kind", "name_status",
    "place_raw", "health_zone", "province", "event", "event_date", "beds",
    "status_note", "evidence_quote", "confidence")) {
    if (is.null(ev[[col]])) ev[, (col) := ""]
    ev[is.na(get(col)), (col) := ""]
}

# The report date is the corpus's, never the model's.
meta <- rbindlist(lapply(unique(ev$sitrep), function(id) {
    m <- read_report(id)$meta
    data.table(sitrep = id, report_date = as.Date(m$report_date),
        build_key = m$build_key)
}))
ev <- merge(ev, meta, by = "sitrep", all.x = TRUE)

# ------------------------------------------------------------------ the gate

rejects <- list()
reject <- function(rows, reason) {
    if (!nrow(rows)) return(invisible())
    rejects[[length(rejects) + 1L]] <<- cbind(copy(rows), reason = reason)
}

#' A corpus file rebuilt since extraction invalidates its whole cache entry:
#' the quotes were taken from text that no longer exists. Re-extract rather
#' than verify against the new text.
ev[, key_ok := mapply(function(k, b) startsWith(k, paste0(b, ":")),
    extract_key, build_key)]
reject(ev[key_ok == FALSE], "corpus rebuilt since extraction; re-run 01")
ev <- ev[key_ok == TRUE]

rendered <- setNames(lapply(unique(ev$sitrep), render_report), unique(ev$sitrep))
ev[, quote_ok := mapply(function(q, s) quote_matches(q, rendered[[s]]),
    evidence_quote, sitrep)]
reject(ev[quote_ok == FALSE], "quote is not a span of the report")
ev <- ev[quote_ok == TRUE]

#' The quote has to carry the facility, or it evidences the sentence and not
#' the row. The test is on the distinguishing words of the name rather than on
#' the name as written, because French elides the head noun across a list:
#' `les CTE de Bambu, Nizi et Logo sont satures` names three centres and
#' contains the written form of only the first. Requiring the whole string
#' would reject the second and third for being correctly read. The type prefix
#' is dropped for the same reason, the list carries it once; what remains has
#' to appear in the quote, word for word. Unnamed entries are exempt: there is
#' no name to find.
#'
#' This is not the quote gate. The gate above still demands the quote be a
#' verbatim span of the report and has no exemption. This second test asks a
#' weaker question, whether the span evidences this row rather than its
#' sentence, and has to be able to say yes to a list.
ev[, name_key := name_key_of(facility_raw)]
quote_names <- function(key, quote) {
    words <- strsplit(key, " ", fixed = TRUE)[[1]]
    words <- words[nchar(words) >= 3]
    hay <- base_key(quote)
    if (!length(words)) return(nzchar(key) && grepl(key, hay, fixed = TRUE))
    # A trailing s is optional on both sides. French pluralises the head noun
    # over a list the same way it elides it: `aux cliniques Pinpester et
    # Libiki` names two clinics and writes `clinique` neither time.
    stems <- sub("s$", "", words)
    all(vapply(stems, function(w) grepl(paste0("\\b", w, "s?\\b"), hay,
        perl = TRUE), logical(1)))
}
ev[, names_ok := name_status != "named" |
    mapply(quote_names, name_key, evidence_quote)]
reject(ev[names_ok == FALSE], "quote does not name the facility")
ev <- ev[names_ok == TRUE]

reject(ev[!event %in% EVENTS], "event outside the vocabulary")
ev <- ev[event %in% EVENTS]

message("Verified ", nrow(ev), " events, rejected ",
    sum(vapply(rejects, nrow, integer(1))), ".")

# -------------------------------------------------------------------- keys

ev[, place_key := place_key_of(place_raw, facility_raw)]
ev[, beds_int := suppressWarnings(as.integer(gsub("[^0-9]", "", beds)))]
ev[, event_date := suppressWarnings(as.Date(event_date))]
ev[!site_kind %in% names(ID_PREFIX), site_kind := "other"]

# ------------------------------------------------------------- geography

#' GRID3 constrains, it does not overrule. The province a report gives is
#' kept and only respelt to GRID3's spelling, which absorbs `Bas Uele` against
#' `Bas-Uele` and `Nord-kivu` against `Nord-Kivu`. A province GRID3 does not
#' recognise stays exactly as the report wrote it, because the report is the
#' evidence and the lexicon is a reference.
ev[, province_grid3 := canonical_province(province, base_key)]
ev[nzchar(province_grid3), province := province_grid3]
ev[, province_grid3 := NULL]

#' The health zone is filled only where the place names exactly one zone
#' inside the province the report gave, and only where the report gave no
#' zone of its own.
ev[, zone_grid3 := resolve_zone(place_key, province, base_key)]
filled_zone <- ev[!nzchar(health_zone) & nzchar(zone_grid3), .N]
ev[!nzchar(health_zone) & nzchar(zone_grid3), health_zone := zone_grid3]
filled_prov <- ev[!nzchar(province) & nzchar(zone_grid3) &
    nzchar(zone_province(zone_grid3, base_key)), .N]
ev[!nzchar(province) & nzchar(zone_grid3),
    province := zone_province(zone_grid3, base_key)]
ev[, zone_grid3 := NULL]

#' A report that names its health zone but not its province gets the
#' province GRID3 puts that zone in, where no other province has a zone of
#' that name. The zone is matched folded, so `NIA-NIA` finds `Nia-Nia`.
g3_zones <- unique(grid3_places(base_key)$health_zone)
ev[, zone_named := g3_zones[match(base_key(health_zone), base_key(g3_zones))]]
ev[, zone_prov := ""]
ev[!nzchar(province) & !is.na(zone_named),
    zone_prov := zone_province(zone_named, base_key)]
filled_prov <- filled_prov + ev[nzchar(zone_prov), .N]
ev[nzchar(zone_prov), province := zone_prov]
ev[, c("zone_named", "zone_prov") := NULL]

if (filled_zone || filled_prov) {
    message("GRID3 filled ", filled_zone, " missing health zones and ",
        filled_prov, " missing provinces.")
}

#' Only a named facility can be resolved. An unnamed or ambiguous entry keeps
#' its place and its quote and stays in the events table, where a person can
#' attach it later; it never reaches facilities.csv.
ev[, resolvable := name_status == "named" & nzchar(name_key)]

#' `other` means "this report did not say what kind of place it is", not a
#' kind of its own. A hospital decontaminated in one report and holding
#' patients in the next would otherwise become two facilities, one of them
#' permanently unopened, because `facility_id` starts with the site kind.
#'
#' So where a name is seen as `other` and as exactly one real kind, the real
#' kind wins everywhere. Where it is seen as two real kinds, both stay: a
#' transit centre and a treatment centre can share a name and a town, and
#' choosing between them is a judgement, flagged below rather than made here.
kinds <- unique(ev[resolvable == TRUE & site_kind != "other", .(name_key, site_kind)])
single <- kinds[, .(n = .N), by = name_key][n == 1L, .(name_key)]
promote <- merge(kinds, single, by = "name_key")
setnames(promote, "site_kind", "real_kind")
ev <- merge(ev, unique(promote), by = "name_key", all.x = TRUE, sort = FALSE)
promoted <- ev[, sum(site_kind == "other" & !is.na(real_kind))]
ev[site_kind == "other" & !is.na(real_kind), site_kind := real_kind]
ev[, real_kind := NULL]
if (promoted) {
    message("Promoted ", promoted,
        " activity-only mentions onto the facility they name.")
}

# ---------------------------------------------------------------- registry

reg_cols <- c("facility_raw", "name_key", "place_key", "site_kind",
    "facility_id", "reviewed", "note")
registry <- if (file.exists(out_registry())) {
    fread(out_registry(), colClasses = "character")
} else {
    setNames(data.table(matrix("", 0, length(reg_cols))), reg_cols)
}
for (col in reg_cols) if (is.null(registry[[col]])) registry[, (col) := ""]
registry[, reviewed := toupper(trimws(reviewed)) %in% c("TRUE", "YES", "1")]

seen <- unique(ev[resolvable == TRUE, .(facility_raw, name_key, place_key, site_kind)])
# One row a spelling. Where a spelling appears with two kinds of site, the
# commonest wins here and the disagreement is flagged below.
modal <- ev[resolvable == TRUE, .N, by = .(facility_raw, site_kind)][order(-N)]
seen <- merge(seen[, .(facility_raw, name_key, place_key)],
    unique(modal, by = "facility_raw")[, .(facility_raw, site_kind)],
    by = "facility_raw")

fresh <- seen[!facility_raw %in% registry$facility_raw]
if (nrow(fresh)) {
    fresh[, facility_id := paste0(ID_PREFIX[site_kind], "-", slug(name_key))]
    fresh[, reviewed := FALSE]
    fresh[, note := paste0("added automatically ", Sys.Date())]
    registry <- rbind(registry, fresh[, ..reg_cols], fill = TRUE)
    message("Registry: ", nrow(fresh), " new spellings appended for review.")
}

#' A reviewed row is a decision, so its id is never recomputed. An unreviewed
#' one is only ever this script's own guess and is refreshed, which is what
#' lets a correction to the keys take effect without hand editing.
registry[reviewed == FALSE, `:=`(
    name_key = name_key_of(facility_raw),
    facility_id = fifelse(nzchar(facility_id), facility_id,
        paste0(ID_PREFIX[site_kind], "-", slug(name_key_of(facility_raw)))))]

registry <- unique(registry, by = "facility_raw")
fwrite(registry[order(facility_id, facility_raw)], out_registry())

ev <- merge(ev, registry[, .(facility_raw, facility_id,
    reg_kind = site_kind)], by = "facility_raw", all.x = TRUE)
ev[is.na(facility_id) | resolvable == FALSE, facility_id := ""]

#' `facility_id` starts with the kind of site, so the registry's kind is the
#' one the id asserts and the event's own has to agree with it. Letting the
#' event keep a kind the id contradicts puts `transit_centre` rows under a
#' `cte-` id, and then every count by kind depends on which table is read.
ev[nzchar(facility_id) & !is.na(reg_kind) & nzchar(reg_kind),
    site_kind := reg_kind]
ev[, reg_kind := NULL]

# ------------------------------------------------------------------- flags

flags <- list()

#' `group` names the reason a set of facilities was put together, so a later
#' step can reconstruct the clusters rather than only know that each member
#' is flagged. Without it `possible_same_site` is one undifferentiated pile
#' and a person reviewing it cannot see which rows are a decision together.
add_flag <- function(ids, flag, group) {
    ids <- unique(ids)
    if (length(ids) < 2L) return(invisible())
    flags[[length(flags) + 1L]] <<- data.table(facility_id = ids,
        flag = flag, group = paste0(flag, ":", group))
}

fac <- unique(ev[nzchar(facility_id), .(facility_id, name_key, place_key, site_kind)])

#' One name, two kinds of site. A transit centre and a treatment centre can
#' share a name and a town, and choosing between them is a judgement.
same_name <- fac[, .(kinds = uniqueN(site_kind)), by = name_key][kinds > 1]
for (k in same_name$name_key) {
    add_flag(fac[name_key == k, facility_id], "possible_same_site", k)
}

#' INSP writes Mongbwalu, Mungbwalu and Mongwalu. Near neighbours are put
#' side by side for a person to judge; nothing is merged automatically.
#'
#' One edit is a typo. Two edits is only a typo if the letters are the same
#' ones in a different order, as in Elikya and Elykia. Allowing any two edits
#' puts Beni and Bunia together, which are two towns 300km apart, and a
#' review queue that groups by transitive closure then drags the whole of
#' both into one question.
anagram <- function(a, b) {
    identical(sort(strsplit(a, "")[[1]]), sort(strsplit(b, "")[[1]]))
}
long <- unique(fac[nchar(name_key) >= 6L, .(facility_id, name_key, site_kind)])
if (nrow(long) > 1L) {
    d <- adist(long$name_key, long$name_key)
    for (i in seq_len(nrow(long))) {
        same_kind <- long$site_kind == long$site_kind[i]
        near <- which(same_kind & (d[i, ] <= 1L | (d[i, ] == 2L &
            vapply(long$name_key, anagram, logical(1), long$name_key[i]))))
        add_flag(long$facility_id[near], "possible_spelling_variant",
            long$name_key[i])
    }
}

#' A treatment centre named with its host hospital and one named without it
#' may be the same centre. `CTE de l'HGR Bunia` and `CTE de Bunia` almost
#' certainly are; `CTE de l'HGR Rwampara` and `CTE du CME Rwampara` are two
#' centres in one town, and `CTE de Rwampara` is a shorthand for one of them.
#' Dropping the host from the key would merge all three, so the host stays in
#' the key and the set is put in front of a person.
bare_key <- trimws(gsub(" +", " ",
    gsub(HOSPITAL_WORDS, " ", fac$name_key, perl = TRUE)))
host <- data.table(facility_id = fac$facility_id, bare_key,
    kind = fac$site_kind, has_host = bare_key != fac$name_key)
host_hits <- host[nzchar(bare_key),
    .(n = uniqueN(facility_id), any_host = any(has_host)),
    by = .(bare_key, kind)][n > 1L & any_host == TRUE]
for (i in seq_len(nrow(host_hits))) {
    add_flag(host[bare_key == host_hits$bare_key[i] &
        kind == host_hits$kind[i], facility_id], "possible_host_variant",
        paste(host_hits$bare_key[i], host_hits$kind[i]))
}

#' One name's words inside another's, at the same place. `isolement Madula`
#' and `Madula` are the same unit written twice, and neither the spelling rule
#' nor the host rule sees it: the keys are four edits apart and `isolement` is
#' not a hospital word. Requiring the same place_key keeps this from reaching
#' across towns, and the shorter name is usually the one the reports settle on.
words_of <- function(x) strsplit(x, " ", fixed = TRUE)
sub_pool <- fac[nzchar(place_key) & nzchar(name_key)]
for (i in seq_len(nrow(sub_pool))) {
    here <- sub_pool[place_key == sub_pool$place_key[i] &
        site_kind == sub_pool$site_kind[i] &
        facility_id != sub_pool$facility_id[i]]
    if (!nrow(here)) next
    mine <- words_of(sub_pool$name_key[i])[[1]]
    for (j in seq_len(nrow(here))) {
        theirs <- words_of(here$name_key[j])[[1]]
        if (all(mine %in% theirs) || all(theirs %in% mine)) {
            add_flag(c(sub_pool$facility_id[i], here$facility_id[j]),
                "possible_name_subset",
                paste(sub_pool$place_key[i], sub_pool$site_kind[i]))
        }
    }
}

#' A name that is only a host, with no place at all. `CTE CME` and `CTE ISTM`
#' name an institution the outbreak has several of: there is a CME at Bunia,
#' at Rwampara and at Nyankunde. The reports write it bare because their
#' reader knows which one, and the register cannot. Flagging it against every
#' centre of that kind whose name carries the same host asks the question
#' rather than guessing an answer, and 28 reports hang on each of these two.
HOST_ONLY <- c("cme", "istm", "ist", "hgr", "ch", "cs", "cme bunia nyakunde",
    "hopital", "clinique", "hospital", "fomulac", "cbca")
bare_only <- fac[name_key %in% HOST_ONLY]
for (i in seq_len(nrow(bare_only))) {
    token <- bare_only$name_key[i]
    kin <- fac[site_kind == bare_only$site_kind[i] &
        vapply(words_of(name_key), function(w) token %in% w, logical(1))]
    if (nrow(kin) > 1L) {
        add_flag(unique(c(bare_only$facility_id[i], kin$facility_id)),
            "possible_missing_place", paste(token, bare_only$site_kind[i]))
    }
}

#' A health zone has one reference hospital, and the reports name a centre
#' sometimes by the zone and sometimes by the hospital. GRID3 says Butembo's
#' reference hospital is called Kitatumba, so `cte-butembo` and
#' `cte-kitatumba` are one centre and no comparison of those two strings
#' could ever say so.
fac_zone <- ev[nzchar(facility_id) & nzchar(health_zone),
    .N, by = .(facility_id, health_zone)][order(-N)]
fac_zone <- unique(fac_zone, by = "facility_id")[, .(facility_id, health_zone)]
hosts <- zone_host_names(base_key)
alias <- merge(data.table(facility_id = fac$facility_id, bare_key,
    kind = fac$site_kind), fac_zone, by = "facility_id")
alias <- merge(alias, hosts, by = "health_zone", all.x = TRUE)
#' Only a name that carries no host, or carries the reference hospital, can
#' be the zone's own centre. `CTE du CME Rwampara` reduces to the same bare
#' key as `CTE de l'HGR Rwampara` and is a different host, which GRID3 lists
#' separately, so it is excluded here rather than flagged as the same site.
REF_WORDS <- "\\bhgrs?\\b|hopital general de reference|\\bhopital\\b|\\bhg\\b"
alias[, hostless := !grepl(HOSPITAL_WORDS, fac$name_key[
    match(facility_id, fac$facility_id)], perl = TRUE)]
alias[, ref_host := grepl(REF_WORDS, fac$name_key[
    match(facility_id, fac$facility_id)], perl = TRUE)]
alias[, names_the_zone := (hostless | ref_host) &
    (bare_key == base_key(health_zone) |
     (!is.na(host_key) & bare_key == host_key))]
host_alias <- alias[names_the_zone == TRUE,
    .(n = uniqueN(facility_id)), by = .(health_zone, kind)][n > 1L]
for (i in seq_len(nrow(host_alias))) {
    add_flag(alias[names_the_zone == TRUE &
        health_zone == host_alias$health_zone[i] &
        kind == host_alias$kind[i], facility_id],
        "possible_same_host", host_alias$health_zone[i])
}

#' `HGR Bunia` and `Bunia HGR` are one hospital and their keys are as far
#' apart as edit distance can put them, so word order is checked separately.
fac[, sorted_key := vapply(strsplit(name_key, " ", fixed = TRUE),
    function(w) paste(sort(w), collapse = " "), character(1))]
reordered <- fac[, .(ids = uniqueN(facility_id)), by = .(sorted_key, site_kind)]
for (i in which(reordered$ids > 1L)) {
    add_flag(fac[sorted_key == reordered$sorted_key[i] &
        site_kind == reordered$site_kind[i], facility_id],
        "possible_word_order", reordered$sorted_key[i])
}

flag_long <- if (length(flags)) rbindlist(flags) else
    data.table(facility_id = character(), flag = character(), group = character())
fwrite(unique(flag_long)[order(group, facility_id)], out_flags())

flag_dt <- if (length(flags)) {
    rbindlist(flags)[, .(flags = paste(sort(unique(flag)), collapse = ";")),
        by = facility_id]
} else data.table(facility_id = character(), flags = character())

# ------------------------------------------------------------ write events

#' Rule 1 says one entry a facility an event a report. Where a model breaks it,
#' the longest quote is kept: it is the most informative, and the alternative
#' is counting one statement twice.
ev[, dup_key := paste(sitrep, facility_id, facility_raw, event)]
ev[, quote_len := nchar(evidence_quote)]
setorder(ev, dup_key, -quote_len)
dups <- sum(duplicated(ev$dup_key))
ev <- ev[!duplicated(dup_key)]
if (dups) message("Dropped ", dups, " duplicate events (same facility, same event, same report).")

event_cols <- c("sitrep", "report_date", "facility_id", "facility_raw",
    "name_status", "site_kind", "place_key", "place_raw", "event", "event_date",
    "beds_int", "health_zone", "province", "status_note", "evidence_quote",
    "confidence", "model")
#' The model's `beds` is a string and `beds_int` is the number read out of
#' it. Renaming without dropping the string leaves two columns called `beds`,
#' and everything downstream silently reads the first: `!is.na()` is true of
#' every empty string, so the latest bed count became whatever the last row
#' held, which was usually nothing.
ev[, beds := NULL]
setnames(ev, "beds_int", "beds")
event_cols[event_cols == "beds_int"] <- "beds"
setorder(ev, report_date, facility_id, event)
fwrite(ev[, ..event_cols], out_events())

if (length(rejects)) {
    rej <- rbindlist(rejects, fill = TRUE)
    fwrite(rej, out_rejected())
    message("Rejected events written to ", out_rejected())
} else if (file.exists(out_rejected())) {
    file.remove(out_rejected())
}

# -------------------------------------------------------- derive facilities

published <- sort(unique(as.integer(sub("_v.*", "", corpus_ids()))))
commonest <- function(x) {
    x <- x[nzchar(x)]
    if (!length(x)) return("")
    names(sort(table(x), decreasing = TRUE))[1]
}
first_of <- function(dates, keep) {
    d <- dates[keep & !is.na(dates)]
    if (!length(d)) as.Date(NA) else min(d)
}

res <- ev[nzchar(facility_id)]
facilities <- res[, {
    num <- as.integer(sub("_v.*", "", sitrep))
    first_i <- which.min(report_date)
    real <- event != "mention_only"
    last_real <- if (any(real)) which(real)[which.max(report_date[real])] else NA_integer_
    beds_i <- which(!is.na(beds))
    opened_i <- which(event == "opened")
    .(
        facility_name = commonest(facility_raw),
        site_kind = commonest(site_kind),
        place_key = commonest(place_key),
        health_zone = commonest(health_zone),
        province = commonest(province),
        date_first_mentioned = min(report_date),
        sitrep_first_mentioned = sitrep[first_i],
        # The sitrep before the first mention was never published, so the true
        # first mention may sit in a report that does not exist.
        first_mention_after_gap = !(min(num) - 1L) %in% published && min(num) > 1L,
        date_first_planned = first_of(report_date, event %in% c("planned", "under_construction")),
        date_opening_announced = first_of(report_date, event == "opened"),
        sitrep_opening_announced = if (length(opened_i)) sitrep[opened_i[which.min(report_date[opened_i])]] else NA_character_,
        # Only the reports that give an opening date have one; min() over all
        # missing values returns Inf rather than NA.
        date_opening_stated = first_of(event_date, seq_along(event) %in% opened_i),
        date_first_in_service = first_of(report_date, event %in% IN_SERVICE),
        status_latest = if (is.na(last_real)) "mention_only" else event[last_real],
        status_latest_date = if (is.na(last_real)) as.Date(NA) else report_date[last_real],
        beds_latest = if (length(beds_i)) beds[beds_i[which.max(report_date[beds_i])]] else NA_integer_,
        beds_latest_date = if (length(beds_i)) max(report_date[beds_i]) else as.Date(NA),
        date_last_mentioned = max(report_date),
        n_sitreps = uniqueN(sitrep),
        n_events = .N,
        aliases = paste(sort(unique(facility_raw)), collapse = "; ")
    )
}, by = facility_id]

facilities <- merge(facilities, flag_dt, by = "facility_id", all.x = TRUE)
facilities[is.na(flags), flags := ""]
setorder(facilities, site_kind, facility_id)
fwrite(facilities, out_facilities())

message("\nFacilities: ", nrow(facilities), " from ", nrow(res),
    " resolved events, plus ", nrow(ev) - nrow(res), " unresolved.")
print(facilities[, .N, by = site_kind])
message("\nWritten: ", out_events())
message("Written: ", out_facilities())
message("Written: ", out_registry())

`#ai-written`

# Column definitions

`facility_events.csv` is what the reports say, `facilities.csv` is what
follows from it, `facility_opening.csv` turns that into an interval an opening
falls in, `facility_aliases.csv` is the name vocabulary that joins them, and
`facility_flags.csv` records which facilities a flag put together. The files
under `checks/` are the judgements none of that could settle.

An empty string and `NA` both mean the report did not say. Neither means zero.

## data/facility_events.csv

One row for each thing one report says about one facility. 1,885 rows.

| column | meaning |
|---|---|
| `sitrep` | report id, as the corpus names it (`006_v2` is the reissue of 006) |
| `report_date` | the report's own date, from the corpus, never from the model |
| `facility_id` | the facility this resolved to, empty where it did not resolve |
| `facility_raw` | the facility as the report writes it, unaltered |
| `name_status` | `named`, `unnamed` or `ambiguous`; only `named` rows resolve |
| `site_kind` | `treatment_centre`, `transit_centre`, `isolation_centre`, `hospital_isolation` or `other` |
| `place_key` | the locality, with every word naming a kind of building removed |
| `place_raw` | the place as the report writes it |
| `event` | one of the nine values below |
| `event_date` | a date the report itself gives for the event; empty in all but three rows |
| `beds` | bed count as an integer, where the report gives one |
| `health_zone` | health zone, where the report gives one |
| `province` | province, where the report gives one; spellings are not yet normalised |
| `status_note` | a short note the model took from the text |
| `evidence_quote` | the French sentence this row came from, verified character for character against the report |
| `confidence` | `high` or `low`, the model's own |
| `model` | which model read the report |

### event

The vocabulary is closed. `R/03_checks.R` fails on any other value.

| value | what the report has to say |
|---|---|
| `planned` | a facility is intended |
| `under_construction` | building or fitting out is under way |
| `opened` | an opening is announced or has just happened |
| `operating` | Ebola patients are at the facility |
| `expanded` | capacity was added |
| `strained` | saturated, over capacity, or short of something needed to run |
| `incident` | an attack, a closure threat, a breakdown, a stock-out |
| `closed` | the facility stopped taking patients |
| `mention_only` | the report names the place without saying patients were there: a decontamination, a supply delivery, a supervision visit |

`operating`, `expanded`, `strained` and `incident` are the four that show a
facility in service. `date_first_in_service` is the first report date carrying
any of them.

The distinction that does most work here is between `operating` and
`mention_only`. Work done at a building is not the same as patients being in
it, and the reports describe far more of the first than the second.

## data/facilities.csv

One row a facility. 620 rows. Every column is derived from that facility's
events and nothing else, and `R/03_checks.R` recomputes all of them by a
second implementation.

| column | meaning |
|---|---|
| `facility_id` | `<kind prefix>-<name key>`: `cte`, `ct`, `ci`, `hosp` or `site` |
| `facility_name` | the commonest spelling among its events |
| `site_kind` | the kind the id asserts, taken from the registry |
| `place_key` | the locality |
| `health_zone`, `province` | the commonest value among its events |
| `date_first_mentioned` | earliest report date of any event |
| `sitrep_first_mentioned` | the report that date came from |
| `first_mention_after_gap` | TRUE where the SitRep before the first mention was never published, so the true first mention may be unrecoverable |
| `date_first_planned` | first report date of a `planned` or `under_construction` event |
| `date_opening_announced` | first report date of an `opened` event |
| `sitrep_opening_announced` | the report that date came from |
| `date_opening_stated` | a date the report gives for the opening; empty for every facility, see README |
| `date_first_in_service` | first report date of an `operating`, `expanded`, `strained` or `incident` event |
| `status_latest` | the event of the latest report that said anything other than `mention_only` |
| `status_latest_date` | that report's date |
| `beds_latest` | the bed count from the latest report giving one |
| `beds_latest_date` | that report's date |
| `date_last_mentioned` | latest report date of any event |
| `n_sitreps` | reports mentioning it |
| `n_events` | rows in `facility_events.csv` |
| `aliases` | every spelling seen, semicolon separated |
| `flags` | open judgements, semicolon separated, see below |

## data/facility_opening.csv

One row a facility, 620 rows, written by `R/06_opening.R` from the events. The
columns up to `explanation` are the estimate; the rest are carried from
`facilities.csv` unchanged, so the file stands alone.

| column | meaning |
|---|---|
| `opened_after` | latest report showing it still building or planned, before any evidence of service; empty where none |
| `opened_by` | earliest report showing it holding patients, or announcing its opening, whichever came first; empty where none |
| `opened_midpoint` | midway between the two bounds, only where both exist |
| `interval_days` | days between the bounds |
| `basis` | which evidence bounds it, one of the five below |
| `censoring` | how to read the bounds in an analysis |
| `explanation` | the same, as one sentence naming the dates |
| `first_service` | earliest `operating`, `expanded`, `strained` or `incident` event |
| `announced` | earliest `opened` event |
| `last_not_open` | same as `opened_after`, kept under its own name |

| `basis` | facilities | what it means |
|---|---|---|
| `bounded both sides` | 17 | reported building, then reported in service |
| `in service, no earlier bound` | 190 | in service from its first mention; may have opened long before |
| `announced, no earlier bound` | 6 | opening announced, nothing showing it built |
| `building, never seen open` | 29 | building when last mentioned, never reported holding patients |
| `no opening evidence` | 378 | named only; mostly the `other` sites, which the response touched without treating anyone there |

An announcement is not treated as the opening. Where a facility has both, the
median gap between the announcement and the first report showing patients is
minus four days, so `opened_by` takes whichever came first. `mention_only` is
evidence neither way.

## checks/rejected_events.csv

What the quote gate dropped, 14 rows, written by `R/02_resolve.R`. The event
columns are as extracted, plus `quote_ok`, `names_ok` and `reason`, which is
`quote is not a span of the report` (8) or `quote does not name the facility`
(6). `R/03_checks.R` fails while the file has rows. A rejection is fixed by
rerunning that report, never by relaxing the gate.

## checks/review_queue.csv

The open naming judgements, 208 facilities in 65 clusters, written by
`R/04_review.R`. One row a facility, ordered by `rank`, the cluster's position
when clusters are sorted by `events_in_cluster`, so the first decisions are
the ones most of the data hangs on. `cluster` groups the facilities a flag put
together; `host_zone` is the health zone they share. Decide one by editing
`facility_id` in `registry/facility_aliases.csv` and setting `reviewed =
TRUE`, then rerun from `R/02_resolve.R`.

## checks/decisions/

One markdown sheet a decision, 20 of them, written by `R/08_decisions.R` from
the review queue. A sheet asks one question: are these names, all of one
`site_kind` and one place, one facility or more than one? It carries the rival
names and their aliases, what GRID3 recognises, how many reports name more
than one of them, what merging would do to the opening interval, and the
quotes that carry the bounds. `index.csv` lists all 20 with those counts.

A cluster from `review_queue.csv` becomes one sheet a `site_kind`, because a
treatment centre and a transit centre at one hospital are two facilities
however the reports spell them. Clusters with no treatment, transit or
isolation centre get no sheet: no opening date depends on them.

`Decision:` and `Reason:` at the foot of each sheet are for a person to fill
in. The decision itself is recorded in `registry/facility_aliases.csv`, which
is what the pipeline reads; the sheet is the working.

## registry/decisions.csv

The naming decisions a person has made, one row each. This is the record;
`facility_aliases.csv` is what the pipeline reads, and `R/09_apply_decisions.R`
carries one into the other.

| column | meaning |
|---|---|
| `decision_id` | `<cluster>__<kind>`, the same id as the sheet in `checks/decisions/` |
| `rank`, `cluster`, `site_kind` | which question this answers, as `checks/review_queue.csv` posed it |
| `verdict` | `same`, `apart` or `unsure` |
| `facility_ids` | the ids the decision was made over, semicolon separated |
| `merged_into` | for `same`, the id the others fold into; empty otherwise |
| `decided_by`, `decided_on` | who, and when |
| `note` | the reason, in the decider's words |
| `open_question` | a pair inside an `apart` group whose names differ only by spelling, so the group decision did not settle it |

`same` gives every name in the group one id. `apart` keeps the ids apart and
records that this was decided, not overlooked. `unsure` leaves the facilities
separate and still flagged, which is what `checks/review_queue.csv` lists.

Decisions apply in file order, so a row that assumes an earlier one sits
after it: at Nyankunde and Mongbwalu the spelling merges collapse the variants
first, and the `apart` row that follows ranges over the ids left. A `same`
needs its `merged_into` id to still exist and an `apart` needs at least two of
its ids; `R/09_apply_decisions.R` reports and skips a row that fails, rather
than applying a decision to a question the data no longer asks.

## registry/facility_aliases.csv

One row a spelling. 795 rows. The only file meant to be edited by hand.

| column | meaning |
|---|---|
| `facility_raw` | the spelling, as it appears in a report |
| `name_key` | what identifies the facility: the kind of centre stripped out, the host hospital kept in |
| `place_key` | what identifies the locality: every word naming a kind of building stripped out |
| `site_kind` | the kind of site this spelling is taken to be |
| `facility_id` | the facility it resolves to |
| `reviewed` | TRUE where a person decided this row |
| `note` | free text |

`reviewed` is the whole point of the file. A row with `reviewed = FALSE` is a
guess `R/02_resolve.R` made and will remake, so a correction to the keys takes
effect without hand editing. A row with `reviewed = TRUE` is a decision and is
never recomputed. To merge two facilities, set both rows to the same
`facility_id` and mark them reviewed.

## data/facility_flags.csv

One row a facility a flag. 369 rows. `group` names the set a flag put
together, so `R/04_review.R` can reconstruct the clusters.

| flag | what it means |
|---|---|
| `possible_same_site` | one name, two kinds of site; a transit centre and a treatment centre can share a town |
| `possible_spelling_variant` | two names within an edit distance of two, same kind of site: Mongbwalu, Mungbwalu, Mongwalu |
| `possible_host_variant` | one name carries a host hospital and another does not: `CTE de l'HGR Bunia` against `CTE de Bunia` |
| `possible_word_order` | the same words in a different order: `hosp-hgr-bunia` against `hosp-bunia-hgr` |
| `possible_same_host` | GRID3 says these name the same health zone's reference hospital, whether by the zone (`cte-butembo`) or by the hospital's own name (`cte-kitatumba`) |

Nothing flagged is ever merged automatically. A flag says a person should
look, and `R/04_review.R` says in what order.

## data/organisations.csv

Who the reports name alongside a facility, one row an organisation, written
by `R/07_organisations.R`. A keyword scan over the corpus with no model call.

| column | meaning |
|---|---|
| `organisation` | the name as this script groups it; MSF covers MSF, MSF France and MSF Hollande |
| `type` | international NGO, UN agency, DRC government, Congolese hospital or institute, local contractor |
| `role_in_reports` | what the reports attribute to it, read from the quotes |
| `facility_sentences` | sentences naming both it and a facility |
| `reports` | how many reports those fall in |
| `first_sitrep`, `last_sitrep` | the range |
| `example_quote` | a verbatim sentence, a literal slice of the corpus |
| `corpus_md`, `source_pdf` | paths to that report inside a bvd-sitreps checkout |

A row says an organisation was named in a sentence that also mentions a
facility. That covers building a treatment centre and equally covers
delivering soap to one, so `facility_sentences` is an upper bound on
providing a facility. Read the quote before citing a row.

`type` separates two different things. An international NGO or UN agency is a
partner with its own records to ask for. A Congolese hospital or institute,
CME, ISTM, FOMULAC, is the building itself, and appears because the reports
name a facility by its host.

## data/external_corroboration_<source>.csv

One row for each facility mention in a document INSP did not write, after the
quote gate. One file a source: `who_don` for WHO's Disease Outbreak News,
`who_afro` for the AFRO weekly situation reports. Written by
`R/22_external_match.R` from the corpus bvd-sitreps publishes.

| column | meaning |
|---|---|
| `source`, `doc_id`, `publisher`, `licence`, `url` | where the mention came from and under what terms |
| `report_date` | the document's own date |
| `facility_raw` … `confidence` | as in `facility_events.csv`, read by the same schema |
| `facility_id` | the register facility the external name folds to; filled only on `id` rows |
| `facility_id_guess` | on `place_kind` rows only, the one register facility with the same place and kind. A guess, not a second publisher naming it |
| `match_kind` | `id` (the name folds to a register id), `place_kind` (same place and kind as exactly one facility), `place_only` (the place is known, the kind is not there), `unmatched` |

`unmatched` is the column to read. It is either a facility the situation
reports never named, or a name for one they named differently. The WHO
documents' unmatched rows are mostly facilities outside the Democratic
Republic of the Congo: an isolation unit in Berlin, a university hospital in
Frankfurt, the Mulago Isolation Treatment Unit in Kampala.

## data/capacity_indicators.csv

One row a capacity figure, 193 of them, written by `R/30_capacity.R` from the
WHO AFRO weekly reports. The vocabulary is fixed in the script so that a later
pass over the INSP bed tables writes into this same table with a different
`source`.

| column | meaning |
|---|---|
| `source`, `doc_id`, `publisher`, `licence`, `url` | which document, and under what terms |
| `report_date` | the document's own date |
| `as_of_date` | the date the figure describes, which is the report's date unless the document gives another |
| `indicator` | one of `beds_capacity`, `beds_occupied`, `bed_occupancy_pct`, `patients_in_isolation`, `admissions`, `discharges_recovered`, `deaths_in_facility`, `escapes`, `facilities_operational`, `laboratories_testing` |
| `level` | `national`, `province`, `health_zone` or `facility` |
| `country`, `place`, `place_raw` | where it applies; `place` folds `Ituri Province` and `North Kivu` onto the canonical six, `place_raw` keeps what the document wrote |
| `value`, `unit`, `period` | the figure, what it counts, and whether it is a stock or a flow |
| `ambiguous_key` | TRUE where the document states more than one figure for the same indicator, place and date |
| `confidence`, `evidence_quote` | the model's own hedge, and the sentence the figure came from |

`ambiguous_key` marks 48 of the 193, and the cause is usually definitional
rather than a misreading. SitRep 18 gives 1,390 "active beds" in its
case-management text and 1,366 "Bed Capacity" in its headline block; both are
in the document, and choosing between them is a judgement about what a bed is.
Anything building a series has to decide, which is why the rows are marked
rather than silently thinned.

## checks/register_suggestions.csv

What the other registers say about an open naming decision, written by
`R/23_registers_suggest.R` and printed on the sheet. `source` is `grid3` or
`osm`, `finding` is one of `reference_hospital`, `area_in_zone`,
`both_registered`, `host_registered_at` or `named_in_osm`, and `leans` says
which way it points. None of it decides anything.

## data/reference/osm_places.csv

1,502 named facilities tagged `hospital`, `clinic` or `doctors` in the six
outbreak provinces, from OpenStreetMap through the Overpass API. Columns:
`province`, `osm_type`, `osm_id`, `name`, `amenity`, `healthcare`, `operator`,
`lat`, `lon`. Rebuilt by `tools/osm-places.R`. © OpenStreetMap contributors,
ODbL 1.0.

## data/reference/grid3_places.csv

GRID3 COD Health Facilities v8.0, trimmed to the six outbreak provinces and to
the columns a name lookup needs. 8,667 rows: `province`, `health_zone`,
`health_area`, `locality`, `facility_type`, `facility_name`, `grid3id`. Built
by `tools/grid3-lexicon.R`, committed, and read only by `R/lib/places.R`.

## checks/place_check.csv

One row a facility, written by `R/05_places.R`.
`confirmed_in_zone` is TRUE where GRID3 lists that name inside that health
zone, which is the strong form; `name_known` allows a match anywhere in the
six provinces; `place_known` says only that the locality exists. `grid3_type`
is what GRID3 calls it. A facility unknown to GRID3 is not necessarily wrong,
since the response built structures no national register lists, but the list
is mostly misspellings: `cte-elykia` is unknown where `cte-elikya` is
confirmed.

## data/indicators.csv and data/indicator_appearances.csv

A survey of every label the situation report tables use, built from the tables
alone with no model call. Separate from the facility pipeline.

`indicator_appearances.csv` is one row a label an appearance: `sitrep`,
`report_date`, `table_n`, `caption`, `label_raw`, `kind`, `label_key`, `role`.

`indicators.csv` is one row a distinct label, with `n_appearances`,
`n_reports`, `first_sitrep`, `last_sitrep`, `first_date`, `last_date`,
`has_series` (in five or more reports), `still_reported`, a `cluster` of
near-identical labels, and `example_caption` and `example_raw` showing where
it appears. `role` separates an indicator from a dimension (a province, a
health zone) and from free text. `topic_suggested` is this script's guess;
`topic` is the column for a person to fill.

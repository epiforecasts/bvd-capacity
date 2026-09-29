`#ai-written`

# Column definitions

`facility_events.csv` is what the reports say, `facilities.csv` is what
follows from it, `facility_opening.csv` turns that into an interval an opening
falls in, `facility_aliases.csv` is the name vocabulary that joins them, and
`facility_flags.csv` records which facilities a flag put together. The files
under `checks/` are the judgements none of that could settle.

An empty string and `NA` both mean the report did not say. Neither means zero.

## data/
### data/facility_events.csv

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

#### event

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

### data/facilities.csv

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

### data/facility_opening.csv

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

### data/facility_flags.csv

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

### data/organisations.csv

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

### data/external_corroboration_<source>.csv

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
| `facility_id_guess` | on `place_kind` rows only, the guessed facility of the same place and kind. A guess, not a second publisher naming it |
| `match_kind` | `id` (the name folds to a register id), `place_kind` (a facility of the same place and kind is guessed), `place_only` (the place is in the register but no facility is guessed), `unmatched` |
| `guess_basis` | how a `place_kind` guess was made: `only_candidate` (one facility of that kind at that place), `name_word` (the name carries a host word, CME/HGR/ISTM, exactly one candidate shares), `most_events` (otherwise, the candidate the INSP reports mention most), tried in that order |
| `guess_withheld` | why no facility is guessed, on `place_only` rows and, for `no_place`, `unmatched` ones: `no_place` (no place to match on), `several_places` (one mention covering sites in more than one place), `pre_opening` (planned or under construction), `host_unmatched` (the name carries a host word no candidate shares), `tie` (the busiest candidates have equal events) |

`unmatched` is the column to read. It is either a facility the situation
reports never named, or a name for one they named differently. The WHO
documents' unmatched rows are mostly facilities outside the Democratic
Republic of the Congo: an isolation unit in Berlin, a university hospital in
Frankfurt, the Mulago Isolation Treatment Unit in Kampala.

A guess is withheld for `pre_opening` because the register's busiest centre
at a place is the one least likely to be the one still being built.

### data/indicators.csv and data/indicator_appearances.csv

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

### data/capacity_indicators.csv

One row a capacity figure, 2,280 of them, from two sources under one fixed
vocabulary: 213 `who_afro` rows written by `R/30_capacity.R` from the WHO
AFRO weekly reports, one model call a document, and 2,067 `insp` rows
written by `R/32_capacity_insp.R` from the INSP bed tables, no model call,
by the label mapping in `registry/insp_capacity_labels.csv`.

| column | meaning |
|---|---|
| `source`, `doc_id`, `publisher`, `licence`, `url` | which document, and under what terms |
| `report_date` | the document's own date |
| `as_of_date` | the date the figure describes, which is the report's date unless the document gives another |
| `indicator` | one of `beds_capacity`, `beds_occupied`, `bed_occupancy_pct`, `patients_in_isolation`, `admissions`, `discharges_recovered`, `deaths_in_facility`, `escapes`, `facilities_operational`, `laboratories_testing` |
| `level` | `national`, `province`, `health_zone` or `facility` |
| `country`, `place`, `place_raw` | where it applies; `place` folds `Ituri Province` and `North Kivu` onto the canonical six, `place_raw` keeps what the document wrote |
| `value`, `unit`, `period` | the figure, what it counts, and whether it is a stock or a flow |
| `ambiguous_key` | TRUE where the document states more than one figure for the same indicator, level, country, place, period and unit, and `as_of_date` |
| `preferred` | TRUE for the figure a series should read; see below |
| `confidence`, `evidence_quote` | the model's own hedge (`who_afro`) or a flag for a value that needed coercion (`insp`, e.g. `28 lits`, `93,9%`), and the sentence or table line the figure came from |

For `source == "insp"`, `url` is the INSP table's path inside a bvd-sitreps
checkout (`data/csv/060_table_06_tableau_6_occupation_des_structures_de_s.csv`),
and `evidence_quote` is that table's header line and the data line the value
came from, joined by a newline, both copied verbatim from the CSV so that
`R/03_checks.R` can find the data line as a literal line of the file. Where
the bed count sits in the column header itself (`HGR BUNIA (12 Lits: 08 S et
03 C)`) or in an unlabelled first data row (SitReps 006, 006_v2), the quote
is the header line alone.

`fread()` cannot correctly round-trip an `evidence_quote` that mixes an
embedded newline with more than one quoted segment, which many INSP data
lines are (French comma-decimal cells like `"93,9%"` are quoted in the
source CSV): each read through `fread()` doubles the escaping further.
`read_capacity_csv()` in `R/lib/capacity_preferred.R` reads this file with
base R's `read.csv()` instead, which parses the same file correctly;
`R/31_capacity_preferred.R` and `R/03_checks.R` both use it rather than
`fread()` directly. Writing is unaffected: `fwrite()` already writes
standard, correctly escaped CSV, and the corruption was only ever in reading
it back.

`ambiguous_key` marks 27 of the 213 `who_afro` rows (none of the `insp`
rows). It used to mark 52, keyed without
`country` and `unit`: a national total for Uganda then collided with the
national total for the Democratic Republic of the Congo under one key (48
figures across afro-03 to afro-10), which is not a disagreement about one
quantity. Keying on `country` and `unit` as well, in
`R/lib/capacity_preferred.R`, dropped 12 of the 25 conflict groups the coarse
key found, with no judgement.

`preferred` marks which of the remaining conflicting rows a series should
use, written by `R/31_capacity_preferred.R` from the rule in decision
`capacity-rules` (`registry/capacity_decisions.csv`): a figure that changed
mid-sentence ("increased from A to B") reads as B; an occupancy percentage
consistent with a numerator and denominator stated in the same document
(within 0.5 percentage points) beats one that contradicts them; otherwise a
headline figure block beats a narrative sentence. SitRep 18 gives 1,390
"active beds" in its case-management text and 1,366 "Bed Capacity" in its
headline block; both stay in the table, and 1,366 is `preferred`. A row with
no conflict is `preferred`. Three of the 13 remaining conflict groups needed
a person to read the quotes rather than a mechanical rule: one is settled and
recorded as decision `capacity-afro04-2026-06-07-patients-in-isolation`, two
are left unsettled (`capacity-afro04-2026-06-07-escapes` and
`capacity-afro12-2026-08-02-facilities-operational`) because the quotes are
two different quantities or give no total to choose between; every row of
those two groups has `preferred = FALSE`. `checks/capacity_conflicts.csv`
lists every row that ever shared a key, its value, whether it is preferred,
and which rule or decision chose it. Merging the INSP rows in changed
neither the count nor the shape of the conflicts: no INSP row shares a key
with a WHO AFRO row or with another INSP row, so `ambiguous_key` still marks
the same 27 rows across 13 groups it did before.

### data/reference
#### data/reference/osm_places.csv

1,502 named facilities tagged `hospital`, `clinic` or `doctors` in the six
outbreak provinces, from OpenStreetMap through the Overpass API. Columns:
`province`, `osm_type`, `osm_id`, `name`, `amenity`, `healthcare`, `operator`,
`lat`, `lon`. Rebuilt by `tools/osm-places.R`. © OpenStreetMap contributors,
ODbL 1.0.

### data/reference/grid3_places.csv

GRID3 COD Health Facilities v8.0, trimmed to the six outbreak provinces and to
the columns a name lookup needs. 8,667 rows: `province`, `health_zone`,
`health_area`, `locality`, `facility_type`, `facility_name`, `grid3id`. Built
by `tools/grid3-lexicon.R`, committed, and read only by `R/lib/places.R`.

## checks/
### checks/register_suggestions.csv

What the other registers say about an open naming decision, written by
`R/23_registers_suggest.R` and printed on the sheet. `source` is `grid3` or
`osm`, `finding` is one of `reference_hospital`, `area_in_zone`,
`both_registered`, `host_registered_at` or `named_in_osm`, and `leans` says
which way it points. None of it decides anything.

### checks/place_check.csv

One row a facility, written by `R/05_places.R`.
`confirmed_in_zone` is TRUE where GRID3 lists that name inside that health
zone, which is the strong form; `name_known` allows a match anywhere in the
six provinces; `place_known` says only that the locality exists. `grid3_type`
is what GRID3 calls it. A facility unknown to GRID3 is not necessarily wrong,
since the response built structures no national register lists, but the list
is mostly misspellings: `cte-elykia` is unknown where `cte-elikya` is
confirmed.

### checks/rejected_events.csv

What the quote gate dropped, 14 rows, written by `R/02_resolve.R`. The event
columns are as extracted, plus `quote_ok`, `names_ok` and `reason`, which is
`quote is not a span of the report` (8) or `quote does not name the facility`
(6). `R/03_checks.R` fails while the file has rows. A rejection is fixed by
rerunning that report, never by relaxing the gate.

### checks/review_queue.csv

The open naming judgements, 208 facilities in 65 clusters, written by
`R/04_review.R`. One row a facility, ordered by `rank`, the cluster's position
when clusters are sorted by `events_in_cluster`, so the first decisions are
the ones most of the data hangs on. `cluster` groups the facilities a flag put
together; `host_zone` is the health zone they share. Decide one by editing
`facility_id` in `registry/facility_aliases.csv` and setting `reviewed =
TRUE`, then rerun from `R/02_resolve.R`.

### checks/decisions/

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

### checks/capacity_conflicts.csv

Every row of `capacity_indicators.csv` that ever shared a key with another,
written by `R/31_capacity_preferred.R`. One row a conflicting figure: its
value, whether it is `preferred`, and `rule`, which names the rule
(`rule1_change_wording`, `rule2_numerator_denominator`,
`rule3_headline_over_narrative`) or decision (`decision:<decision_id>`) that
chose it, or `unsettled` (or `unsettled:<decision_id>`) where none did.

### checks/insp_capacity_skipped.csv

Every INSP table row `R/32_capacity_insp.R` could not use, one row a
skipped cell, with `url`, `doc_id`, `row_label`, `place_raw` (the column),
`value_raw` and `reason`. Reasons: a duplicate column name from extraction,
which loses which of two similarly-named facilities a count belongs to
(SitRep 007 alone, 107 cells); a subtotal across a cluster of facilities or
a column mixing a total with an occupancy rate, neither a formal place
level (98 cells); a trailing column the extraction misaligned, whose
contents do not line up with a place (SitRep 080's `col`, 5 cells); an
unmapped label, not in `registry/insp_capacity_labels.csv`; or a value that
is not a number once `ND`, a blank cell and `-` have already been read as
not reported rather than as an error.

### checks/capacity_insp_vs_afro.csv

Where INSP and WHO AFRO both give a national figure for the same indicator,
country, unit and kind of period (both `24h`, both `point`, or both
`cumulative`) within three days of each other, written by
`R/32_capacity_insp.R`: `insp_date`, `afro_date`, `insp_value`, `afro_value`,
`diff` and `ratio`. AFRO reports weekly, so an exact date match is not
expected; a `24h` INSP figure is never compared with a `7d` or `cumulative`
AFRO figure, since the two are not disagreeing about the same quantity.
Where the earliest tables give a bed count per facility (SitReps 006,
006_v2, 013, 014), the same file also carries the sum of those facility
counts against the national total the same report gives, as `indicator`
`beds_capacity (facility sum vs national)`; none of those four reports
states a national total, so `afro_value` and `ratio` are empty for that row,
which is itself the finding: the facility columns in that period are not a
complete register the report itself totals.

### checks/compare_bos_province_care.csv

This repository's province-level INSP capacity rows against
BVDOutbreakSize's independent province-care reads (PR #969), written by
`R/33_compare_bos.R`. One row a (`sitrep`, `report_date`, `province`,
`quantity`): `ours`, `bos_scan` and `bos_read` (BVDOutbreakSize's
deterministic scan and its independent blind read of the same tables),
`agree_scan` and `agree_read` (`NA` where that read has no figure for the
cell, not only where it disagrees), and `status`: `all_agree`,
`ours_differs`, `bos_reads_differ` (BVDOutbreakSize's own two reads
disagree with each other), `only_ours` or `only_bos`. `bos_commit` carries
the BVDOutbreakSize commit the comparison ran against.

Six quantities are compared directly: `patients_in_isolation` /
`patients_isolated`, `beds_capacity` / `beds`, `bed_occupancy_pct` /
`occupancy_rate_pct` (0.5 percentage point tolerance, otherwise exact),
`admissions` (24h only; the `cumulative` reading from SitRep 064 is
dropped first) / `admissions_24h`, `discharges_recovered` / `recovered_24h`,
and `deaths_in_facility` / `deaths_incare_24h`. `beds_occupied` and
`escapes` appear as `only_ours`: BVDOutbreakSize has no equivalent, and
`beds_occupied` ("Patients présents au lit (J-1)", dated to the day before
the report) is a narrower count than `patients_in_isolation`, not the same
figure under another name. `discharges_24h` appears as `only_bos`:
BVDOutbreakSize's total across every exit category, which this repository
has no single vocabulary indicator for.


## registry/
### registry/decisions.csv

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

### registry/capacity_decisions.csv

The rule for choosing which of two capacity figures a series should read
when a document gives more than one, plus a row for each conflict group the
rule does not settle mechanically. The naming equivalent of
`registry/decisions.csv`; `R/31_capacity_preferred.R` is what
`R/09_apply_decisions.R` is there.

| column | meaning |
|---|---|
| `decision_id` | `capacity-rules` for the rule itself, otherwise one row a conflict group |
| `doc_id`, `as_of_date`, `indicator`, `level`, `country`, `place`, `period` | which figure this answers, empty on the `capacity-rules` row |
| `preferred_value` | the value to prefer; empty where the group is left unsettled |
| `rule` | `unsettled`, or free text for `capacity-rules` |
| `decided_by`, `decided_on` | who, and when |
| `note` | the reason, in the decider's words |

`capacity-rules` is `kathsherratt`'s: where a figure changed mid-sentence
("increased from A to B"), B is current; where the same document states a
numerator and denominator, an occupancy percentage consistent with them
(within 0.5 percentage points) beats one that contradicts them; otherwise a
headline figure block beats a narrative sentence; a figure with no conflict
is preferred. `R/lib/capacity_preferred.R` applies these three mechanically
wherever the quote's shape lets it, which covers 10 of the 13 remaining
conflict groups. The rest are `claude-code`'s: one settled by reading the
quotes, `preferred_value` filled in; two left `unsettled`, `preferred_value`
empty, because the quotes describe two different quantities, or give no
total to choose between.

### registry/insp_capacity_labels.csv

The closed set of row labels the INSP bed tables use, mapped by hand onto
the fixed capacity vocabulary, read by `R/32_capacity_insp.R`.

| column | meaning |
|---|---|
| `label_key` | the row label as the table prints it, exactly |
| `indicator` | one of the fixed vocabulary's ten values, or empty where the label does not map |
| `unit`, `period` | as in `capacity_indicators.csv`; empty where `indicator` is |
| `note` | the reasoning behind the mapping, or why the label was left out |

A label not in this file at all is not guessed at: the row is skipped and
logged to `checks/insp_capacity_skipped.csv` with reason `unmapped label`.
Two mappings are handled in code rather than by a row here, and are
documented as comments in `R/32_capacity_insp.R`: a bed count folded into a
facility column's header (`HGR BUNIA (12 Lits: 08 S et 03 C)`), and the
unlabelled first data row SitReps 006 and 006_v2 carry, holding a bed count
per facility column. One further label, the bare `Total admissions`, maps
by this file to period `24h`, its meaning where it is the only admissions
total in the table (SitRep 018); `R/32_capacity_insp.R` overrides that to
`cumulative` wherever the same table also carries an explicit
`Total admissions (24 h)` row, which is every table from SitRep 064, since
the bare row there is roughly seven times the size of the 24h row.

### registry/facility_aliases.csv

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

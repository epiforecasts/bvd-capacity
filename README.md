`#ai-input`

# bvd-capacity

This repository holds a dataset of when each Ebola treatment, transit and isolation facility appeared, opened and came under strain during the 2026 Bundibugyo virus disease outbreak in the Democratic Republic of the Congo, read from the INSP situation reports.

> Under active review. This dataset is being read and corrected by people
> who know these facilities, and it will change while that happens. The
> facility counts are an upper bound: names that are probably one centre are
> held apart until someone says otherwise, so the error runs towards splitting
> one site into two. Ten naming questions are open in
> [`checks/decisions/`](checks/decisions) and recorded in
> [issue #1](https://github.com/epiforecasts/bvd-capacity/issues/1), and 48 of
> the 193 capacity figures are marked `ambiguous_key` pending a decision about
> what counts as a bed. Cite a version, read the quote on any row you rely on,
> and expect ids to be merged as decisions land.

Very many thanks to INSP and all those providing public access to these reports.

- Authors are in no way affiliated with INSP, and INSP hold complete rights over the source material; see [citation](#citation) and [licence](#licence) details.
- Every row is extracted by Google Gemini, and you should assume this has **not been reviewed by a human**. Every row carries the French sentence it came from, checked character for character against the report, so please read the quote and the source report before relying on any row.
- If you spot any errors, give feedback, or wish to contribute, you are very welcome and encouraged to open an [Issue](https://github.com/epiforecasts/bvd-capacity/issues).

| | |
|---|---|
| Source | INSP situation reports, via the corpus published by [bvd-sitreps](https://github.com/epiforecasts/bvd-sitreps) |
| Reports | 116, SitReps 001 to 122, 14 May to 13 September 2026 |
| Events | 1,895 |
| Facilities | 604 |
| Read by | `gemini-3.1-pro` at low thinking, one call a report |

## The outputs

`data/facility_events.csv` is the observations: one row for each thing a
report says about a facility. A facility mentioned in forty reports has forty
or more rows, each with its own quote. This is the table to use for anything
that should respect what was known when.

`data/facilities.csv` is the register: one row a facility, with the dates
derived from its events. First mentioned, first planned, opening announced,
opening date as stated, first seen in service, latest status, latest bed
count.

`data/capacity_indicators.csv` is the system layer: how many beds the
response had and how full they were, week by week, with a fixed indicator
vocabulary and one row a figure. It exists because the INSP bed tables stop:
`patients au lit (j-1)` runs to 2 August and `taux d'occupation global` to 11
July, while the outbreak runs into late September. WHO AFRO's weekly reports
carry bed capacity and occupancy through 20 September, so the series
continues where the national tables stop.

`data/facility_opening.csv` is the opening estimate: one row a facility,
giving the interval its opening falls in, which evidence bounds each end, and
how it is censored. The reports never state an opening date, so this is
derived from reports that show a facility still building and reports that show
it holding patients.

`registry/facility_aliases.csv` is the name vocabulary: one row a spelling,
mapping it to a `facility_id`. It is the only file meant to be edited by hand.

Supporting: `data/facility_flags.csv` says which facilities each flag grouped
together. `data/organisations.csv` is who the reports name alongside a
facility, with a verbatim quote and a path to the report for each. `data/reference/grid3_places.csv` is the canonical place vocabulary,
described below. `data/indicators.csv` and `data/indicator_appearances.csv` are a
separate survey of every label the situation report tables use, built without
a model call.

`checks/` holds what the pipeline could not settle by itself, for a person to
settle: `rejected_events.csv` is what the quote gate dropped and why,
`review_queue.csv` the naming decisions ordered by the events at stake,
`place_check.csv` the register against GRID3, and `decisions/` one sheet a
decision with the quotes that settle it. They are committed, so a run
that changes a judgement shows it in the diff. `runs/` holds logs, raw model
output and the spend ledger, and is not committed.

## Coverage

| kind of site | facilities | in 3+ reports | with an in-service date |
|---|---|---|---|
| treatment centre | 70 | 48 | 61 |
| hospital isolation | 83 | 22 | 81 |
| transit centre | 36 | 12 | 32 |
| isolation centre | 21 | 6 | 8 |
| other | 394 | 39 | 13 |

Opening evidence, for the three kinds of site that hold patients:

| | bounded both sides | in service, no earlier bound | announced only | building, never seen open | nothing |
|---|---|---|---|---|---|
| treatment centre | 13 | 49 | 1 | 7 | 1 |
| transit centre | 0 | 32 | 1 | 2 | 1 |
| isolation centre | 0 | 9 | 0 | 9 | 4 |

Thirteen centres were reported building and then reported holding patients, so
their opening is bounded on both sides. For most of the rest the reports show
a centre already in service at its first mention, which fixes a date it had
opened by and nothing earlier. `data/facility_opening.csv` carries the bounds,
which evidence sets each one, and how it is censored.

`other` is a health facility the response touched without the report saying it
held Ebola patients: a decontamination, a supply delivery, a supervision
visit. Most appear once. They are kept because a later pass over the same
corpus will want them, and because deciding they are irrelevant is not the
extraction step's job.

Of 1,895 events, 1,604 resolve to a named facility. The remaining 291 are
places the report described without naming, kept with their place and their
quote so a person can attach them later, and absent from `facilities.csv`.

## The canonical place vocabulary

`data/reference/grid3_places.csv` holds GRID3 COD Health Facilities v8.0 for
the six provinces the outbreak reaches: 8,667 facilities with province, health
zone, health area, locality, name and type. Rebuild it with
`tools/grid3-lexicon.R`, which needs a BDBV2026-Data checkout and `sf`;
nothing else in the pipeline needs either.

It does three things.

It respells `province` to one of six canonical values, which removes the
`Bas Uele` and `Nord-kivu` variants the reports contain.

It fills a health zone or province the report left out, 901 zones and 332
provinces, and only where the place names exactly one zone inside the province
the report already gave. Where the report gave a province or zone, GRID3 never
overrides it. That direction is not cosmetic: names like Amani and Gloria
belong to facilities in several provinces, so an unconstrained lookup silently
moves facilities between them.

It says which health zone's reference hospital carries which name. A zone has
one, so `CTE de l'HGR Bunia` and `CTE de Bunia` are the same centre while
`CTE de l'HGR Rwampara` and `CTE du CME Rwampara` are not. It also finds
merges no comparison of strings could: the reference hospital of Butembo is
named Kitatumba, and Katana's is named FOMULAC.

Citation: Center for Integrated Earth System Information (CIESIN), Columbia
University; Ministere de la Sante Publique, Hygiene et Prevention, Democratic
Republic of the Congo; GRID3 (2025). GRID3 COD Health Facilities v8.0.
https://doi.org/10.7916/f1ft-y872. CC BY 4.0.

## Method

1. `R/lib/corpus.R` renders a report to one deterministic text, body and
   tables together. Extraction and verification use the same renderer, so a
   quote that matched at extraction still matches at verification.
2. `R/01_facilities.R` sends that text to the model with
   `assets/prompt-facilities.md` and a fixed schema, and caches the reply in
   `data/cache/` under a key made from the corpus build key, the prompt, the
   schema and the model. Any change to any of those invalidates the cache.
3. `R/02_resolve.R` verifies every quote, keys the names, assigns facility
   ids from the registry, and derives the two tables.
4. `R/03_checks.R` rebuilds the register from the events by a second
   implementation and fails if the two disagree.
5. `R/04_review.R` orders the open naming judgements by how many events
   depend on each, `R/08_decisions.R` writes a sheet for each with the quotes
   that settle it, and `R/09_apply_decisions.R` carries the answers in
   `registry/decisions.csv` back into the name vocabulary. `R/05_places.R`
   checks the register's places against GRID3.

The quote gate in step 3 has no exemption route. A quote that is not a span of
the report is dropped, whatever it says, because a model that paraphrases once
will paraphrase again and there is no way to tell from the row which it did.
Rejections are written to `checks/rejected_events.csv` and `R/03_checks.R`
fails while any remain.

## Running it

```sh
Rscript R/01_facilities.R          # model calls; --only=, --force, --cache=
Rscript R/02_resolve.R             # no model calls
Rscript R/03_checks.R              # exit 1 on any failure
Rscript R/04_review.R              # worksheet for the naming decisions
Rscript R/05_places.R              # what GRID3 does and does not recognise
Rscript R/06_opening.R             # opening dates as intervals
Rscript R/07_organisations.R       # who is named alongside a facility
Rscript R/08_decisions.R           # a sheet a naming decision, with its quotes
Rscript R/09_apply_decisions.R     # the decisions made, into the name vocabulary
```

The order matters in one place. `R/09_apply_decisions.R` edits the name
vocabulary and `R/02_resolve.R` reads it, so a decision reaches the data only
on the next resolve. After a new extraction, which appends spellings the
decisions have never seen, the sequence is resolve, apply, resolve again:

```sh
Rscript R/02_resolve.R && Rscript R/09_apply_decisions.R && Rscript R/02_resolve.R
```

Day to day, with no new extraction, `R/09_apply_decisions.R` then
`R/02_resolve.R` is enough.

`R/01_facilities.R` expects a bvd-sitreps checkout beside this one, or
`BVD_SITREPS` pointing at one. It reads that corpus by path and never opens a
PDF. Extraction takes about three hours over 116 reports and should be run
detached:

```sh
mkdir -p runs/logs
nohup caffeinate -is Rscript R/01_facilities.R \
  > runs/logs/facilities_$(date +%F-%H%M).log 2>&1 &
```

Exit 3 means the model quota stopped the run; rerunning resumes from the
cache. `data/cache/` is not committed, so steps 2 onwards run from a cache you
built: the datasets in `data/` are the committed result. Changing a decision
or the register and rerunning steps 2, 9 and 3 needs no model access.

## Other accounts of the same outbreak

INSP is not the only publisher writing about this epidemic, and a second
account is worth having for the same reason a second implementation of the
facilities table is worth having: agreement is weak evidence, disagreement is
strong. Three other sources are read here, each under its own licence, and
none of them can change a row in the register.

| source | what it is | what it settles |
|---|---|---|
| WHO Disease Outbreak News | 12 documents, May to September | little about individual facilities, but it names the sites outside the DRC that took patients from this outbreak, which the INSP reports never mention |
| WHO AFRO weekly situation reports | 19 documents | the treatment centres WHO names, and bed capacity and occupancy in its headline figures |
| GRID3 COD Health Facilities v8.0 | the national health facility register | which hospital is a health zone's reference hospital, which health areas sit inside which zone, and which names are registered facilities in their own right |
| OpenStreetMap | 1,502 named health facilities in the six provinces, via Overpass | names as written on buildings rather than as registered, so it holds facilities a ministry list does not |

The WHO documents are fetched and rendered by
[bvd-sitreps](https://github.com/epiforecasts/bvd-sitreps), not here, and read
from that corpus by path exactly as the INSP reports are. This repository
opens no PDF, no API and no website; that boundary is what keeps text
wrangling in one repository and facilities in this one.

From there they go through the same machinery as the situation reports: one
model call a document, a fixed schema, and a quote gate that drops any claim
whose sentence is not a span of the document.
`data/external_corroboration_<source>.csv` says how each external mention met
the register, and the interesting column is the one where it did not.

GRID3 and OSM answer a narrower question, asked of each open naming decision
by `R/23_registers_suggest.R` and printed on the sheet: is one name the
reference hospital of the other's zone, is one a health area inside it, are
both registered separately, and does a facility of this name exist on the map
at all. A finding is evidence on a sheet, never a decision.

[`data/LICENCE.md`](data/LICENCE.md) carries the terms for every table,
including these three. The MIT licence at the root covers this repository's
code, never its sources.

## The naming decisions

The reports write one facility several ways and write several facilities one
way, so some names cannot be resolved by code. `CTE de l'HGR Bunia` and `CTE
de Bunia` may be one centre; `CTE de l'HGR Rwampara` and `CTE du CME
Rwampara` are two centres in one town and must stay apart. Those questions
are collected, ranked by the events that depend on each, and answered by a
person.

`registry/decisions.csv` is the record: the verdict, who made it, when, and
the reason. `R/09_apply_decisions.R` carries it into the name vocabulary. A
verdict of `same` folds the names into one `facility_id`, `apart` keeps them
separate and records that this was decided rather than missed, and `unsure`
leaves the question open and the facilities flagged.

The evidence for each open question is a sheet in `checks/decisions/`: the
candidate names, what GRID3 recognises, whether any report names more than one
of them in a single sentence, what merging would do to the opening interval,
and the quotes the bounds come from.

Disagreeing with a recorded decision is welcome and is an ordinary pull
request, or a comment on the issue that documents them. The decision belongs
to whoever can read the evidence.

## Limitations

The register counts spellings, not buildings. `CTE de l'HGR Bunia` and `CTE de
Bunia` are probably one centre and are two rows until someone says otherwise;
`CTE de l'HGR Rwampara` and `CTE du CME Rwampara` are two centres in one town
and must stay apart. Twenty-seven of these are decided and recorded in
`registry/decisions.csv`; ten questions over treatment, transit and
isolation centres remain open. Treat the facility counts above as an upper
bound: the error runs one way, towards splitting one centre into two, because
a name is only ever merged by a decision someone signed.

Two known cases of it: `CTE CME` and `CTE ISTM` name an institution the
outbreak has several of, and the reports write them without a town. They are
carried as facilities of their own, and which centre each belongs to is the
question in `checks/decisions/00-names-without-a-place.md`.

A date here is the date a report said something, not the date it happened.
`date_first_in_service` is the first report showing patients at the facility,
which is at or after the true opening.

`date_opening_stated` is empty for every facility. It exists to hold a date
the report itself gives, and across 116 reports the INSP never gives one: an
opening is announced on the day it is reported (`Inauguration officielle du
CTE normé de CME Rwampara`) and the date is the report's. Three events
anywhere in the corpus carry a date of their own. Treat
`date_opening_announced`, which 18 facilities have, as the earliest date an
opening is known by, not as the opening.

Seven SitRep numbers were never published (003, 029, 043, 045, 063, 075,
076), so a facility's first mention may sit in a report that does not exist.
`first_mention_after_gap` marks the 50 facilities where this is possible.

Two events were rejected by the quote gate and are not in the data: a
saturation table SitRep 081 rewrites into a sentence of its own, and a name
SitRep 048 renders joined to the number beside it. Twelve more were rejected
on the first pass and cleared when those reports were reread. Both survivors
are recorded in `checks/rejected_acknowledged.csv` with the reason they are
expected to stay rejected.

Beds are sparse. Only 25 facilities have a bed count, because the bed table
stops appearing after SitRep 090.

## Citation

Please cite the INSP situation reports, and GRID3 for the place vocabulary.

- Institut National de Santé Publique, Democratic Republic of the Congo
  (2026). *Situation reports on the 17th Ebola virus disease epidemic.*
  <https://insp.cd/ebola-17eme-epidemie/>.
- CIESIN, Columbia University; Ministère de la Santé Publique, Hygiène et
  Prévention, DRC; GRID3 (2025). *GRID3 COD Health Facilities v8.0.* DOI:
  [10.7916/f1ft-y872](https://doi.org/10.7916/f1ft-y872). CC BY 4.0. Obtained
  through the contextual data assembled by INRB/INOHA and INSP at
  [INRB-UMIE/BDBV2026-Data](https://github.com/INRB-UMIE/BDBV2026-Data), which
  is worth crediting alongside it.

If you relied on the opening intervals or the facility identities for further
work, rather than on a figure you could read in a report yourself, you may
wish to also cite this dataset and the corpus it reads:

- Sherratt, K. (2026). *bvd-capacity: Ebola treatment and isolation facilities
  in the 2026 DRC Bundibugyo virus outbreak.*
  <https://github.com/epiforecasts/bvd-capacity>.
- Sherratt, K. (2026). *bvd-sitreps: a machine-readable corpus of the INSP
  situation reports for the 2026 DRC Bundibugyo virus outbreak.*
  <https://github.com/epiforecasts/bvd-sitreps>.

Machine-readable citation: [CITATION.cff](CITATION.cff).

For any individual statement or number, please cite the specific report it
appears in. Every row in `facility_events.csv` names its report.

## Contributing

All feedback, discussion, or contributions of any kind are very welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Licence

The code in `R/` is MIT, in [LICENSE](LICENSE). That licence does not cover
anything in `data/`; full terms, file by file, are in
[data/LICENCE.md](data/LICENCE.md).

| table | derived from | terms |
|---|---|---|
| `facilities.csv`, `facility_events.csv`, `facility_opening.csv`, `facility_flags.csv`, `organisations.csv`, `indicators.csv`, `indicator_appearances.csv` | INSP situation reports | INSP holds rights in the reports; this repository's extraction is CC BY 4.0 |
| `capacity_indicators.csv`, `external_corroboration_who_afro.csv`, `external_corroboration_who_don.csv` | WHO AFRO and WHO DON | CC BY-NC-SA 3.0 IGO: non-commercial, share-alike, WHO's `evidence_quote` text stays WHO's |
| `data/reference/grid3_places.csv` | GRID3 COD Health Facilities v8.0 | CC BY 4.0 |
| `data/reference/osm_places.csv` | OpenStreetMap | ODbL 1.0, with attribution |

Figures extracted from a source are facts and are not copyrightable; a
verbatim quote in `evidence_quote` is the publisher's own text and carries
that publisher's terms.

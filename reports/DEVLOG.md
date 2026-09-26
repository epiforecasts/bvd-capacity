# Development log for the reports

Difficulties and uncertainties met while building `index.qmd` (overview, for
people working on the response) and `methods.qmd` (data and methods, for
modellers). Newest last. Items marked open need a decision from someone who
knows the data or the sites; the rest record a choice made and why.
In-page comments tagged `UNCERTAIN:` point back to these.

## 2026-09-26

1. Uganda rows in the capacity table. `capacity_indicators.csv` holds 30
   WHO AFRO rows with `country = Uganda` (Mulago and others) and 10 with no
   country. A national series that does not filter on country mixes a Ugandan
   patient count into the DRC. Both reports keep DRC and blank-country rows.
   Open: are the 10 blank-country rows DRC? They should be given a country at
   extraction.

2. "Open by" is a lower bound, and the curve is cumulative. The sites-open
   plot counts a site from `opened_by` in `facility_opening.csv`, the first
   report showing it open or holding patients. That date is at or after the
   true opening, and most sites are left-censored (first mentioned already
   working), so the curve lags reality. Closures are not subtracted: only five
   sites are ever reported closed, and a closure date is as uncertain as an
   opening. Chosen: say both in the caption rather than draw a band, because a
   band's lower edge would be the whole outbreak for 49 of 70 treatment
   centres and carry no information.

3. `opened_by` and `first_service` disagree for some centres. For example
   `cte-cme-rwampara` has `opened_by` 31 May (an opening announcement) and
   `first_service` 15 July. The overview uses `opened_by`, which follows the
   opening-interval logic in `R/06_opening.R`. Open: whether an announced
   opening with no patients for six weeks should count as open.

4. Beds capacity date shift at 23 August. Before the capacity decision
   (issue #2) the series had 1184 on 16 August and 1308 on 30 August, with 23
   August missing, because afro-15's "increased from 1 184 to 1 308" put both
   figures on one date. Rule 1 of the decision settles this.

5. Occupancy above 100 %. WHO AFRO prints Nord-Kivu at 132 to 146 % in
   several weeks, and once the INSP tables were read (issue #3) INSP shows
   the same, up to 160 % on one day in July. Shown as printed. The reports do not say whether patients
   were on extra mattresses, counted in transit centres against treatment
   beds, or whether the denominator lagged new beds. A modeller should not
   read it as a hard ceiling breached without checking the source.

6. Lines across gaps. Weekly series have holes (7 to 42 days) where a report
   did not give a figure. Drawing a line across them implied a trend nobody
   reported, so lines break where consecutive figures are more than ten days
   apart.

7. Facility counts are an upper bound. Ten naming questions are open, and
   the Bunia cluster alone holds seven treatment-centre ids. The overview
   says so in its opening note rather than on every number.

8. Rendering in CI. The reports are R-executed Quarto pages, and the Pages
   workflow has no R. They use `freeze: auto`, so `reports/_freeze/` is
   committed and CI only assembles the site. The consequence: the published
   site changes only when someone renders locally (`Rscript R/main.R report`)
   and commits the freeze. Chosen because installing R and the tidy stack in
   CI adds several minutes a push and a second dependency set to maintain.

9. Frozen pages do not notice new data. `freeze: auto` re-executes a page
   only when its source changes, not when `data/` does, so a project render
   after a data update silently republishes old figures. Rendering a single
   file ignores the freeze, so the runner's report stage renders each page
   by name and then the project. Anyone rendering by hand needs to do the
   same.

10. Rule 2's numerator (open). For afro-12, 2 August, no beds-occupied
    figure is printed, so the capacity decision used patients in isolation
    (707 of 1,050 beds, 67.3 %) and preferred it over the headline 72.4 %.
    Patients in isolation may include people in transit centres whose beds
    are not in the 1,050. If so the headline figure is the better one, and
    rule 3 would have picked it. Worth a second look.

11. A misread figure, left unsettled by the #2 agent. afro-12's
    `facilities_operational` has 33 (treatment facilities) and 8 (sites that
    completed an IPC/WASH assessment). The 8 is not a count of operational
    facilities; it was mis-labelled at extraction. I settled it as 33 in
    `registry/capacity_decisions.csv` (decided_by claude-code).

12. "From A to B" with A at outbreak onset. The laboratories rows say
    "increasing from two laboratories at the onset". Rule 1 correctly prefers
    the current figure, but the 2 is then stored against the report's date,
    where it is wrong rather than merely superseded. It stays in the table
    with `preferred = FALSE`; a consumer ignoring `preferred` would see a
    laboratory count dropping to 2 in September.

13. The 13 September bed figure (open). Kath's rule 3 (headline box over
    narrative) picks 1,366 for afro-18, which is exactly the 6 September
    figure from the week before. The narrative's 1,390 fits a series rising
    every week. The headline box may simply not have been updated. The plot
    shows a flat week that is probably an artefact. Worth revisiting rule 3
    for this one key, or adding a check that a headline equal to the prior
    week's figure yields to a narrative that differs.

14. `fread` and multi-line quotes. The #3 agent found that
    `data.table::fread` misreads `evidence_quote` fields that hold a newline
    and several quoted segments (223 of 2,280 rows), and switched the
    pipeline to a base-R reader. Row counts and values read identically
    either way, so the reports keep `fread`; they never show a quote. Anyone
    reading quotes should use `read_capacity_csv()` in
    `R/lib/capacity_preferred.R`.

15. INSP and WHO AFRO agree too well to be independent. Stock figures agree
    at a median ratio of 1.00. That makes the splice seamless, but it means
    the overlap is not corroboration. Said in the methods page.

16. Discharges do not match across sources (median ratio 0.67). WHO AFRO's
    `discharges_recovered` is cumulative recoveries; INSP's is daily
    `Sorties Guéris`, and the comparison paired them where the period
    matched. Neither report defines the terms. Not used in either page.

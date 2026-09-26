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
   several weeks. Shown as printed. The reports do not say whether patients
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

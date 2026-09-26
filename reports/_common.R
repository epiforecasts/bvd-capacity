# ai-written
#
# Shared loading and plotting for the two reports. Reads only the committed
# tables under data/, so the reports rebuild from a clone with no model and no
# corpus.

suppressMessages({
    library(data.table)
    library(ggplot2)
})

# Quarto runs each page from reports/, and here::here() stops at the
# _quarto.yml it finds there, so the repository root is set explicitly.
ROOT <- normalizePath(if (basename(getwd()) == "reports") ".." else ".")
data_path <- function(...) file.path(ROOT, "data", ...)

events <- fread(data_path("facility_events.csv"), encoding = "UTF-8",
    colClasses = list(character = "sitrep"))
facilities <- fread(data_path("facilities.csv"), encoding = "UTF-8",
    colClasses = list(character = "sitrep_first_mentioned"))
opening <- fread(data_path("facility_opening.csv"), encoding = "UTF-8")
capacity <- fread(data_path("capacity_indicators.csv"), encoding = "UTF-8")

date_cols <- function(dt) {
    cols <- grep("^date_|_date$|^opened_|^first_service$|^announced$|^last_not_open$",
        names(dt), value = TRUE)
    for (c in cols) set(dt, j = c, value = as.IDate(dt[[c]]))
    invisible(dt)
}
date_cols(events)
date_cols(facilities)
date_cols(opening)
date_cols(capacity)

# `preferred` arrives with the capacity decision (issue #2). Until then, fall
# back to dropping every figure whose key is contested, which is what the
# series did before.
if (!"preferred" %in% names(capacity)) {
    capacity[, preferred := !ambiguous_key]
}

report_first <- min(events$report_date)
report_last <- max(events$report_date)

# The three kinds of site that hold Ebola patients. `hospital_isolation` is a
# general hospital's isolation room, and `other` is a facility the response
# touched without the report saying patients were there.
KINDS <- c(
    treatment_centre = "Treatment centre (CTE)",
    transit_centre = "Transit centre (CT)",
    isolation_centre = "Isolation centre (CI)",
    hospital_isolation = "Hospital isolation",
    other = "Other health facility"
)
PATIENT_KINDS <- c("treatment_centre", "transit_centre", "isolation_centre")

kind_label <- function(x) factor(unname(KINDS[x]), levels = unname(KINDS))

PROVINCES <- c("Ituri", "Nord-Kivu", "Sud-Kivu", "Haut-Uele", "Bas-Uele",
    "Tshopo")

INK <- "#1a1a1a"
ACCENT <- "#b03a2e"
GREY <- "#7f7f7f"
RULE <- "#d4d4d4"

# Okabe-Ito, for the few plots that need more than two series.
SOURCE_COLOURS <- c(insp = INK, who_afro = ACCENT)
SOURCE_LABELS <- c(insp = "INSP situation reports",
    who_afro = "WHO AFRO weekly reports")

theme_report <- function(base_size = 11) {
    theme_minimal(base_size = base_size, base_family = "") +
        theme(
            panel.grid.minor = element_blank(),
            panel.grid.major.x = element_blank(),
            panel.grid.major.y = element_line(colour = RULE, linewidth = 0.3),
            axis.title = element_text(colour = GREY, size = rel(0.9)),
            axis.text = element_text(colour = INK),
            strip.text = element_text(hjust = 0, face = "bold"),
            legend.position = "top",
            legend.justification = "left",
            legend.title = element_blank(),
            plot.title.position = "plot",
            plot.caption = element_text(colour = GREY, hjust = 0),
            plot.caption.position = "plot"
        )
}
theme_set(theme_report())

scale_x_outbreak <- function(...) {
    scale_x_date(date_breaks = "1 month", date_labels = "%e %b",
        expand = expansion(mult = c(0.01, 0.03)), ...)
}

fmt_n <- function(x) format(x, big.mark = ",", trim = TRUE)
fmt_date <- function(x) trimws(format(as.Date(x), "%e %B"))

# A plain HTML table, so it reads on a phone without a widget library.
html_table <- function(dt, align = NULL, caption = NULL) {
    knitr::kable(dt, format = "html", align = align, caption = caption,
        escape = TRUE, table.attr = 'class="data"') |>
        (\(x) knitr::asis_output(paste0('<div class="table-wrap">', x, "</div>")))()
}

# A line drawn across a gap of weeks implies the reports said something about
# the weeks in between. Break a series wherever consecutive figures are more
# than `max_gap` days apart.
gap_group <- function(date, max_gap = 10L) {
    o <- order(date)
    g <- cumsum(c(TRUE, diff(as.integer(date[o])) > max_gap))
    g[order(o)]
}

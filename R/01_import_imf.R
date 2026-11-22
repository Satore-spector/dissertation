# ------------------------------------------------------------------------------
# Script: 01_import_imf.R
# Purpose: Discover/pull IMF series, build the initial monthly panel, and run
#          coverage/NA checks used in the raw assignment.
# Inputs:  IMF Data API (via imf.data) as specified in series_spec.
# Outputs: data/raw/imf_vars.csv
#          outputs/tables/imf_coverage_report.csv
#          outputs/tables/imf_na_summary.csv
#          outputs/tables/imf_phl_na_rows.csv
#          data/processed/panel_wide_imf_raw.rds (intermediate for script 02)
# Depends on: R/00_config.R
# ------------------------------------------------------------------------------

source(here::here("R", "00_config.R"))

# ---- IMF dataset discovery (retained for provenance) -------------------------
# Raw assignment explored available datasets/indicators before selecting series.
df_datasets <- imf.data::list_datasets()
head(df_datasets)

indicator_names <- c("Effective Exchange rate", "Exchange Rate", "MFS")
pattern <- paste(indicator_names, collapse = "|")

id <- df_datasets |>
  dplyr::filter(
    stringr::str_detect(name, stringr::regex(pattern, ignore_case = TRUE)),
    stringr::str_detect(name, "2026", negate = FALSE)
  )

print(id)

# ---- Series selection --------------------------------------------------------
# Selected IMF indicators (raw assignment notes):
# - EER      -> REER index (CPI-based, 2010=100)
# - ER       -> bilateral exchange rate vs USD (end of period)
# - NSRF_11  -> foreign assets / FX reserves proxy
# - NSRF_31N -> net foreign assets in banking system
# - NSRF_35L -> money plus quasi money (M2)
# - NSRF_22D -> claims on private sector (private credit)
# - NSRF_14_ -> reserve/base money
series_spec <- list(
  list(
    label = "reer_cpi",
    dataflow = "EER",
    filters = list(INDICATOR = "REER_IX_RY2010_ACW_RCPI", FREQUENCY = "M")
  ),
  list(
    label = "fx_usd_eop",
    dataflow = "ER",
    filters = list(
      INDICATOR = "XDC_USD", TYPE_OF_TRANSFORMATION = "EOP_RT",
      FREQUENCY = "M"
    )
  ),
  list(
    label = "fx_reserves",
    dataflow = "MFS_NSRF",
    filters = list(INDICATOR = "NSRF_11", FREQUENCY = "M")
  ),
  list(
    label = "net_foreign_assets",
    dataflow = "MFS_NSRF",
    filters = list(INDICATOR = "NSRF_31N", FREQUENCY = "M")
  ),
  list(
    label = "m2_broad_money",
    dataflow = "MFS_NSRF",
    filters = list(INDICATOR = "NSRF_35L", FREQUENCY = "M")
  ),
  list(
    label = "private_credit",
    dataflow = "MFS_NSRF",
    filters = list(INDICATOR = "NSRF_22D", FREQUENCY = "M")
  ),
  list(
    label = "reserve_money",
    dataflow = "MFS_NSRF",
    filters = list(INDICATOR = "NSRF_14_", FREQUENCY = "M")
  )
)

# ---- Pull data ---------------------------------------------------------------
pulled <- purrr::map(series_spec, pull_dat)
names(pulled) <- purrr::map_chr(series_spec, "label")
pulled <- purrr::compact(pulled)

# ---- Coverage report ---------------------------------------------------------
# Data availability for these countries is spotty; check before trusting.
coverage_report <- purrr::map_dfr(pulled, function(d) {
  d |>
    dplyr::group_by(series, dataflow, COUNTRY) |>
    dplyr::summarise(
      first_obs = min(TIME_PERIOD),
      last_obs = max(TIME_PERIOD),
      n_obs = dplyr::n(),
      .groups = "drop"
    )
})

print(coverage_report, n = Inf)
readr::write_csv(coverage_report, file.path(PATH_TABLES, "imf_coverage_report.csv"))

# ---- Build panel -------------------------------------------------------------
panel_long <- dplyr::bind_rows(pulled) |>
  dplyr::select(COUNTRY, series, dataflow, TIME_PERIOD, OBS_VALUE)

panel_wide <- panel_long |>
  dplyr::select(COUNTRY, series, TIME_PERIOD, OBS_VALUE) |>
  tidyr::pivot_wider(names_from = series, values_from = OBS_VALUE)

# ---- NA/availability checks --------------------------------------------------
# Raw assignment used a custom summary_wide() helper by country.
check <- summary_wide(panel_wide, COUNTRIES)
print(check)

# Capture NA counts by country as a table artifact (clean console output).
na_summary <- panel_wide |>
  dplyr::group_by(COUNTRY) |>
  dplyr::summarise(dplyr::across(dplyr::everything(), ~ sum(is.na(.))), .groups = "drop")
print(na_summary, n = Inf, width = Inf)
readr::write_csv(na_summary, file.path(PATH_TABLES, "imf_na_summary.csv"))

# Raw assignment inspected Philippines missing rows after date handling in 03;
# we also save an early PHL NA snapshot here for provenance.
phl_na_rows_early <- panel_wide |>
  dplyr::filter(COUNTRY == "PHL", dplyr::if_any(dplyr::everything(), is.na))
readr::write_csv(phl_na_rows_early, file.path(PATH_TABLES, "imf_phl_na_rows.csv"))

# ---- Save raw IMF panel ------------------------------------------------------
# Original saved to data\\IMF\\IMF_VARS with no extension. Use a clear path.
panel_imf <- janitor::clean_names(panel_wide)
readr::write_csv(panel_imf, file.path(PATH_RAW, "imf_vars.csv"), na = "NA")
saveRDS(panel_wide, file.path(PATH_PROCESSED, "panel_wide_imf_raw.rds"))

message("01_import_imf.R complete: raw IMF panel saved.")

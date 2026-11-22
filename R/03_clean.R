# ------------------------------------------------------------------------------
# Script: 03_clean.R
# Purpose: Clean dates, complete monthly grid, interpolate short gaps, inspect
#          NAs, and build the model-ready dataset `rdf`.
# Inputs:  data/processed/panel_wide_with_reer.rds
# Outputs: data/processed/rdf.rds
#          outputs/tables/na_check_by_country.csv
#          outputs/tables/phl_na_rows.csv
#          outputs/tables/rdf_summary_by_country.csv
# Depends on: R/00_config.R, R/02_import_fred_reer.R
# ------------------------------------------------------------------------------

source(here::here("R", "00_config.R"))

panel_wide <- readRDS(file.path(PATH_PROCESSED, "panel_wide_with_reer.rds"))

# ---- Date handling and monthly completion ------------------------------------
panel_wide <- panel_wide |>
  dplyr::mutate(date = as.Date(paste0(
    substr(TIME_PERIOD, 1, 4), "-",
    substr(TIME_PERIOD, 7, 8), "-01"
  )))

panel_wide <- panel_wide |>
  dplyr::filter(date >= as.Date(START_DATE)) |>
  dplyr::group_by(COUNTRY) |>
  tidyr::complete(date = seq(min(date), max(date), by = "month")) |>
  dplyr::mutate(TIME_PERIOD = format(date, "%Y-M%m")) |>
  dplyr::arrange(date, .by_group = TRUE) |>
  dplyr::mutate(dplyr::across(
    c(reer_cpi, fx_usd_eop, net_foreign_assets, m2_broad_money),
    ~ zoo::na.approx(.x, na.rm = FALSE, maxgap = 3)
  )) |>
  dplyr::ungroup()

# ---- NA checks ---------------------------------------------------------------
nacheck <- panel_wide |>
  dplyr::group_by(COUNTRY) |>
  dplyr::summarise(dplyr::across(dplyr::everything(), ~ sum(is.na(.))), .groups = "drop")

print(nacheck, n = Inf, width = Inf)
readr::write_csv(nacheck, file.path(PATH_TABLES, "na_check_by_country.csv"))

natable <- panel_wide |>
  dplyr::filter(COUNTRY == "PHL", dplyr::if_any(dplyr::everything(), is.na))

print(natable, n = Inf, width = Inf)
readr::write_csv(natable, file.path(PATH_TABLES, "phl_na_rows.csv"))

# ---- Build model-ready dataset (rdf) -----------------------------------------
# Raw assignment note:
# After thorough research it's clear the only avenue for filling the gaps in
# Thailand will be to rebase from narrower Bruegel estimates. This will require
# further research since unlike BIS/FRED/OECD/IMF/World Bank data, rebasing the
# same will be hard. We will need to be more prudent in our methodology.
# Therefore Thailand is excluded from the model-ready dataset for now.
rdf <- panel_wide |>
  dplyr::filter(COUNTRY != "THA", date <= as.Date("2007-12-01")) |>
  tidyr::drop_na() |>
  dplyr::arrange(COUNTRY, date)

# Sanity check: row counts and date coverage by country.
rdf_coverage <- rdf |>
  dplyr::group_by(COUNTRY) |>
  dplyr::summarise(first_obs = min(date), last_obs = max(date), n_obs = dplyr::n(), .groups = "drop")
print(rdf_coverage)

# Save summaries for verification.
rdf_summary <- summary_wide(rdf, unique(rdf$COUNTRY))
capture.output(rdf_summary, file = file.path(PATH_TABLES, "rdf_summary_by_country.txt"))

saveRDS(rdf, file.path(PATH_PROCESSED, "rdf.rds"))

message("03_clean.R complete: rdf saved.")

# ------------------------------------------------------------------------------
# Script: 05_analysis_timeseries.R
# Purpose: Run ADF stationarity tests, VAR lag selection, and pairwise Granger
#          causality tests for pre-crisis and full-sample periods.
# Inputs:  data/processed/pw.rds
# Outputs: outputs/tables/adf_results.csv
#          outputs/tables/varselect_selection.csv
#          outputs/tables/granger_all.csv
# Depends on: R/00_config.R, R/04_features.R
# ------------------------------------------------------------------------------

source(here::here("R", "00_config.R"))

pw <- readRDS(file.path(PATH_PROCESSED, "pw.rds"))

# ---- ADF tests ---------------------------------------------------------------
# Time series tests:
# H0: the series has a unit root (non-stationary).
# H1: the series does not have a unit root (stationary).
adf_results <- pw |>
  dplyr::group_by(COUNTRY) |>
  dplyr::summarise(
    adf_level_p = tseries::adf.test(stats::na.omit(log(fx_usd_eop)))$p.value,
    adf_diff_p  = tseries::adf.test(stats::na.omit(dl_fx))$p.value,
    .groups = "drop"
  )

print(adf_results)
readr::write_csv(adf_results, file.path(PATH_TABLES, "adf_results.csv"))

# Interpretation (raw assignment):
# Exchange rates for IDN, MYS, and PHL are non-stationary at levels but become
# stationary after first-differencing, consistent with I(1) processes.

# ---- VAR lag selection and Granger causality ---------------------------------
# For causality testing, we use Granger causality because the data are time
# series and stationary in first differences; it is effectively a lagged OLS
# F-test.

countries <- c("IDN", "MYS", "PHL")
fx_wide <- pw |>
  dplyr::select(date, COUNTRY, dl_fx) |>
  tidyr::pivot_wider(names_from = COUNTRY, values_from = dl_fx) |>
  tidyr::drop_na()

# Use vars::VARselect for optimal lag length (VAR modelling context).
varselect_selection <- vars::VARselect(
  fx_wide[, countries],
  lag.max = 12,
  type = "const"
)$selection

print(varselect_selection)
varselect_df <- tibble::tibble(
  criterion = names(varselect_selection),
  lag = as.integer(varselect_selection)
)
readr::write_csv(varselect_df, file.path(PATH_TABLES, "varselect_selection.csv"))

# Interpretation (raw assignment):
# AIC (p=9) prioritizes minimizing forecast error variance by capturing subtle,
# higher-order lag relationships. SC/BIC at 1 indicates a single lag captures
# most predictable linear structure. We use p=1 for this analysis.
p <- 1

# Build all directed country pairs.
country_pairs <- tidyr::expand_grid(cause = countries, effect = countries) |>
  dplyr::filter(cause != effect)

# Run Granger tests for pre-July-1997 and full sample. July 1997 is the
# inflection point; pre-period acts as the "normal" market.
granger_all <- dplyr::bind_rows(
  `1980s-1999` = purrr::pmap_dfr(country_pairs, ~ run_granger_pair(fx_wide, ..1, ..2, p)),
  `pre-July 1997` = purrr::pmap_dfr(
    country_pairs,
    ~ run_granger_pair(dplyr::filter(fx_wide, date < "1997-07-01"), ..1, ..2, p)
  ),
  .id = "sample"
) |>
  dplyr::mutate(
    sig_5pct = p_value < 0.05,
    p_bonf = pmin(p_value * 6, 1)
  )

print(granger_all, n = Inf, width = Inf)
readr::write_csv(granger_all, file.path(PATH_TABLES, "granger_all.csv"))

# Interpretation (raw assignment):
# Pre-July 1997, there is no significant cross-border causality between
# exchange rates, consistent with isolatory managed/fixed exchange-rate regimes.
# In the full 1980s-1999 sample, there is relatively heavy confluence between
# markets (save for Indonesia and Philippines), indicating that transition to
# more flexible dynamics during the 1997-1998 AFC catalyzed spillovers.

message("05_analysis_timeseries.R complete: ADF/Granger outputs saved.")

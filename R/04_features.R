# ------------------------------------------------------------------------------
# Script: 04_features.R
# Purpose: Construct exchange-rate stress features and lagged predictors used by
#          the time-series tests and logit early-warning model.
# Inputs:  data/processed/rdf.rds
# Outputs: data/processed/pw.rds
# Depends on: R/00_config.R, R/03_clean.R
# ------------------------------------------------------------------------------

source(here::here("R", "00_config.R"))

rdf <- readRDS(file.path(PATH_PROCESSED, "rdf.rds"))

# ---- Feature construction ----------------------------------------------------
# We begin testing and analysis in service of future agent-based models. The
# ABM will be a behavioral model of banks in these countries and their changing
# patterns of investment relevant to macroeconomic changes. To that end we first
# confirm relationships, normality, and significance of these variables to the
# crisis.
pw <- rdf |>
  dplyr::arrange(COUNTRY, date) |>
  dplyr::group_by(COUNTRY) |>
  dplyr::mutate(
    res_usd = fx_reserves / fx_usd_eop,

    # Monthly changes (positive dl_fx = depreciation).
    dl_fx = log(fx_usd_eop) - dplyr::lag(log(fx_usd_eop)),
    dl_res = log(res_usd) - dplyr::lag(log(res_usd)),

    # Predictors, lagged one month so they come before the stress event.
    reer_gap_l1 = dplyr::lag(log(reer_cpi) - log(zoo::rollmeanr(reer_cpi, 36, fill = NA))),
    credit_g12_l1 = dplyr::lag(log(private_credit) - dplyr::lag(log(private_credit), 12)),
    m2_res_l1 = dplyr::lag(log(m2_broad_money / fx_reserves)),
    res_g6_l1 = dplyr::lag(log(res_usd) - dplyr::lag(log(res_usd), 6))
  ) |>
  dplyr::ungroup()

saveRDS(pw, file.path(PATH_PROCESSED, "pw.rds"))

message("04_features.R complete: pw saved.")

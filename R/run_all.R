# ------------------------------------------------------------------------------
# Script: run_all.R
# Purpose: Run the full AFC early-warning pipeline in order from a fresh R
#          session.
# Inputs:  .Renviron with FRED_API_KEY; network access for IMF/FRED APIs.
# Outputs: All artifacts written by scripts 01-07 into data/ and outputs/.
# Depends on: R/00_config.R through R/07_visualisation.R
# ------------------------------------------------------------------------------

# Run from project root. This script uses here::here() via sourced scripts.
source(here::here("R", "00_config.R"))
source(here::here("R", "01_import_imf.R"))
source(here::here("R", "02_import_fred_reer.R"))
source(here::here("R", "03_clean.R"))
source(here::here("R", "04_features.R"))
source(here::here("R", "05_analysis_timeseries.R"))
source(here::here("R", "06_analysis_logit.R"))
source(here::here("R", "07_visualisation.R"))

message("run_all.R complete: pipeline finished.")

# ------------------------------------------------------------------------------
# Script: 00_config.R
# Purpose: Load packages, define constants/paths, and provide shared helpers for
#          the Asian Financial Crisis early-warning pipeline.
# Inputs:  .Renviron (optional) containing FRED_API_KEY; no data files required.
# Outputs: Defines objects/functions in the R session for downstream scripts.
# Depends on: none (sourced first by R/run_all.R; also sourced by each script).
# ------------------------------------------------------------------------------

# ---- Packages ----------------------------------------------------------------
# Loaded packages are limited to those used by the pipeline scripts.
suppressPackageStartupMessages({
  library(here)
  library(imf.data)
  library(tidyverse)
  library(janitor)
  library(stringr)
  library(tidyr)
  library(fredr)
  library(zoo)
  library(lmtest)
  library(tseries)
  library(vars)
  library(ggplot2)
})

# REVIEW: The raw assignment loaded additional packages that are not used by the
# retained analysis outputs: WDI, writexl, wbstats, data.table, pandoc, pROC.
# They are not loaded here to keep dependencies minimal; confirm none are needed
# for planned extensions.

# ---- Constants ---------------------------------------------------------------
COUNTRIES  <- c("THA", "IDN", "MYS", "PHL")
START_DATE <- "1987-01-01"
END_DATE   <- "2017-12-31"
TRAIN_END  <- as.Date("1996-12-01")

# ---- Paths -------------------------------------------------------------------
PATH_RAW       <- here::here("data", "raw")
PATH_PROCESSED <- here::here("data", "processed")
PATH_TABLES    <- here::here("outputs", "tables")
PATH_FIGURES   <- here::here("outputs", "figures")

dir.create(PATH_RAW, recursive = TRUE, showWarnings = FALSE)
dir.create(PATH_PROCESSED, recursive = TRUE, showWarnings = FALSE)
dir.create(PATH_TABLES, recursive = TRUE, showWarnings = FALSE)
dir.create(PATH_FIGURES, recursive = TRUE, showWarnings = FALSE)

# ---- FRED API key ------------------------------------------------------------
# Load .Renviron from project root if present, then read the key from the
# environment. Do not hardcode or print the key.
renviron_path <- here::here(".Renviron")
if (file.exists(renviron_path)) {
  readRenviron(renviron_path)
}

FRED_API_KEY <- Sys.getenv("FRED_API_KEY")
if (!nzchar(FRED_API_KEY)) {
  stop(
    "FRED_API_KEY is empty. Copy .Renviron.example to .Renviron and add your ",
    "free key from https://fred.stlouisfed.org/docs/api/api_key.html, then ",
    "restart R or rerun the script.",
    call. = FALSE
  )
}
fredr::fredr_set_key(FRED_API_KEY)

# ---- Shared helpers ----------------------------------------------------------

# Pull one IMF series specification and return a tidy data frame, or NULL on
# failure/empty result. Preserves raw-assignment behavior.
pull_dat <- function(spec, countries = COUNTRIES, start = START_DATE, end = END_DATE) {
  f <- c(list(COUNTRY = countries), spec$filters)

  result <- tryCatch({
    # Raw assignment used imf.data::get_data(); keep the same call.
    imf.data::get_data(
      spec$dataflow,
      filters = f,
      start_period = start,
      end_period = end
    )
  }, error = function(e) {
    message(sprintf("[%s / %s] failed: %s", spec$label, spec$dataflow, conditionMessage(e)))
    NULL
  })

  if (is.null(result) || nrow(result) == 0) {
    message(sprintf("[%s / %s] returned no rows", spec$label, spec$dataflow))
    return(NULL)
  }

  result |>
    dplyr::mutate(series = spec$label, dataflow = spec$dataflow)
}

# Summary helper used during raw data inspection. Returns a named list of
# summary() outputs by country.
summary_wide <- function(d = panel_wide, c = COUNTRIES) {
  out <- list()
  for (i in c) {
    out[[i]] <- d |>
      dplyr::filter(COUNTRY == i) |>
      summary()
  }
  out
}

# Run one pairwise Granger causality test (lmtest::grangertest) for a cause ->
# effect pair at lag order p.
run_granger_pair <- function(dat, cause, effect, p) {
  g <- lmtest::grangertest(
    stats::as.formula(paste(effect, "~", cause)),
    order = p,
    data = dat
  )
  tibble::tibble(
    cause = cause,
    effect = effect,
    F_stat = g$F[2],
    p_value = g$`Pr(>F)`[2]
  )
}

# ------------------------------------------------------------------------------
# Script: 02_import_fred_reer.R
# Purpose: Fill Indonesia and Thailand REER gaps using FRED/OECD/BIS series,
#          rebase/splice series, interpolate to monthly calendar, and merge into
#          the IMF panel.
# Inputs:  data/processed/panel_wide_imf_raw.rds
#          FRED API series (CCRETT01IDQ661N, RBIDBIS, RBTHBIS, CCRETT01THQ661N)
# Outputs: data/processed/panel_wide_with_reer.rds
#          outputs/tables/reer_fill_confirmation.csv
# Depends on: R/00_config.R, R/01_import_imf.R
# ------------------------------------------------------------------------------

source(here::here("R", "00_config.R"))

panel_wide <- readRDS(file.path(PATH_PROCESSED, "panel_wide_imf_raw.rds"))

# ---- Indonesia REER gap fill -------------------------------------------------
# Raw assignment note:
# FRED provides BIS REER from 1994 onward and quarterly OECD REER pre-1994.
# We can interpolate pre-1994 data. This should not compromise the ABM since
# the key inflection point is 1997-1998. Thailand still requires extraction.
reer_oecd_idn <- fredr::fredr(
  series_id = "CCRETT01IDQ661N",
  observation_start = as.Date("1980-01-01"),
  observation_end = as.Date("1993-12-31")
) |>
  dplyr::mutate(country = "IDN", source = "OECD", frequency = "quarterly")

reer_bis_idn <- fredr::fredr(
  series_id = "RBIDBIS",
  observation_start = as.Date("1994-01-01"),
  observation_end = as.Date("2017-12-31")
) |>
  dplyr::mutate(value = value / mean(value[format(date, "%Y") == "2010"]) * 100) |>
  dplyr::mutate(country = "IDN", source = "BIS", frequency = "monthly")

# Rebasing rationale (raw assignment):
# The two sources do not share a base year. OECD and BIS index different
# reference periods to 100, so raw numbers are not directly comparable. If
# spliced without rebasing, an artificial jump would appear at the splice point
# (Jan 1994) due to scale differences, not real exchange-rate movement.
# Rebasing puts both on a shared scale before splicing.
oecd_anchor <- reer_oecd_idn |>
  dplyr::filter(date == max(date)) |>
  dplyr::pull(value)
bis_anchor <- reer_bis_idn |>
  dplyr::filter(date == min(date)) |>
  dplyr::pull(value)

reer_oecd_idn <- reer_oecd_idn |>
  dplyr::mutate(value_rebased = value / oecd_anchor * bis_anchor)

reer_bis_idn <- reer_bis_idn |>
  dplyr::mutate(value_rebased = value)

reer_idn_spliced <- dplyr::bind_rows(
  reer_oecd_idn |>
    dplyr::select(date, value = value_rebased, source, frequency),
  reer_bis_idn |>
    dplyr::select(date, value = value_rebased, source, frequency)
) |>
  dplyr::arrange(date) %>%
  dplyr::mutate(country = "IDN")

# Combine spliced data with the panel.
reer_idn_spliced <- reer_idn_spliced |>
  dplyr::mutate(TIME_PERIOD = format(date, "%Y-M%m"))

# Build a complete monthly calendar for 1987-2017 to interpolate onto.
full_months <- tibble::tibble(
  TIME_PERIOD = format(
    seq(as.Date(START_DATE), as.Date(END_DATE), by = "month"),
    "%Y-M%m"
  )
)

idn_reer_monthly <- full_months |>
  dplyr::left_join(
    reer_idn_spliced |> dplyr::select(TIME_PERIOD, value),
    by = "TIME_PERIOD"
  ) |>
  dplyr::mutate(value_interp = zoo::na.approx(value, na.rm = FALSE)) |>
  dplyr::select(TIME_PERIOD, reer_cpi_new = value_interp)

# Mapping onto panel wide with na.approx from the zoo package.
panel_wide <- panel_wide |>
  dplyr::left_join(idn_reer_monthly, by = "TIME_PERIOD") |>
  dplyr::mutate(reer_cpi = dplyr::if_else(
    COUNTRY == "IDN",
    dplyr::coalesce(reer_cpi, reer_cpi_new),
    reer_cpi
  )) |>
  dplyr::select(-reer_cpi_new)

# Confirm IDN fill worked.
idn_fill_check <- panel_wide |>
  dplyr::filter(COUNTRY == "IDN") |>
  dplyr::summarise(
    n = dplyr::n(),
    n_filled = sum(!is.na(reer_cpi)),
    first_filled = min(TIME_PERIOD[!is.na(reer_cpi)])
  )
print(idn_fill_check)

# ---- Thailand REER gap fill --------------------------------------------------
# Raw assignment note:
# Thailand has the same REER gap. FRED carries the BIS series from 1994 onward.
# It is rebased to 2010 = 100 to match the IMF series, and an OECD quarterly
# series is attempted for the pre-1994 period.
reer_bis_tha <- fredr::fredr(
  series_id = "RBTHBIS",
  observation_start = as.Date("1994-01-01"),
  observation_end = as.Date("2017-12-31")
) |>
  dplyr::mutate(value = value / mean(value[format(date, "%Y") == "2010"]) * 100) |>
  dplyr::mutate(source = "BIS", frequency = "monthly")

reer_oecd_tha <- tryCatch(
  fredr::fredr(
    series_id = "CCRETT01THQ661N",
    observation_start = as.Date("1980-01-01"),
    observation_end = as.Date("1993-12-31")
  ),
  error = function(e) {
    message("OECD series for THA unavailable on FRED, BIS only from 1994")
    NULL
  }
)

if (!is.null(reer_oecd_tha)) {
  reer_oecd_tha <- reer_oecd_tha |>
    dplyr::mutate(
      value = value / value[date == max(date)] * reer_bis_tha$value[1],
      source = "OECD", frequency = "quarterly"
    )
}

reer_tha_spliced <- dplyr::bind_rows(reer_oecd_tha, reer_bis_tha) |>
  dplyr::arrange(date) |>
  dplyr::mutate(TIME_PERIOD = format(date, "%Y-M%m"))

tha_reer_monthly <- full_months |>
  dplyr::left_join(
    reer_tha_spliced |> dplyr::select(TIME_PERIOD, value),
    by = "TIME_PERIOD"
  ) |>
  dplyr::mutate(value_interp = zoo::na.approx(value, na.rm = FALSE)) |>
  dplyr::select(TIME_PERIOD, reer_cpi_tha = value_interp)

panel_wide <- panel_wide |>
  dplyr::left_join(tha_reer_monthly, by = "TIME_PERIOD") |>
  dplyr::mutate(reer_cpi = dplyr::if_else(
    COUNTRY == "THA",
    dplyr::coalesce(reer_cpi, reer_cpi_tha),
    reer_cpi
  )) |>
  dplyr::select(-reer_cpi_tha)

# Confirm THA fill worked.
tha_fill_check <- panel_wide |>
  dplyr::filter(COUNTRY == "THA") |>
  dplyr::summarise(
    n = dplyr::n(),
    n_filled = sum(!is.na(reer_cpi)),
    first_filled = min(TIME_PERIOD[!is.na(reer_cpi)])
  )
print(tha_fill_check)

# REVIEW: IDN and THA REER fill logic is similar but not identical (IDN uses
# oecd_anchor/bis_anchor rebasing; THA rebases OECD to the first BIS value when
# OECD is available). I kept both blocks to preserve original behavior exactly.

fill_confirmation <- dplyr::bind_rows(
  idn_fill_check |> dplyr::mutate(COUNTRY = "IDN"),
  tha_fill_check |> dplyr::mutate(COUNTRY = "THA")
) |>
  dplyr::select(COUNTRY, n, n_filled, first_filled)
readr::write_csv(fill_confirmation, file.path(PATH_TABLES, "reer_fill_confirmation.csv"))

saveRDS(panel_wide, file.path(PATH_PROCESSED, "panel_wide_with_reer.rds"))

message("02_import_fred_reer.R complete: REER-filled panel saved.")

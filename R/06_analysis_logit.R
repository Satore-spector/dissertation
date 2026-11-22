# ------------------------------------------------------------------------------
# Script: 06_analysis_logit.R
# Purpose: Define EMP-based stress months, split train/test around TRAIN_END,
#          fit a logistic early-warning model, and export coefficients/odds
#          ratios and stress counts.
# Inputs:  data/processed/pw.rds
# Outputs: outputs/tables/stress_month_counts.csv
#          outputs/tables/logit_coefficients.csv
#          outputs/tables/logit_odds_ratios.csv
#          outputs/tables/logit_model_summary.txt
#          data/processed/logit_model.rds
# Depends on: R/00_config.R, R/04_features.R
# ------------------------------------------------------------------------------

source(here::here("R", "00_config.R"))

pw <- readRDS(file.path(PATH_PROCESSED, "pw.rds"))

# ---- Stress-month (EMP) definition -------------------------------------------
# Logit early-warning system: define stress months as periods when currency
# depreciation is large or reserves fall a lot. k scales reserve changes against
# FX volatility because absolute reserve deviations can dominate; this is better
# than taking log since we deal in negatives.
emp_params <- pw |>
  dplyr::filter(date <= TRAIN_END) |>
  dplyr::group_by(COUNTRY) |>
  dplyr::summarise(k = sd(dl_fx, na.rm = TRUE) / sd(dl_res, na.rm = TRUE), .groups = "drop")

pw <- pw |>
  dplyr::left_join(emp_params, by = "COUNTRY") |>
  dplyr::mutate(emp = dl_fx - k * dl_res) |>
  dplyr::group_by(COUNTRY) |>
  dplyr::mutate(
    emp_mu = mean(emp[date <= TRAIN_END], na.rm = TRUE),
    emp_sd = sd(emp[date <= TRAIN_END], na.rm = TRUE),
    stress = as.integer(emp > emp_mu + 1.5 * emp_sd)
  ) |>
  dplyr::ungroup()

# Stress months by country and period.
stress_counts <- pw |>
  dplyr::group_by(COUNTRY, period = ifelse(date <= TRAIN_END, "train", "test")) |>
  dplyr::summarise(
    n = sum(!is.na(stress)),
    stress_months = sum(stress, na.rm = TRUE),
    .groups = "drop"
  )

print(stress_counts, n = Inf)
readr::write_csv(stress_counts, file.path(PATH_TABLES, "stress_month_counts.csv"))

# ---- Logit model -------------------------------------------------------------
model_df <- pw |>
  dplyr::select(COUNTRY, date, stress, dplyr::ends_with("_l1")) |>
  tidyr::drop_na()

train <- dplyr::filter(model_df, date <= TRAIN_END)
test <- dplyr::filter(model_df, date > TRAIN_END)

# REVIEW: `test` is created as in the raw assignment but not used in downstream
# evaluation/model comparison. Kept for fidelity and potential extension.

fit <- stats::glm(
  stress ~ reer_gap_l1 + credit_g12_l1 + m2_res_l1 + res_g6_l1 + COUNTRY,
  data = train,
  family = stats::binomial()
)

fit_summary <- summary(fit)
print(fit_summary)
capture.output(fit_summary, file = file.path(PATH_TABLES, "logit_model_summary.txt"))

# ---- Local helper ------------------------------------------------------------
# Keep coefficient extraction dependency-free (no broom required).
broom_like_coef <- function(s) {
  co <- as.data.frame(s$coefficients)
  co$term <- rownames(co)
  co <- co[, c("term", "Estimate", "Std. Error", "z value", "Pr(>|z|)")]
  colnames(co) <- c("term", "estimate", "std_error", "z_value", "p_value")
  tibble::as_tibble(co)
}

# Coefficients table.
coef_table <- broom_like_coef(fit_summary)
readr::write_csv(coef_table, file.path(PATH_TABLES, "logit_coefficients.csv"))

# Odds ratios with default (Wald) confidence intervals, as in raw script.
odds_ratios <- cbind(OR = exp(stats::coef(fit)), exp(stats::confint.default(fit)))
odds_ratios_df <- tibble::tibble(term = rownames(odds_ratios)) |>
  dplyr::bind_cols(as.data.frame(odds_ratios))
colnames(odds_ratios_df) <- c("term", "OR", "CI_low", "CI_high")
print(odds_ratios_df)
readr::write_csv(odds_ratios_df, file.path(PATH_TABLES, "logit_odds_ratios.csv"))

saveRDS(fit, file.path(PATH_PROCESSED, "logit_model.rds"))

# Interpretation (raw assignment):
# The output is significant in its insignificance. The null hypothesis that the
# variables have no effect on stress months is not rejected. This conforms to
# Krugman's argument that macroeconomic fundamentals were not to blame; instead
# this was a heuristic issue.

message("06_analysis_logit.R complete: logit outputs saved.")

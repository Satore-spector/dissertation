# ------------------------------------------------------------------------------
# Script: 07_visualisation.R
# Purpose: Create figures from analysis outputs. Currently produces the Granger
#          causality heatmap; structured for easy extension with additional plots.
# Inputs:  outputs/tables/granger_all.csv
# Outputs: outputs/figures/granger_causality_heatmap.png
# Depends on: R/00_config.R, R/05_analysis_timeseries.R
# ------------------------------------------------------------------------------

source(here::here("R", "00_config.R"))

granger_all <- readr::read_csv(file.path(PATH_TABLES, "granger_all.csv"), show_col_types = FALSE)

# ---- Granger causality heatmap ----------------------------------------------
# Graphical representation of causality grid, facet-wrapped to show pre-1997
# (right) and full sample (left) as in the raw assignment.
granger_heatmap <- ggplot2::ggplot(granger_all, ggplot2::aes(x = cause, y = effect, fill = F_stat)) +
  ggplot2::geom_tile(color = "white") +
  ggplot2::geom_text(
    ggplot2::aes(label = ifelse(sig_5pct, paste0(round(F_stat, 1), "*"), round(F_stat, 1)))
  ) +
  ggplot2::facet_wrap(~sample) +
  ggplot2::scale_fill_gradient(low = "grey", high = "red") +
  ggplot2::labs(
    title = "Granger causality of monthly depreciation",
    x = "Cause",
    y = "Effect",
    fill = "F"
  ) +
  ggplot2::theme_minimal()

print(granger_heatmap)

ggplot2::ggsave(
  filename = file.path(PATH_FIGURES, "granger_causality_heatmap.png"),
  plot = granger_heatmap,
  width = 9,
  height = 4.5,
  dpi = 300
)

# ---- Additional plots --------------------------------------------------------
# The raw Rmd ended with an empty "##" heading, so more plots are expected.
# Add new plot blocks below, saving each with ggsave() to PATH_FIGURES.

message("07_visualisation.R complete: figures saved.")

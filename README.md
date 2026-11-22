# Agent-Based Modelling Approach to Forecasting the Asian Financial Crisis

This project is an early empirical/pre-modeling pipeline for a dissertation on agent-based modelling (ABM) approaches to forecasting the Asian Financial Crisis (AFC). It assembles monthly macro-financial data for Thailand, Indonesia, Malaysia, and the Philippines, harmonizes gaps in real effective exchange rates, and constructs exchange-market stress indicators. The cleaned data are then used for exploratory diagnostics—ADF stationarity tests, pairwise Granger causality tests, and a logistic early-warning model—to assess whether macro fundamentals signaled stress before/during the AFC and to inform behavioral assumptions for later ABM work.

## Data sources

- **IMF (via `imf.data`)**: monthly macro-financial series pulled for `THA`, `IDN`, `MYS`, `PHL`, 1987-01 to 2017-12.
- **FRED / BIS / OECD**: REER gap-filling series used to splice/rebase Indonesia and Thailand REER before 1994 / around missing IMF coverage.

| Label in pipeline | Source/dataflow | Series/code | Description |
|---|---|---|---|
| `reer_cpi` | IMF EER | `REER_IX_RY2010_ACW_RCPI`, monthly | CPI-based real effective exchange rate index |
| `fx_usd_eop` | IMF ER | `XDC_USD`, `EOP_RT`, monthly | Bilateral exchange rate vs USD, end of period |
| `fx_reserves` | IMF MFS_NSRF | `NSRF_11`, monthly | Foreign assets / FX reserves proxy |
| `net_foreign_assets` | IMF MFS_NSRF | `NSRF_31N`, monthly | Net foreign assets in banking system |
| `m2_broad_money` | IMF MFS_NSRF | `NSRF_35L`, monthly | Money plus quasi money (M2) |
| `private_credit` | IMF MFS_NSRF | `NSRF_22D`, monthly | Claims on private sector |
| `reserve_money` | IMF MFS_NSRF | `NSRF_14_`, monthly | Reserve/base money |
| IDN REER splice | FRED/OECD/BIS | `CCRETT01IDQ661N` (OECD, quarterly, pre-1994), `RBIDBIS` (BIS, monthly, 1994+) | Indonesia REER gap fill; rebased/spliced to common scale |
| THA REER splice | FRED/OECD/BIS | `CCRETT01THQ661N` (OECD, quarterly, attempted pre-1994), `RBTHBIS` (BIS, monthly, 1994+) | Thailand REER gap fill; rebased to 2010=100 where applicable |

## Pipeline

| Script | What it does | Key outputs |
|---|---|---|
| `R/00_config.R` | Loads packages, sets constants/paths, validates `FRED_API_KEY`, defines shared helpers | Session objects/functions |
| `R/01_import_imf.R` | Discovers IMF datasets, pulls IMF series, builds raw panel, writes coverage/NA checks | `data/raw/imf_vars.csv`, `outputs/tables/imf_coverage_report.csv`, `outputs/tables/imf_na_summary.csv`, `outputs/tables/imf_phl_na_rows.csv`, `data/processed/panel_wide_imf_raw.rds` |
| `R/02_import_fred_reer.R` | Fills IDN/THA REER gaps via FRED/OECD/BIS; rebases/splices/interpolates; merges into panel | `data/processed/panel_wide_with_reer.rds`, `outputs/tables/reer_fill_confirmation.csv` |
| `R/03_clean.R` | Handles dates, completes monthly grid, interpolates short gaps (`maxgap=3`), builds model dataset `rdf` | `data/processed/rdf.rds`, `outputs/tables/na_check_by_country.csv`, `outputs/tables/phl_na_rows.csv`, `outputs/tables/rdf_summary_by_country.txt` |
| `R/04_features.R` | Constructs `res_usd`, `dl_fx`, `dl_res`, lagged predictors (`reer_gap_l1`, `credit_g12_l1`, `m2_res_l1`, `res_g6_l1`) | `data/processed/pw.rds` |
| `R/05_analysis_timeseries.R` | Runs ADF tests, VAR lag selection, pairwise Granger causality pre-July 1997 vs full sample | `outputs/tables/adf_results.csv`, `outputs/tables/varselect_selection.csv`, `outputs/tables/granger_all.csv` |
| `R/06_analysis_logit.R` | Defines EMP stress months, train/test split at `TRAIN_END`, fits logit early-warning model, exports odds ratios | `outputs/tables/stress_month_counts.csv`, `outputs/tables/logit_coefficients.csv`, `outputs/tables/logit_odds_ratios.csv`, `outputs/tables/logit_model_summary.txt`, `data/processed/logit_model.rds` |
| `R/07_visualisation.R` | Builds Granger causality heatmap; easy to extend with additional plots | `outputs/figures/granger_causality_heatmap.png` |
| `R/run_all.R` | Sources scripts 00-07 in order for one-command execution | All pipeline artifacts |

## How to run

1. **Install R packages** (R 4.5+ recommended). If `renv` is used in this repo, restore the environment:

   ```r
   install.packages("renv") # if needed
   renv::restore()
   ```

   If you are not using `renv`, install packages used by the pipeline: `here`, `imf.data`, `tidyverse`, `janitor`, `stringr`, `tidyr`, `fredr`, `zoo`, `lmtest`, `tseries`, `vars`, `ggplot2`.

2. **Configure FRED API key**. Copy `.Renviron.example` to `.Renviron` and add your own free key from [FRED API](https://fred.stlouisfed.org/docs/api/api_key.html):

   ```text
   FRED_API_KEY=your_key_here
   ```

3. **Run the pipeline** from the project root:

   ```r
   source("R/run_all.R")
   ```

   Scripts are designed to run from a fresh R session and read/write intermediate files under `data/` and `outputs/`.

## Findings (from the original analysis)

- **Granger causality**: Pre-July 1997, there is no significant cross-border causality between exchange-rate depreciation series, consistent with isolatory managed/fixed exchange-rate regimes. In the full 1980s-1999 sample, there is relatively heavy confluence between markets (save for Indonesia and Philippines), indicating that transition to more flexible dynamics during the 1997–1998 AFC catalyzed spillovers.
- **Logit early-warning model**: The model output is significant in its insignificance: the null hypothesis that the selected lagged fundamentals have no effect on stress months is not rejected. This is consistent with Krugman's argument that macroeconomic fundamentals were not to blame; instead this was a heuristic issue.

These findings are reported as exploratory evidence for later ABM assumptions and should not be over-interpreted beyond the original assignment scope.

## Known limitations

- **Thailand excluded from model dataset (`rdf`)**: Thailand has REER/data-gap issues in the early period; after cleaning, `rdf` excludes `THA` and keeps `IDN`, `MYS`, `PHL`.
- **Sample end for model dataset**: `rdf` is filtered to `date <= 2007-12-01` and then `drop_na()` is applied.
- **Stress definition is rule-based**: stress months are defined by EMP exceeding training-period mean + 1.5 SD, with training ending at `1996-12-01`.
- **Granger lag choice**: VAR selection reports AIC/SC criteria; the analysis uses `p = 1` as in the raw assignment.
- **Raw assignment provenance**: the original working Rmd is preserved at `archive/raw_assignment.Rmd`; methodology/parameters were kept unchanged during refactor.

## Repository layout

```text
.
├── archive/                 # Original raw assignment (preserved)
├── data/
│   ├── raw/                 # Raw pulled data (gitignored)
│   └── processed/           # Intermediate .rds objects (gitignored)
├── outputs/
│   ├── tables/              # CSV/TXT analysis outputs
│   └── figures/             # Plots
├── R/                       # Numbered pipeline scripts + run_all.R
├── .Renviron.example        # FRED key template (no secrets)
└── README.md
```

## Author

- **Teerth Narang** — MSc Economics, Data Analytics  
- Symbiosis School of Economics, Department of DA, SB Road, Pune  
- October 2026 (assignment date from raw Rmd metadata)

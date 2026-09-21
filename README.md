# Are NBA Salaries Efficient?

Scraping 2025-26 NBA stats and salaries from Basketball-Reference with `rvest` to estimate what the market pays for on-court production, and which players are paid well below that rate.

Blog post: *link to be added*

## Question

Holding production fixed, how far do individual salaries deviate from the market rate, and are those deviations systematic by age (a proxy for rookie-scale contracts)?

## Main findings

- Among 278 players with 1,000+ minutes, current-season VORP explains less than 20% of the variation in log salary, even among players aged 25+.
- Holding VORP fixed, players aged 24 and under earn about 38% less than players aged 25-29; players 30 and over earn about 68% more (both p < 0.001, HC1 robust SEs).
- The largest surplus values belong mostly to players on rookie-scale deals. Rankings are stable when Win Shares replaces VORP (Spearman correlation 0.92).

## Data

| File | Source | Description |
|---|---|---|
| `data/raw/advanced_2026.csv` | [basketball-reference.com/leagues/NBA_2026_advanced.html](https://www.basketball-reference.com/leagues/NBA_2026_advanced.html) | Advanced stats, all players |
| `data/raw/salaries_2026.csv` | `basketball-reference.com/teams/{TEAM}/2026.html` (30 pages) | Salary table from each team page |
| `data/processed/nba_2026.csv` | Built by `02_clean.R` | One row per player, stats merged with salary |

Data were scraped on September 21, 2026.

**Access and ethics.** Only public pages were requested; no login, paywall or CAPTCHA was involved. The site's robots.txt allows `/leagues/` and `/teams/` and sets `Crawl-delay: 3`, and Sports Reference [blocks clients sending more than 20 requests per minute](https://www.sports-reference.com/bot-traffic.html). The scraper makes 32 requests in total, spaced 4 seconds apart.

## Repository structure

```
code/
  01_scrape.R     scrape advanced stats and 30 team salary tables
  02_clean.R      clean, match player names, merge, apply minutes filter
  03_analyze.R    market-rate model, surplus value, robustness, figures
data/
  raw/            scraped tables, saved as downloaded
  processed/      analysis dataset
results/
  figures/        fig1_market_curve.png, fig2_top_bargains.png, fig3_surplus_by_age.png
  tables/         top bargains, top overpaid, age-group summary, model fit, age coefficients
```

## How to replicate

1. Clone the repository and open `nba-salary-efficiency.Rproj` in RStudio.
2. Install the packages:
```r
   install.packages(c("rvest", "dplyr", "readr", "stringr", "stringi", "ggplot2",
                      "ggrepel", "sandwich", "lmtest", "here"))
```
3. Run the scripts in order:
```r
   source("code/01_scrape.R")   # about 2 minutes because of rate limiting
   source("code/02_clean.R")
   source("code/03_analyze.R")
```
   The raw data are included, so step 1 can be skipped. Re-scraping later may return slightly different numbers if Basketball-Reference revises its data.

Built with R 4.6.1.

## Method notes

- **Traded players** keep the combined row (`2TM`, `3TM`, `4TM`). A player listed on more than one team's salary table is assigned the larger figure, an approximation of his annual salary.
- **Name matching** uses a normalised key (accents, Cyrillic look-alike characters, suffixes and punctuation removed). Two names are matched by hand in `02_clean.R`.
- **Two-way contracts** have no salary on the team pages and are excluded (one player above the minutes threshold).
- **Market rate** is estimated by regressing log salary on VORP for players aged 25+, then applied to everyone. Predictions are back-transformed with Duan's smearing estimator and capped at the highest salary in the data. A spline version fits only slightly better (AIC 472 vs 475) and bends upward at low VORP, so the linear version is used.
- **Surplus value** is market value minus salary. A player is flagged as a bargain if his salary falls below the 80% prediction interval.

## Limitations

- The model is descriptive, not causal. Win Shares and VORP accumulate with minutes, and higher-paid players tend to get more minutes, which likely makes the estimated surplus of low-paid players conservative.
- Age is only a proxy for contract type; some players aged 25-26 are still on rookie deals.
- Salaries are set when contracts are signed, often years earlier, so part of every gap reflects changes in a player's performance since then.
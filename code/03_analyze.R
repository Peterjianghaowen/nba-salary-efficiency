# Market-rate salary curve and player surplus value
# Curve is fitted on players 25+ (mostly open-market contracts), then applied to everyone.

library(dplyr)
library(readr)
library(ggplot2)
library(ggrepel)
library(splines)
library(sandwich)
library(lmtest)
library(here)

season <- 2026
nba <- read_csv(here("data", "processed", paste0("nba_", season, ".csv"))) |>
  mutate(age_group = cut(age, breaks = c(0, 24, 29, Inf),
                         labels = c("24 and under", "25-29", "30 and over")))

market  <- filter(nba, age >= 25)
max_sal <- max(nba$salary_m)  # max contract caps what anyone can be paid

# 1. Candidate market-rate models: log salary on production
models <- list(
  "Linear WS"   = lm(log(salary_m) ~ ws,               data = market),
  "Spline WS"   = lm(log(salary_m) ~ ns(ws, df = 3),   data = market),
  "Linear VORP" = lm(log(salary_m) ~ vorp,             data = market),
  "Spline VORP" = lm(log(salary_m) ~ ns(vorp, df = 3), data = market)
)
model_fit <- tibble(model = names(models),
                    r2    = sapply(models, \(m) summary(m)$r.squared),
                    aic   = sapply(models, AIC))

# Main model: linear VORP (monotone in production)
fit   <- models[["Linear VORP"]]
smear <- mean(exp(resid(fit)))  # Duan smearing for the log back-transform
pred  <- predict(fit, newdata = nba, interval = "prediction", level = 0.8)

nba <- nba |>
  mutate(market_value_m = pmin(exp(pred[, "fit"]) * smear, max_sal),
         surplus_m      = market_value_m - salary_m,        # > 0: paid below market rate
         bargain        = salary_m < exp(pred[, "lwr"]),     # below the 80% prediction band
         overpaid       = salary_m > exp(pred[, "upr"]))

# 2. Robustness: same approach with Win Shares
fit_ws   <- models[["Linear WS"]]
smear_ws <- mean(exp(resid(fit_ws)))
nba$surplus_ws_m <- pmin(exp(predict(fit_ws, newdata = nba)) * smear_ws, max_sal) - nba$salary_m
rank_corr <- cor(nba$surplus_m, nba$surplus_ws_m, method = "spearman")

# 3. Age discount: full sample, holding production fixed, robust SEs
fit_age <- lm(log(salary_m) ~ vorp + age_group,
              data = mutate(nba, age_group = relevel(age_group, ref = "25-29")))
age_test <- coeftest(fit_age, vcov = vcovHC(fit_age, type = "HC1"))
age_discount <- exp(coef(fit_age)[c("age_group24 and under", "age_group30 and over")]) - 1

# Tables
round2 <- function(df) mutate(df, across(where(is.numeric), \(x) round(x, 2)))
cols <- c("player", "team", "age", "vorp", "ws", "salary_m", "market_value_m", "surplus_m", "bargain")

top_bargains <- nba |> arrange(desc(surplus_m)) |> slice_head(n = 15) |> select(all_of(cols))
top_overpaid <- nba |> arrange(surplus_m) |> slice_head(n = 15) |> select(all_of(cols))

by_age <- nba |>
  group_by(age_group) |>
  summarise(players          = n(),
            median_salary_m  = median(salary_m),
            median_vorp      = median(vorp),
            median_surplus_m = median(surplus_m),
            share_bargain    = mean(bargain),
            share_overpaid   = mean(overpaid))

age_coefs <- data.frame(term = rownames(age_test), unclass(age_test), row.names = NULL)

write_csv(round2(top_bargains), here("results", "tables", "top_bargains.csv"))
write_csv(round2(top_overpaid), here("results", "tables", "top_overpaid.csv"))
write_csv(round2(by_age),       here("results", "tables", "by_age_group.csv"))
write_csv(round2(model_fit),    here("results", "tables", "model_fit.csv"))
write_csv(age_coefs,            here("results", "tables", "age_discount_robust.csv"))
write_csv(tibble(rank_corr = round(rank_corr, 3)), here("results", "tables", "robustness.csv"))

# Figure 1: market-rate curve with 80% prediction band
grid <- tibble(vorp = seq(min(nba$vorp), max(nba$vorp), length.out = 200))
grid_pred <- predict(fit, newdata = grid, interval = "prediction", level = 0.8)
grid <- grid |>
  mutate(value = pmin(exp(grid_pred[, "fit"]) * smear, max_sal),
         lo    = exp(grid_pred[, "lwr"]),
         hi    = pmin(exp(grid_pred[, "upr"]), max_sal))

label_df <- nba |> filter(rank(-surplus_m) <= 8 | rank(surplus_m) <= 5)
age_cols <- c("24 and under" = "#1b9e77", "25-29" = "#7570b3", "30 and over" = "#d95f02")

p1 <- ggplot(nba, aes(vorp, salary_m)) +
  geom_ribbon(data = grid, aes(vorp, ymin = lo, ymax = hi),
              inherit.aes = FALSE, fill = "grey85") +
  geom_line(data = grid, aes(vorp, value), inherit.aes = FALSE, linewidth = 1) +
  geom_point(aes(colour = age_group), alpha = 0.7) +
  geom_text_repel(data = label_df, aes(label = player), size = 3,
                  min.segment.length = 0, box.padding = 0.5,
                  max.overlaps = Inf, seed = 42) +
  scale_colour_manual(values = age_cols) +
  coord_cartesian(ylim = c(0, max_sal * 1.05)) +
  labs(title = "Market-rate salary curve, 2025-26",
       subtitle = "Curve and 80% band fitted on players aged 25+, capped at the max salary",
       x = "VORP (value over replacement player)", y = "Salary ($ millions)", colour = "Age",
       caption = "Source: Basketball-Reference. Players with 1,000+ minutes.") +
  theme_minimal()
ggsave(here("results", "figures", "fig1_market_curve.png"), p1, width = 8, height = 5.5, dpi = 300)

# Figure 2: largest surplus values
p2 <- ggplot(top_bargains |> left_join(select(nba, player, age_group), by = "player"),
             aes(surplus_m, reorder(player, surplus_m), fill = age_group)) +
  geom_col() +
  scale_fill_manual(values = age_cols) +
  labs(title = "Largest surplus value: market value minus salary",
       x = "Surplus value ($ millions)", y = NULL, fill = "Age",
       caption = "Source: Basketball-Reference.") +
  theme_minimal()
ggsave(here("results", "figures", "fig2_top_bargains.png"), p2, width = 8, height = 5.5, dpi = 300)

# Figure 3: surplus by age group
p3 <- ggplot(nba, aes(age_group, surplus_m, fill = age_group)) +
  geom_hline(yintercept = 0, linetype = "dashed") +
  geom_boxplot(show.legend = FALSE) +
  scale_fill_manual(values = age_cols) +
  labs(title = "Surplus value by age group",
       x = NULL, y = "Market value minus salary ($ millions)",
       caption = "Source: Basketball-Reference. Players with 1,000+ minutes.") +
  theme_minimal()
ggsave(here("results", "figures", "fig3_surplus_by_age.png"), p3, width = 7, height = 5, dpi = 300)

# Key numbers
model_fit
age_test
age_discount
rank_corr
by_age
top_bargains
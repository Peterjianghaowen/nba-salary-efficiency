# Clean advanced stats and salaries, merge into one player-level table

library(dplyr)
library(readr)
library(stringr)
library(here)

season <- 2026

adv_raw    <- read_csv(here("data", "raw", paste0("advanced_", season, ".csv")))
salary_raw <- read_csv(here("data", "raw", paste0("salaries_", season, ".csv")))

# Name formats differ across pages (accents, Jr./III suffixes), so match on a normalised key
name_key <- function(x) {
  x |>
    stringi::stri_trans_general("Any-Latin; NFD; [:Nonspacing Mark:] Remove; Latin-ASCII") |>
    tolower() |>
    str_remove_all("[.']") |>
    str_replace_all("-", " ") |>
    str_remove("\\s+(jr|sr|ii|iii|iv)$") |>
    str_squish()
}

# Players whose names differ entirely between the two pages
name_fix <- c("gregory jackson"    = "gg jackson",
              "hugo gonzalez pena" = "hugo gonzalez")

# Traded players: keep the combined row (2TM/3TM/4TM)
adv <- adv_raw |>
  filter(Player != "League Average") |>
  mutate(total_row = grepl("TM$", Team)) |>
  group_by(Player) |>
  filter(if (any(total_row)) total_row else TRUE) |>
  ungroup() |>
  transmute(player = Player, key = name_key(Player), age = Age, pos = Pos,
            team = Team, g = G, mp = MP, ws = WS, vorp = VORP)

# Players listed by more than one team: keep the larger salary
# NA salaries are two-way contracts, which the salary tables don't report
sal <- salary_raw |>
  mutate(salary = parse_number(salary),
         key    = name_key(player),
         key    = coalesce(unname(name_fix[key]), key)) |>
  filter(!is.na(salary)) |>
  group_by(key) |>
  summarise(salary = max(salary), .groups = "drop")

# Merge; drop players under 1,000 minutes (ratios are noisy for them)
nba <- adv |>
  inner_join(sal, by = "key") |>
  filter(mp >= 1000) |>
  mutate(salary_m = salary / 1e6,
         ws_per_m = ws / salary_m) |>
  select(-key)

write_csv(nba, here("data", "processed", paste0("nba_", season, ".csv")))

# Checks
nrow(nba)
adv |> filter(mp >= 1000) |> anti_join(sal, by = "key") |> select(player, team, mp)
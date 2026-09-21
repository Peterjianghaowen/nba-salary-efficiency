
# Scrape 2025-26 advanced stats and team salaries from Basketball-Reference
# robots.txt: Crawl-delay 3; site limit: 20 requests/min -> sleep 4s between requests


library(rvest)
library(readr)
library(here)

season   <- 2026  # 2025-26 season
base_url <- "https://www.basketball-reference.com"

# 1. Check robots.txt before scraping
robots <- readLines(paste0(base_url, "/robots.txt"))
print(robots)

# 2. Advanced stats: one page covers every player
adv_url  <- paste0(base_url, "/leagues/NBA_", season, "_advanced.html")
adv_page <- read_html(adv_url)
adv_raw  <- adv_page |> html_element("table") |> html_table()

write_csv(adv_raw, here("data", "raw", paste0("advanced_", season, ".csv")))
dim(adv_raw)
head(adv_raw)
# 3. Team salaries (table is inside an HTML comment on team pages)
scrape_team_salary <- function(team) {
  url  <- paste0(base_url, "/teams/", team, "/", season, ".html")
  page <- read_html(url)
  tbl  <- page |> html_element("table#salaries2")
  if (inherits(tbl, "xml_missing")) {
    comments <- page |> html_elements(xpath = "//comment()") |> html_text()
    sal_html <- comments[grepl('id="salaries2"', comments)]
    if (length(sal_html) == 0) return(NULL)
    tbl <- read_html(sal_html[1]) |> html_element("table#salaries2")
  }
  out <- html_table(tbl)[, 1:3]
  names(out) <- c("rk", "player", "salary")
  out$team <- team
  out
}

teams <- c("ATL", "BOS", "BRK", "CHO", "CHI", "CLE", "DAL", "DEN", "DET", "GSW",
           "HOU", "IND", "LAC", "LAL", "MEM", "MIA", "MIL", "MIN", "NOP", "NYK",
           "OKC", "ORL", "PHI", "PHO", "POR", "SAC", "SAS", "TOR", "UTA", "WAS")

salary_list <- list()
for (tm in teams) {
  message("Scraping ", tm)
  salary_list[[tm]] <- tryCatch(scrape_team_salary(tm), error = function(e) NULL)
  Sys.sleep(4)
}

salary_raw <- do.call(rbind, salary_list)
write_csv(salary_raw, here("data", "raw", paste0("salaries_", season, ".csv")))

nrow(salary_raw)
table(salary_raw$team)
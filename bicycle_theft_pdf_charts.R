knitr::opts_chunk$set(message = TRUE, warning = TRUE)

## ============================================================
## Bicycle Theft Spatial Risk Prediction — R code for every chart
## that actually appears in the PDF (Bicycle_Theft_Spatial_Risk_Prediction_v4.pdf)
##
## This is a faithful R translation of the Python/matplotlib pipeline that
## produced the PDF (loocv_models.py + chart_p1_heatmap.py + chart_p1_top10.py +
## chart_p2_ranking.py + chart_p3_theta.py + chart_p3_surface.py + chart_p4_seasonal.py).
## Same 9-candidate-model LOOCV comparison, same theta grid, strict kriging
## LOOCV with fold-local variogram fitting, same colors (Nexus palette), same chart layouts.
##
## Run with:  Rscript bicycle_theft_pdf_charts.R
## Requires bicycle.csv in the working directory (or edit `data_path` below).
## ============================================================

load_packages <- function(pkgs) {
  missing_pkgs <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing_pkgs) > 0) install.packages(missing_pkgs, repos = "https://cloud.r-project.org")
  invisible(lapply(pkgs, library, character.only = TRUE))
}
load_packages(c("tidyverse", "sf", "fields", "gstat", "sp", "viridis", "scales", "patchwork", "ggmap"))

set.seed(42)

data_path <- if (file.exists("bicycle.csv")) {
  "bicycle.csv"
} else {
  "/Users/jingnan/Downloads/four_dataset/bicycle.csv"
}

if (!file.exists(data_path)) {
  stop("Could not find bicycle.csv. Put it in the working directory or update data_path.", call. = FALSE)
}

df <- read.csv(data_path) %>%
  filter(!is.na(neighborhood), !is.na(long), !is.na(lat))

dir.create("figures", showWarnings = FALSE, recursive = TRUE)


## Nexus palette (matches the PDF's colors exactly)
TEAL       <- "#01696F"
TEAL_LIGHT <- "#20808D"
TEAL_DARK  <- "#0C4E54"
TEXT       <- "#28251D"
MUTED      <- "#7A7974"
BORDER     <- "#D4D1CA"
GRAY       <- "#BAB9B4"
GOLD       <- "#D19900"
RUST       <- "#A84B2F"




## ============================================================
## 1. Neighborhood-level aggregation to 140 centroids (UTM km)
## ============================================================
agg <- df %>%
  group_by(neighborhood, long, lat) %>%
  summarise(count = n(), .groups = "drop")

stopifnot(nrow(agg) == 140)

agg_sf <- st_as_sf(agg, coords = c("long", "lat"), crs = 4326, remove = FALSE) %>%
  st_transform(32617)   # UTM zone 17N (Toronto), meters

utm <- st_coordinates(agg_sf)
agg$x <- utm[, 1] / 1000   # km
agg$y <- utm[, 2] / 1000   # km

y_all  <- log1p(agg$count)          # target: log(theft_count + 1)
coords <- as.matrix(agg[, c("x", "y")])
n      <- nrow(agg)

rmse_fn <- function(a, b) sqrt(mean((a - b)^2))
mae_fn  <- function(a, b) mean(abs(a - b))


## ============================================================
## 2. Mean Baseline — LOOCV
## ============================================================
preds <- numeric(n)
for (i in 1:n) preds[i] <- mean(y_all[-i])
rmse_baseline <- rmse_fn(y_all, preds)
mae_baseline  <- mae_fn(y_all, preds)


## ============================================================
## 3. Linear Regression with spatial basis (x, y, x^2, y^2, x*y) — LOOCV
## ============================================================
basis_df <- agg %>% mutate(x2 = x^2, y2 = y^2, xy = x * y, log_count = y_all)

preds <- numeric(n)
for (i in 1:n) {
  fit <- lm(log_count ~ x + y + x2 + y2 + xy, data = basis_df[-i, ])
  preds[i] <- predict(fit, newdata = basis_df[i, ])
}
rmse_lm <- rmse_fn(y_all, preds)
mae_lm  <- mae_fn(y_all, preds)


## ============================================================
## 4. IDW theta = 1..5 — LOOCV
## ============================================================
D_full <- rdist(coords)   # n x n distance matrix

idw_loocv <- function(theta) {
  preds <- numeric(n)
  for (i in 1:n) {
    d <- D_full[i, -i]
    d[d == 0] <- 1e-6
    w <- 1 / (d ^ theta)
    preds[i] <- sum(w * y_all[-i]) / sum(w)
  }
  preds
}

idw_rmse <- list(); idw_mae <- list()
for (theta in 1:5) {
  p <- idw_loocv(theta)
  idw_rmse[[as.character(theta)]] <- rmse_fn(y_all, p)
  idw_mae[[as.character(theta)]]  <- mae_fn(y_all, p)
}


## ============================================================
## 5. Ordinary Kriging — Spherical / Exponential — strict LOOCV
##    The variogram is refit inside each held-out fold to avoid using the
##    test point's response when estimating the spatial covariance structure.
## ============================================================
sp_data <- agg
coordinates(sp_data) <- ~ x + y

krige_loocv_rmse <- function(vgm_model_code) {
  preds <- rep(NA_real_, n)
  ranges <- rep(NA_real_, n)

  for (i in seq_len(n)) {
    train_sp <- sp_data[-i, ]
    test_sp  <- sp_data[i, ]

    v_emp <- tryCatch(variogram(count_log ~ 1, train_sp), error = function(e) NULL)
    if (is.null(v_emp) || nrow(v_emp) == 0) next

    train_var <- var(train_sp$count_log, na.rm = TRUE)
    init_model <- vgm(
      psill = train_var * 0.8,
      model = vgm_model_code,
      range = max(spDists(train_sp)) / 3,
      nugget = train_var * 0.2
    )

    v_fit <- tryCatch(
      suppressWarnings(fit.variogram(v_emp, model = init_model)),
      error = function(e) NULL
    )
    if (is.null(v_fit) || anyNA(v_fit$psill) || anyNA(v_fit$range)) next

    pred_i <- tryCatch(
      suppressMessages(
        suppressWarnings(krige(count_log ~ 1, train_sp, test_sp, model = v_fit)$var1.pred[1])
      ),
      error = function(e) NA_real_
    )
    preds[i] <- pred_i
    ranges[i] <- v_fit$range[2]
  }

  list(
    rmse  = rmse_fn(y_all, preds),
    mae   = mae_fn(y_all, preds),
    range = median(ranges, na.rm = TRUE)
  )
}

sp_data$count_log <- y_all

krige_sph <- krige_loocv_rmse("Sph")   # Spherical
krige_exp <- krige_loocv_rmse("Exp")   # Exponential


## ============================================================
## 6. Assemble the 9-candidate-model ranking table
## ============================================================
results <- tibble(
  model = c(
    "Mean Baseline",
    "Linear Regression",
    paste0("IDW (theta=", 1:5, ")"),
    "Kriging (Spherical)",
    "Kriging (Exponential)"
  ),
  rmse = c(
    rmse_baseline,
    rmse_lm,
    unlist(idw_rmse),
    krige_sph$rmse,
    krige_exp$rmse
  ),
  mae = c(
    mae_baseline,
    mae_lm,
    unlist(idw_mae),
    krige_sph$mae,
    krige_exp$mae
  ),
  group = c("baseline", "regression", rep("idw", 5), "kriging", "kriging")
) %>%
  arrange(rmse)

cat("=== LOOCV RANKING (best to worst) ===\n")
print(results, n = Inf)


## ============================================================
## 7. Page 1 (left): Spatial heatmap with Stadia Maps basemap
## ============================================================
stadia_maps_key <- Sys.getenv("STADIA_MAPS_KEY")
if (stadia_maps_key == "") {
  stop(
    "STADIA_MAPS_KEY is not set. Please add it to ~/.Renviron before running this script.",
    call. = FALSE
  )
}

register_stadiamaps(key = stadia_maps_key, write = FALSE)

toronto_bbox <- c(
  left   = min(df$long) - 0.02,
  bottom = min(df$lat) - 0.02,
  right  = max(df$long) + 0.02,
  top    = max(df$lat) + 0.02
)

map_background <- tryCatch(
  get_stadiamap(
    bbox = toronto_bbox,
    zoom = 11,
    maptype = "stamen_toner_lite"
  ),
  error = function(e) {
    stop(
      "Stadia Maps basemap could not be downloaded. ",
      "Please check the API key, internet connection, and bbox/zoom settings. ",
      "Original error: ", conditionMessage(e),
      call. = FALSE
    )
  }
)

p_heatmap <- ggmap(map_background) +
  stat_bin2d(
    data = df,
    aes(x = long, y = lat, fill = after_stat(count)),
    bins = 45,
    alpha = 0.85
  ) +
  scale_fill_viridis_c(option = "plasma", name = "Number of\nIncidents") +
  coord_quickmap(
    xlim = toronto_bbox[c("left", "right")],
    ylim = toronto_bbox[c("bottom", "top")]
  ) +
  labs(
    title = "Spatial Distribution of Bike Theft Incidents",
    subtitle = "Each grid cell represents the count of thefts in that area",
    x = "Longitude", y = "Latitude"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5, size = 13, color = TEXT),
    plot.subtitle = element_text(hjust = 0.5, size = 9, color = MUTED),
    panel.grid = element_blank(),
    axis.text = element_text(color = TEXT),
    axis.title = element_text(color = TEXT)
  )

print(p_heatmap)
ggsave("figures/heatmap.pdf", p_heatmap, width = 6.2, height = 5.6, dpi = 200, device = "pdf")


## ============================================================
## 8. Page 1 (right): Top 10 high-risk neighborhoods bar chart
##    (matches chart_p1_top10.py: top-3 highlighted teal shades, rest gray)
## ============================================================
top10 <- df %>%
  count(neighborhood, sort = TRUE) %>%
  slice_head(n = 10) %>%
  arrange(n) %>%
  mutate(
    neighborhood = fct_reorder(neighborhood, n),
    rank_from_top = 10 - row_number(),
    bar_color = case_when(
      rank_from_top == 0 ~ TEAL,
      rank_from_top == 1 ~ TEAL_LIGHT,
      rank_from_top == 2 ~ "#5BA3AC",
      TRUE ~ GRAY
    )
  )

p_top10 <- ggplot(top10, aes(x = neighborhood, y = n, fill = bar_color)) +
  geom_col(width = 0.65) +
  geom_text(aes(label = comma(n)), hjust = -0.15, size = 3.4, fontface = "bold", color = TEXT) +
  scale_fill_identity() +
  coord_flip() +
  labs(
    title = "Top 10 High-Risk Neighborhoods",
    subtitle = "Top 10 Neighborhood Theft Counts (2014-2023)",
    x = NULL, y = "Theft Incidents"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5, size = 13, color = TEXT),
    plot.subtitle = element_text(hjust = 0.5, size = 9, color = MUTED),
    axis.text = element_text(color = TEXT, size = 9),
    panel.grid.major.y = element_blank()
  ) +
  expand_limits(y = max(top10$n) * 1.18)

print(p_top10)
ggsave("figures/top10_barchart.pdf", p_top10, width = 6.2, height = 5.6, dpi = 200, device = "pdf")


## ============================================================
## 9. Page 2: LOOCV Model Ranking — 9 candidate models
##    Kriging values use strict LOOCV, refitting the variogram inside each fold;
##    top-2 highlighted dark teal.
## ============================================================
ranked_9 <- results %>%
  arrange(desc(rmse)) %>%          # worst at top -> best at bottom for coord_flip
  mutate(model = factor(model, levels = model))

n_models <- nrow(ranked_9)
color_map <- c(baseline = GRAY, regression = "#8C8A82", idw = TEAL_LIGHT, kriging = RUST)
bar_colors <- color_map[ranked_9$group]
bar_colors[n_models]     <- TEAL       # best model
bar_colors[n_models - 1] <- TEAL_DARK  # second-best model

p_ranking <- ggplot(ranked_9, aes(x = model, y = rmse)) +
  geom_col(fill = bar_colors, width = 0.62) +
  geom_text(aes(label = sprintf("%.3f", rmse)), hjust = -0.15, size = 3.3,
            color = TEXT, fontface = "bold") +
  coord_flip() +
  labs(
    title = "LOOCV Model Ranking - 9 Candidate Models",
    x = NULL, y = "Strict LOOCV RMSE  (log(theft_count + 1), lower is better)"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5, size = 13.5, color = TEXT),
    axis.text = element_text(color = TEXT),
    panel.grid.major.y = element_blank()
  ) +
  expand_limits(y = max(ranked_9$rmse) * 1.14)

print(p_ranking)
ggsave("figures/loocv_ranking.pdf", p_ranking, width = 9.6, height = 4.6, dpi = 200, device = "pdf")


## ============================================================
## 10. Page 3 (left): IDW theta sensitivity line chart
##     (matches chart_p3_theta.py: gold circle marks the optimum)
## ============================================================
theta_df <- tibble(theta = 1:5, rmse = unlist(idw_rmse))
best_theta <- theta_df$theta[which.min(theta_df$rmse)]
best_rmse  <- min(theta_df$rmse)

p_theta <- ggplot(theta_df, aes(x = theta, y = rmse)) +
  geom_line(color = TEAL, linewidth = 1) +
  geom_point(color = TEAL, size = 2.8) +
  geom_point(data = filter(theta_df, theta == best_theta),
             shape = 21, size = 6, color = GOLD, stroke = 1.3, fill = NA) +
  geom_text(data = filter(theta_df, theta == best_theta),
            aes(label = paste0("theta=", best_theta, " optimal\nRMSE=", sprintf("%.3f", best_rmse))),
            hjust = -0.1, vjust = -0.3, size = 3.2, fontface = "bold", color = TEXT) +
  geom_text(data = filter(theta_df, theta != best_theta),
            aes(label = sprintf("%.3f", rmse)), vjust = -1, size = 3, color = MUTED) +
  scale_x_continuous(breaks = 1:5) +
  labs(
    title = "IDW Parameter Sensitivity (LOOCV Tuning)",
    x = "IDW power parameter theta", y = "LOOCV RMSE"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5, size = 12, color = TEXT),
    axis.text = element_text(color = TEXT),
    panel.grid.minor = element_blank()
  )

print(p_theta)
ggsave("figures/idw_theta_sensitivity.pdf", p_theta, width = 5.6, height = 3.9, dpi = 200, device = "pdf")


## ============================================================
## 11. Page 3 (middle + right): IDW predicted risk surface +
##     empirical uncertainty surface (theta = best_theta)
##     (matches chart_p3_surface.py)
## ============================================================
idw_predict_grid <- function(train_coords, train_values, grid_coords, theta) {
  D <- rdist(grid_coords, train_coords)
  D[D == 0] <- 1e-6
  W <- 1 / (D ^ theta)
  as.numeric((W %*% train_values) / rowSums(W))
}

pad <- 3.0
gx <- seq(min(coords[, 1]) - pad, max(coords[, 1]) + pad, length.out = 160)
gy <- seq(min(coords[, 2]) - pad, max(coords[, 2]) + pad, length.out = 160)
grid_xy <- as.matrix(expand.grid(x = gx, y = gy))

z_log   <- idw_predict_grid(coords, y_all, grid_xy, best_theta)
z_count <- expm1(z_log)

## LOOCV squared error per point, then interpolate (theta=2, smoother) as uncertainty surface
loocv_pred <- idw_loocv(best_theta)
sq_err <- (loocv_pred - y_all)^2
unc <- idw_predict_grid(coords, sq_err, grid_xy, theta = 2)

grid_df <- tibble(x = grid_xy[, 1], y = grid_xy[, 2], pred_count = z_count, uncertainty = unc)

p_idw_risk <- ggplot(grid_df, aes(x = x, y = y, fill = pred_count)) +
  geom_raster(interpolate = TRUE) +
  geom_point(data = agg, aes(x = x, y = y), inherit.aes = FALSE,
             color = "white", size = 0.6, alpha = 0.55) +
  scale_fill_viridis_c(option = "inferno", name = "Predicted\nTheft Count",
                        limits = c(0, quantile(grid_df$pred_count, 0.99)), oob = scales::squish) +
  coord_fixed(expand = FALSE) +
  labs(
    title = "IDW Predicted Bike Theft Risk Surface",
    subtitle = paste0("Prediction target: log(theft_count+1), theta=", best_theta,
                       ", LOOCV RMSE=", sprintf("%.3f", best_rmse)),
    x = "UTM Easting (km)", y = "UTM Northing (km)"
  ) +
  theme_minimal(base_size = 10) +
  theme(
    plot.title = element_text(face = "bold", size = 11, color = TEXT),
    plot.subtitle = element_text(size = 8, color = MUTED),
    panel.grid.minor = element_blank()
  )

p_idw_uncertainty <- ggplot(grid_df, aes(x = x, y = y, fill = uncertainty)) +
  geom_raster(interpolate = TRUE) +
  geom_point(data = agg, aes(x = x, y = y), inherit.aes = FALSE,
             color = "white", size = 0.6, alpha = 0.55) +
  scale_fill_viridis_c(option = "cividis", name = "LOOCV\nSquared Error") +
  coord_fixed(expand = FALSE) +
  labs(
    title = "IDW Empirical Prediction Uncertainty",
    subtitle = "Uncertainty approximated by interpolated LOOCV squared errors",
    x = "UTM Easting (km)", y = "UTM Northing (km)"
  ) +
  theme_minimal(base_size = 10) +
  theme(
    plot.title = element_text(face = "bold", size = 11, color = TEXT),
    plot.subtitle = element_text(size = 8, color = MUTED),
    panel.grid.minor = element_blank()
  )

print(p_idw_risk); print(p_idw_uncertainty)
ggsave("figures/p_idw_risk_solo.pdf", p_idw_risk, width = 5.4, height = 4.9, dpi = 200, device = "pdf")
ggsave("figures/p_idw_uncertainty_solo.pdf", p_idw_uncertainty, width = 5.4, height = 4.9, dpi = 200, device = "pdf")
ggsave("figures/p_idw_risk.pdf", p_idw_risk + p_idw_uncertainty, width = 11.4, height = 5.0, dpi = 200, device = "pdf")


## ============================================================
## 12. Page 4: Seasonal (Q1-Q4) IDW risk surface facets
##     (matches chart_p4_seasonal.py: theta=3 fit independently per quarter)
## ============================================================
## The 'quarter' column already holds the quarter-start date (e.g. "2014-01-01"),
## matching the Python original's `pd.to_datetime(df['quarter']).dt.quarter`.
df_q <- df %>%
  mutate(quarter_num = as.integer(format(as.Date(quarter), "%m")) %/% 3 + 1)

seasonal_list <- list()
vmax_list <- c()

for (q in 1:4) {
  sub <- df_q %>% filter(quarter_num == q)
  agg_q <- sub %>% group_by(neighborhood, long, lat) %>% summarise(count = n(), .groups = "drop")

  agg_q_sf <- st_as_sf(agg_q, coords = c("long", "lat"), crs = 4326, remove = FALSE) %>% st_transform(32617)
  utm_q <- st_coordinates(agg_q_sf)
  agg_q$x <- utm_q[, 1] / 1000
  agg_q$y <- utm_q[, 2] / 1000

  coords_q <- as.matrix(agg_q[, c("x", "y")])
  y_q <- log1p(agg_q$count)

  gx_q <- seq(min(coords_q[, 1]) - pad, max(coords_q[, 1]) + pad, length.out = 140)
  gy_q <- seq(min(coords_q[, 2]) - pad, max(coords_q[, 2]) + pad, length.out = 140)
  grid_q <- as.matrix(expand.grid(x = gx_q, y = gy_q))

  z_log_q <- idw_predict_grid(coords_q, y_q, grid_q, theta = 3)
  z_q <- expm1(z_log_q)

  seasonal_list[[q]] <- tibble(x = grid_q[, 1], y = grid_q[, 2], pred_count = z_q,
                                quarter = paste0("Q", q))
  vmax_list <- c(vmax_list, z_q)
}

vmax <- quantile(vmax_list, 0.98)
seasonal_grid <- bind_rows(seasonal_list) %>%
  mutate(quarter = factor(quarter, levels = c("Q1", "Q2", "Q3", "Q4")))

p_seasonal <- ggplot(seasonal_grid, aes(x = x, y = y, fill = pred_count)) +
  geom_raster(interpolate = TRUE) +
  scale_fill_viridis_c(option = "inferno", name = "Predicted\nTheft Count",
                        limits = c(0, vmax), oob = scales::squish) +
  facet_wrap(~ quarter, nrow = 2) +
  coord_fixed(expand = FALSE) +
  labs(
    title = "Seasonal Variation of IDW Predicted Theft Risk",
    subtitle = "Q1-Q4 risk surfaces, IDW theta=3 (fit per quarter)",
    x = "UTM Easting (km)", y = "UTM Northing (km)"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5, size = 13, color = TEXT),
    plot.subtitle = element_text(hjust = 0.5, size = 9, color = MUTED),
    strip.text = element_text(face = "bold", size = 11, color = TEXT),
    strip.background = element_rect(fill = "gray95", color = NA),
    panel.grid = element_blank()
  )

print(p_seasonal)
ggsave("figures/seasonal_idw.pdf", p_seasonal, width = 9.6, height = 8.6, dpi = 200, device = "pdf")


## ============================================================
## 13. Save results table
## ============================================================
write.csv(results, "loocv_ranking_9_models.csv", row.names = FALSE)

cat("\n================ DONE ================\n")
cat("All PDF figures written to ./figures/\n")
print(results, n = Inf)

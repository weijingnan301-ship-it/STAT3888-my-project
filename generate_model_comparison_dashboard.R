library(DT)
library(dplyr)
library(ggplot2)
library(htmltools)
library(htmlwidgets)
library(plotly)

idw_results <- tibble::tibble(
  theta = c(1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5, 6),
  rmse = c(
    0.9771498687, 0.8484887511, 0.7532730983, 0.7045859676,
    0.6898319585, 0.6914211145, 0.6988309708, 0.7075855214,
    0.7160651056, 0.7237560641, 0.7305510354
  )
) %>%
  mutate(
    best = rmse == min(rmse),
    label = paste0("theta = ", theta, "<br>LOOCV tuning RMSE = ", round(rmse, 4))
  )

p_tuning <- ggplot(
  idw_results,
  aes(x = theta, y = rmse, text = label)
) +
  geom_line(color = "#2563EB", linewidth = 1.2) +
  geom_point(size = 3, color = "#2563EB") +
  geom_point(
    data = filter(idw_results, best),
    aes(x = theta, y = rmse, text = label),
    color = "#DC2626",
    size = 4,
    inherit.aes = FALSE
  ) +
  geom_text(
    data = filter(idw_results, best),
    aes(x = theta, y = rmse, label = paste0("Best theta = ", theta)),
    vjust = -1,
    color = "#DC2626",
    fontface = "bold",
    size = 4,
    inherit.aes = FALSE
  ) +
  labs(
    title = "Interactive Parameter Tuning Plot",
    subtitle = "IDW theta selection; lower LOOCV RMSE is better",
    x = "IDW Power Parameter theta",
    y = "LOOCV RMSE"
  ) +
  theme_minimal(base_size = 13) +
  theme(
    plot.title = element_text(face = "bold"),
    plot.subtitle = element_text(color = "gray35"),
    panel.grid.minor = element_blank()
  )

interactive_tuning <- plotly::ggplotly(p_tuning, tooltip = "text")

model_table <- tibble::tibble(
  Model = c(
    "Kriging Spherical",
    "Kriging Exponential",
    "IDW (theta = 3)",
    "Linear Regression",
    "Mean Baseline"
  ),
  `Prediction Target` = rep("log(theft_count + 1)", 5),
  `Strict LOOCV RMSE` = c(0.6875, 0.6896, 0.6898, 0.8513, 1.2111),
  `Key Parameters` = c(
    "Spherical variogram refit per fold",
    "Exponential variogram refit per fold",
    "theta = 3 selected by LOOCV tuning",
    "x, y, x^2, y^2, xy",
    "Global mean"
  )
) %>%
  arrange(`Strict LOOCV RMSE`) %>%
  mutate(Rank = row_number()) %>%
  select(Rank, Model, `Prediction Target`, `Strict LOOCV RMSE`, `Key Parameters`)

model_table_html <- datatable(
  model_table,
  rownames = FALSE,
  options = list(
    pageLength = 5,
    dom = "t",
    ordering = TRUE,
    columnDefs = list(list(className = "dt-center", targets = c(0, 3)))
  ),
  caption = htmltools::tags$caption(
    style = "caption-side: top; text-align: left; font-weight: bold; font-size: 18px;",
    "Model Comparison Table: Strict LOOCV Performance"
  )
) %>%
  formatStyle(
    "Rank",
    backgroundColor = styleEqual(
      c(1, 2, 3, 4, 5),
      c("#DCFCE7", "#E0F2FE", "#EFF6FF", "#FEF3C7", "#FEE2E2")
    ),
    fontWeight = "bold"
  ) %>%
  formatStyle(
    "Strict LOOCV RMSE",
    fontWeight = "bold",
    color = "#111827"
  )

dashboard <- tagList(
  tags$head(
    tags$title("Bike Theft Model Comparison Dashboard"),
    tags$style(HTML("
      body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        background: #F8FAFC;
        margin: 0;
        padding: 28px;
        color: #111827;
      }
      .header { margin-bottom: 22px; }
      .header h1 {
        margin: 0;
        font-size: 30px;
        font-weight: 800;
        color: #1F2937;
      }
      .header p {
        margin-top: 8px;
        color: #4B5563;
        font-size: 15px;
      }
      .grid {
        display: grid;
        grid-template-columns: 48% 52%;
        gap: 22px;
        align-items: start;
      }
      .card {
        background: white;
        border: 1px solid #E5E7EB;
        border-radius: 10px;
        padding: 18px;
        box-shadow: 0 8px 22px rgba(15, 23, 42, 0.06);
      }
      .note {
        margin-top: 18px;
        padding: 14px 16px;
        border-left: 4px solid #2563EB;
        background: #EFF6FF;
        color: #1E3A8A;
        font-size: 14px;
      }
    "))
  ),
  div(
    class = "header",
    h1("Bike Theft Spatial Prediction: Model Comparison"),
    p("All models predict log(theft_count + 1). Kriging scores use strict LOOCV: the variogram is refit inside each held-out fold.")
  ),
  div(
    class = "grid",
    div(class = "card", interactive_tuning),
    div(class = "card", model_table_html)
  ),
  div(
    class = "note",
    strong("Interpretation: "),
    "Spherical kriging and IDW theta = 3 are effectively tied. IDW remains the operational choice because it is stable, transparent, and avoids fold-to-fold variogram fitting. ",
    "The IDW theta curve is used for tuning, so it should not be described as an independent future-test estimate."
  )
)

save_html(
  dashboard,
  file = "bike_theft_model_comparison_dashboard.html",
  libdir = "bike_theft_model_comparison_dashboard_files"
)

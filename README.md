# Toronto Bike Theft Spatial Analysis — Project Files

---

## 📊 Full Method Comparison: IDW vs. Ordinary Kriging

| Aspect | IDW | Ordinary Kriging | Why IDW is Selected |
| :--- | :--- | :--- | :--- |
| Core Idea | Closer points receive larger weights | Models spatial structure first, then performs optimal linear prediction | IDW is intuitive and easy to explain in a 4‑slide PPT |
| Semivariogram Required | No | Yes, needs to fit a semivariogram | This project focuses on prediction mapping and model comparison; IDW reduces extra assumptions |
| Parameters | Power parameter θ | Nugget, sill, range, variogram model | IDW has only one main parameter (θ), easy to tune via LOOCV |
| Interpretability | High: larger θ means stronger influence from nearby points | Medium‑high: more professional but conceptually heavier | Reviewers can quickly grasp that "nearby neighborhoods are more similar" |
| Implementation Complexity | Low | Medium‑high | IDW is more stable and less affected by unstable variogram fitting |
| Data Requirement | Low; works with limited samples | High; needs clear spatial structure | This project has only 140 centroid points, so IDW is better for small‑sample spatial prediction |
| Prediction Output | Smoothed risk surface | Smoothed risk surface + prediction variance | Strict LOOCV shows kriging and IDW are effectively tied |
| Uncertainty Representation | Cannot directly output prediction variance; LOOCV error can approximate it | Can directly output Kriging variance | Kriging can serve as a supplementary benchmark for uncertainty, but final model selection is based on RMSE |
| Computational Efficiency | Fast | Slow | IDW is suitable for rapid tuning, cross‑validation, and generating multiple versions |
| Sensitivity to Outliers | Sensitive, especially with large θ | Also sensitive, but nugget can partially mitigate | LOOCV‑based θ selection can control over‑reliance on nearest neighbors |
| Suitable Scenarios | Quick spatial interpolation, risk mapping, interpretable prediction | Rigorous geostatistical modeling, uncertainty estimation | Project goal: produce an interpretable, presentable, and verifiable bike theft risk map |
| Presentation Impact | Simple and direct | More advanced and statistical | IDW as the primary model, Kriging as a high‑level benchmark — balanced overall |

**Conclusion:** After all models were compared on the same target (`log(theft_count + 1)`), strict LOOCV gives **Spherical Kriging RMSE = 0.6875** and **IDW (theta = 3) RMSE = 0.6898**. The gap is negligible, so IDW is selected as the primary operational model because it is transparent, stable across tuning, and avoids fold-to-fold variogram fitting; kriging remains the closest benchmark and a useful uncertainty reference.


## 📁 Project Files

- [Full Comparison Table (Styled)]((https://weijingnan301-ship-it.github.io/STAT3888-my-project/comparison.html))
- [Revised 4-slide PDF](https://weijingnan301-ship-it.github.io/STAT3888-my-project/Bicycle_Theft_Spatial_Risk_Prediction_v4.pdf)
- [Notebook Code](https://weijingnan301-ship-it.github.io/STAT3888-my-project/bicycle_theft_pdf_charts.nb.html)
- [LOOCV Dashboard](https://weijingnan301-ship-it.github.io/STAT3888-my-project/bike_theft_model_comparison_dashboard.html)

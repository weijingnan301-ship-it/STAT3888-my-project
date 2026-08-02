(() => {
  'use strict';

  /* ============================================================
     THEME TOGGLE
     ============================================================ */
  const root = document.documentElement;
  const toggleBtn = document.querySelector('[data-theme-toggle]');

  function getSystemTheme() {
    return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
  }

  function applyTheme(theme) {
    root.setAttribute('data-theme', theme);
    if (toggleBtn) {
      toggleBtn.setAttribute('aria-label', theme === 'dark' ? 'Switch to light mode' : 'Switch to dark mode');
      toggleBtn.innerHTML = theme === 'dark'
        ? '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>'
        : '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>';
    }
  }

  let currentTheme = getSystemTheme();
  applyTheme(currentTheme);

  if (toggleBtn) {
    toggleBtn.addEventListener('click', () => {
      currentTheme = currentTheme === 'dark' ? 'light' : 'dark';
      applyTheme(currentTheme);
      redrawAllCharts();
    });
  }

  /* ============================================================
     SCROLL REVEAL
     ============================================================ */
  const revealEls = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window) {
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add('is-visible');
            io.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12 }
    );
    revealEls.forEach((el) => io.observe(el));
  } else {
    revealEls.forEach((el) => el.classList.add('is-visible'));
  }

  /* ============================================================
     CHART.JS SETUP
     ============================================================ */
  let DATA = null;
  const chartInstances = [];

  function css(varName) {
    return getComputedStyle(document.documentElement).getPropertyValue(varName).trim();
  }

  function chartDefaults() {
    return {
      text: css('--color-text'),
      muted: css('--color-text-muted'),
      divider: css('--color-divider'),
      primary: css('--color-primary'),
      c1: css('--color-chart-1'),
      c2: css('--color-chart-2'),
      c3: css('--color-chart-3'),
      c4: css('--color-chart-4'),
      c5: css('--color-chart-5'),
      c6: css('--color-chart-6'),
      surface: css('--color-surface'),
    };
  }

  function baseFont() {
    return { family: "'Satoshi','Helvetica Neue',sans-serif", size: 12 };
  }

  function destroyAllCharts() {
    chartInstances.forEach((c) => c.destroy());
    chartInstances.length = 0;
  }

  function redrawAllCharts() {
    destroyAllCharts();
    renderYearly();
    renderYearQuarter();
    renderMoran();
    renderTheta();
  }

  /* ---- 1. Yearly bar chart ---- */
  function renderYearly() {
    const ctx = document.getElementById('chartYearly');
    if (!ctx || !DATA) return;
    const t = chartDefaults();
    const labels = DATA.yearly.map((d) => d.year);
    const values = DATA.yearly.map((d) => d.count);

    const chart = new Chart(ctx, {
      type: 'bar',
      data: {
        labels,
        datasets: [
          {
            label: 'Incidents',
            data: values,
            backgroundColor: t.c1,
            borderRadius: 4,
            maxBarThickness: 34,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: {
              label: (item) => `${item.parsed.y.toLocaleString()} incidents`,
            },
          },
        },
        scales: {
          x: {
            grid: { display: false },
            ticks: { color: t.muted, font: baseFont() },
          },
          y: {
            beginAtZero: true,
            grid: { color: t.divider },
            ticks: { color: t.muted, font: baseFont(), callback: (v) => v.toLocaleString() },
          },
        },
      },
    });
    chartInstances.push(chart);
  }

  /* ---- 2. Year x Quarter stacked bar ---- */
  function renderYearQuarter() {
    const ctx = document.getElementById('chartYearQuarter');
    if (!ctx || !DATA) return;
    const t = chartDefaults();
    const labels = DATA.yearQuarter.map((d) => d.year);
    const qColors = [t.c4, t.c1, t.c3, t.c2];
    const qLabels = ['Q1', 'Q2', 'Q3', 'Q4'];

    const datasets = ['q1', 'q2', 'q3', 'q4'].map((key, i) => ({
      label: qLabels[i],
      data: DATA.yearQuarter.map((d) => d[key]),
      backgroundColor: qColors[i],
      borderRadius: 2,
      maxBarThickness: 28,
    }));

    const chart = new Chart(ctx, {
      type: 'bar',
      data: { labels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'bottom',
            labels: { color: t.muted, font: baseFont(), boxWidth: 10, boxHeight: 10, padding: 14 },
          },
          tooltip: {
            callbacks: { label: (item) => `${item.dataset.label}: ${item.parsed.y.toLocaleString()}` },
          },
        },
        scales: {
          x: { stacked: true, grid: { display: false }, ticks: { color: t.muted, font: baseFont() } },
          y: {
            stacked: true,
            beginAtZero: true,
            grid: { color: t.divider },
            ticks: { color: t.muted, font: baseFont(), callback: (v) => v.toLocaleString() },
          },
        },
      },
    });
    chartInstances.push(chart);
  }

  /* ---- 3. Moran scatter ---- */
  function classifyQuadrant(z, lag) {
    if (z >= 0 && lag >= 0) return 'HH';
    if (z < 0 && lag < 0) return 'LL';
    if (z >= 0 && lag < 0) return 'HL';
    return 'LH';
  }

  function renderMoran() {
    const ctx = document.getElementById('chartMoran');
    if (!ctx || !DATA) return;
    const t = chartDefaults();
    const quadColor = { HH: t.c1, LL: t.c3, HL: t.c6, LH: t.c5 };
    const quadLabel = { HH: 'High–High', LL: 'Low–Low', HL: 'High–Low', LH: 'Low–High' };

    const groups = { HH: [], LL: [], HL: [], LH: [] };
    DATA.moran.forEach((d) => {
      const q = classifyQuadrant(d.z, d.lag_z);
      groups[q].push({ x: d.z, y: d.lag_z, n: d.neighborhood });
    });

    const datasets = Object.keys(groups).map((q) => ({
      label: quadLabel[q],
      data: groups[q],
      backgroundColor: quadColor[q],
      pointRadius: 4,
      pointHoverRadius: 6,
    }));

    // simple regression line for visual reference (Moran's I slope)
    const xs = DATA.moran.map((d) => d.z);
    const ys = DATA.moran.map((d) => d.lag_z);
    const xMin = Math.min(...xs), xMax = Math.max(...xs);
    const slope = DATA.moranI;
    const lineData = [
      { x: xMin, y: slope * xMin },
      { x: xMax, y: slope * xMax },
    ];
    datasets.push({
      type: 'line',
      label: `Moran's I = ${DATA.moranI.toFixed(3)}`,
      data: lineData,
      borderColor: t.text,
      borderWidth: 1.5,
      borderDash: [4, 4],
      pointRadius: 0,
      fill: false,
    });

    const chart = new Chart(ctx, {
      type: 'scatter',
      data: { datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'bottom',
            labels: { color: t.muted, font: baseFont(), boxWidth: 10, boxHeight: 10, padding: 12 },
          },
          tooltip: {
            callbacks: {
              label: (item) => {
                if (item.dataset.label.startsWith("Moran")) return item.dataset.label;
                const p = item.raw;
                return `${p.n}: z=${p.x.toFixed(2)}, lag=${p.y.toFixed(2)}`;
              },
            },
          },
        },
        scales: {
          x: {
            title: { display: true, text: 'Standardized incident count (z)', color: t.muted, font: baseFont() },
            grid: { color: t.divider },
            ticks: { color: t.muted, font: baseFont() },
          },
          y: {
            title: { display: true, text: 'Spatial lag of z', color: t.muted, font: baseFont() },
            grid: { color: t.divider },
            ticks: { color: t.muted, font: baseFont() },
          },
        },
      },
    });
    chartInstances.push(chart);
  }

  /* ---- 4. Theta sensitivity line chart ---- */
  function renderTheta() {
    const ctx = document.getElementById('chartTheta');
    if (!ctx || !DATA) return;
    const t = chartDefaults();
    const labels = DATA.thetaGrid.map((d) => d.theta);
    const values = DATA.thetaGrid.map((d) => d.rmse);
    const bestIdx = values.indexOf(Math.min(...values));

    const pointColors = values.map((_, i) => (i === bestIdx ? t.c2 : t.c1));
    const pointRadii = values.map((_, i) => (i === bestIdx ? 6 : 3));

    const chart = new Chart(ctx, {
      type: 'line',
      data: {
        labels,
        datasets: [
          {
            label: 'LOOCV RMSE',
            data: values,
            borderColor: t.c1,
            backgroundColor: 'transparent',
            borderWidth: 2,
            tension: 0.3,
            pointBackgroundColor: pointColors,
            pointRadius: pointRadii,
            pointHoverRadius: 7,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: { display: false },
          tooltip: {
            callbacks: { label: (item) => `θ=${item.label}: RMSE=${item.parsed.y.toFixed(4)}` },
          },
        },
        scales: {
          x: {
            title: { display: true, text: 'θ (power parameter)', color: t.muted, font: baseFont() },
            grid: { display: false },
            ticks: { color: t.muted, font: baseFont() },
          },
          y: {
            title: { display: true, text: 'LOOCV RMSE', color: t.muted, font: baseFont() },
            grid: { color: t.divider },
            ticks: { color: t.muted, font: baseFont() },
          },
        },
      },
    });
    chartInstances.push(chart);
  }

  /* ---- 5. Model comparison table ---- */
  function renderTable() {
    const tbody = document.querySelector('#modelTable tbody');
    if (!tbody || !DATA) return;
    const rows = [...DATA.models].sort((a, b) => a.rmse - b.rmse);
    const best = rows[0];

    tbody.innerHTML = rows
      .map((row, i) => {
        const isBest = row.model === best.model;
        return `<tr class="${isBest ? 'is-best' : ''}">
          <td>${i + 1}</td>
          <td>${row.model}</td>
          <td><span class="tag">${row.group}</span></td>
          <td>${row.rmse.toFixed(4)}</td>
          <td>${row.mae.toFixed(4)}</td>
        </tr>`;
      })
      .join('');
  }

  /* ============================================================
     LOAD DATA + INIT
     ============================================================ */
  fetch('./assets/data.json')
    .then((res) => res.json())
    .then((json) => {
      DATA = json;
      renderYearly();
      renderYearQuarter();
      renderMoran();
      renderTheta();
      renderTable();
    })
    .catch((err) => console.error('Failed to load data.json', err));
})();

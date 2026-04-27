# Parameter-Determination & Utility Helpers

These helpers convert *user-friendly clinical inputs* (medians, response rates,
correlations, dropout rates at calendar landmarks) into the *machine-friendly
parameters* required by `endpoint()` generators, `trial(dropout = ...)`, and
the built-in correlated-endpoint generators.

**Workflow rule:** for any helper that performs a numerical search
(`solveThreeStateModel`, NORTA fitting via `simdesign_norta`), run it
**once** in a separate `Rscript` step, capture the chosen values, and
**hardcode the resolved literals** into the simulation script. The
simulation script must not contain the slow optimization itself — that
would re-run on every replicate.

---

## Distribution-Parameter Solvers

### `solveThreeStateModel(median_pfs, median_os, corr, h12 = seq(0.05, 0.2, length.out = 50))`

Convert (median PFS, median OS, target Pearson correlation) → transition hazards `(h01, h02, h12)` for `CorrelatedPfsAndOs3`. Grid-searches `h12`; returns one row per `(corr, h12)` candidate with an `error` column (smaller is better).

```r
pars <- solveThreeStateModel(
  median_pfs = 5,
  median_os  = 12,
  corr       = seq(0.55, 0.65, by = 0.05),
  h12        = seq(0.05, 0.15, length.out = 50))

best <- pars[which.min(pars$error), ]   # then hardcode best$h01, best$h02, best$h12
```

> **Slow.** Run once in a temp Rscript, present the chosen row to the user with explanation, then hardcode literals in the simulation script.
>
> **Note:** `CorrelatedPfsAndOs3` produces a time-varying OS hazard ratio between arms — incompatible with a Cox PH analysis. If the user plans Cox/log-rank, use `CorrelatedPfsAndOs2` (Gumbel copula, takes `kendall` directly — no helper needed).

---

### `solveMixtureExponentialDistribution(weight1, median1, median2 = NULL, overall_median = NULL)`

Solve for the missing piece of a two-component exponential mixture. Specify exactly one of `median2` or `overall_median`; the other is returned. Use case: **enrichment designs** where you know the overall arm median and the marker-positive subgroup median, and need the marker-negative subgroup median (or vice versa).

```r
# Marker-positive (30%) has median 10; overall median 8 → solve for marker-negative
median2 <- solveMixtureExponentialDistribution(
            weight1 = .3, median1 = 10, overall_median = 8)
# → returns the value for median2; use in a custom mixture generator
```

Custom generator pattern that consumes the result:
```r
gen_mix <- function(n, p_pos, m_pos, m_neg, ...) {
  is_pos <- runif(n) < p_pos
  data.frame(
    os       = ifelse(is_pos,
                      rexp(n, rate = log(2) / m_pos),
                      rexp(n, rate = log(2) / m_neg)),
    os_event = 1L
  )
}
ep <- endpoint(name = "os", type = "tte", generator = gen_mix,
               p_pos = 0.3, m_pos = 10, m_neg = <solved_median2>)
```

---

### `solvePiecewiseConstantExponentialDistribution(surv_prob, times)`

Convert (survival probabilities at calendar landmarks) → piecewise hazards. Returns a `data.frame(end_time, piecewise_risk)` ready to pass as the `risk` argument to `PiecewiseConstantExponentialRNG`.

```r
risk <- solvePiecewiseConstantExponentialDistribution(
          surv_prob = c(0.9, 0.75, 0.64, 0.42, 0.28),
          times     = c(0.4, 1.2, 4.0, 5.5, 9.0))

ep <- endpoint(name = "pfs", type = "tte",
               generator = PiecewiseConstantExponentialRNG,
               risk = risk, endpoint_name = "pfs")
```

When the user says *"survival is 75% at 12 months and 50% at 24 months"*, this is the helper to use rather than asking them for hazard rates.

---

### `weibullDropout(time, dropout_rate)`

Convert (dropout rates at two time points) → `(scale, shape)` for `rweibull`. Pass the result through `trial(..., dropout = rweibull, scale = ..., shape = ...)`.

```r
pars <- weibullDropout(time = c(12, 18), dropout_rate = c(0.08, 0.18))
# → c(scale = ..., shape = ...)

tr <- trial(name = "...", n_patients = 1000, duration = 36,
            enroller = StaggeredRecruiter, accrual_rate = accrual,
            dropout  = rweibull, scale = pars["scale"], shape = pars["shape"])
```

For a single landmark dropout rate, use exponential dropout instead: `dropout = rexp, rate = -log(1 - p) / t` (no helper needed).

---

### `qPiecewiseExponential(p, times, piecewise_risk)`

Quantile function of the piecewise exponential distribution. Use this **inside a NORTA marginal** when one of the correlated endpoints is piecewise exponential — `simdesign_norta()` requires a `function(p)` for each marginal:

```r
pars <- solvePiecewiseConstantExponentialDistribution(
          surv_prob = c(0.9, 0.7, 0.5),
          times     = c(6, 12, 24))

dist <- list(
  os = function(p) qPiecewiseExponential(p,
          times          = pars$end_time,
          piecewise_risk = c(pars$piecewise_risk, tail(pars$piecewise_risk, 1))),
  bm = function(p) qbinom(p, size = 1, prob = 0.6)
)
design <- simdata::simdesign_norta(cor_target_final = Sigma, dist = dist, ...)
```

For an *independent* piecewise exponential endpoint, use `PiecewiseConstantExponentialRNG` directly as the `generator` — no quantile function needed.

---

## Random Number Generation Helpers

### `StaggeredRecruiter(n, accrual_rate)`

Built-in enroller for piecewise-constant-rate recruitment. `accrual_rate` is a `data.frame(end_time, piecewise_rate)`. Pass via `...` to `trial()`:

```r
accrual <- data.frame(
  end_time       = c(6, 36, Inf),
  piecewise_rate = c(10, 20, 25))   # 10/mo for first 6, then 20/mo until 36, then 25
tr <- trial(name = "...", ..., enroller = StaggeredRecruiter, accrual_rate = accrual)
```

For uniform constant enrollment, use a single row with `end_time = Inf`.

### `rconst(n, value)`

Returns a constant vector of length `n`. Useful as a placeholder dropout `function(n, ...)` when modeling no-dropout in a trial that requires the slot, or as a degenerate baseline endpoint.

### `DynamicRNGFunction(fn, ...)`

Wraps a generator and **freezes** the supplied `...` arguments. The returned function still accepts `n` and any *unfrozen* arguments. Use this when you need to make a generator's invariant parameters tamper-proof (e.g., shared across multiple endpoint definitions):

```r
ctrl_os <- DynamicRNGFunction(rexp, rate = log(2) / 12)
ep_ctrl <- endpoint(name = "os", type = "tte", generator = ctrl_os)

# Trying to override a frozen arg errors:
# ctrl_os(n = 10, rate = 0.1)  # Error
```

---

## Output / Post-Simulation Helpers

### `summarizeMilestoneTime(output)`
Summarize triggering times of all milestones across replicates. Input is the data.frame from `controller$get_output()`. Returns a data.frame of class `milestone_time_summary` with a built-in `plot` method.

```r
out <- ctr$get_output()
mt  <- summarizeMilestoneTime(out)
mt
plot(mt)
```

### `expandRegimen(data)`
Expand the compact `regimen_trajectory` column in locked data into one row per regimen segment per patient. Adds `regimen` and `switch_time_from_enrollment` columns; drops `regimen_trajectory`. Use only when treatment switching is enabled via `add_regimen()`.

```r
locked <- trial$get_locked_data("final")
long   <- expandRegimen(locked)
```

### `summarizeDataFrame(data, ...)`
Lightweight `summarytools::dfSummary` alternative — used internally by `arm$print()` etc. End users usually don't call this directly.

---

## Decision Table: which helper for which user input?

| User says... | Helper to call | Output goes into |
|---|---|---|
| "Median PFS / OS for each arm and the correlation between them" + Cox/logrank | None — use `CorrelatedPfsAndOs2` directly with `kendall =` | `endpoint(generator = CorrelatedPfsAndOs2, median_pfs, median_os, kendall, ...)` |
| Same as above, but parametric / non-Cox analysis | `solveThreeStateModel()` (offline) | `endpoint(generator = CorrelatedPfsAndOs3, h01, h02, h12, ...)` — hardcoded |
| "Survival is X% at month T, Y% at month T'" | `solvePiecewiseConstantExponentialDistribution()` | `endpoint(generator = PiecewiseConstantExponentialRNG, risk = <solved>, ...)` |
| "Mixture: p% have median m1, overall median is m" | `solveMixtureExponentialDistribution()` | Custom mixture generator (see example above) |
| "Dropout is 8% at 12mo and 18% at 18mo" | `weibullDropout()` | `trial(dropout = rweibull, scale, shape)` |
| "Dropout is 10% by month T" | None — use `dropout = rexp, rate = -log(1-p)/T` | `trial(dropout = rexp, rate = ...)` |
| "Enroll N patients/month over the trial" | None — build an `accrual_rate` data.frame | `trial(enroller = StaggeredRecruiter, accrual_rate = ...)` |
| Correlated endpoints other than PFS/OS | None — use NORTA via `simdata::simdesign_norta()` (offline) + `qPiecewiseExponential` if piecewise marginal | Custom generator wrapping `simulate_data()` |

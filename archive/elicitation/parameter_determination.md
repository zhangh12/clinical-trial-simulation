# Parameter Determination Guide

## Goal
Bridge user-friendly clinical inputs (medians, response rates, correlations,
landmark survival/dropout probabilities) to the **machine parameters**
required by `TrialSimulator` generators and `trial()` arguments. This guide
tells the agent **when to invoke a helper function** before writing the
final simulation script.

> **Key rule:** any helper that performs a numerical search (`solveThreeStateModel`,
> NORTA fitting, optimization-based solvers) must be run **once** in a
> separate `Rscript` step. Capture the chosen values, present them to the
> user, then **hardcode the literals** in the simulation script. The
> simulation script must never re-run the optimizer per replicate.

---

## Decision Flowchart

### TTE endpoint, single distribution

```
User input                    | Action
------------------------------|-----------------------------------------------
Median + exponential          | rate = log(2) / median; generator = rexp
Median + assumed PH           | Same as above; HR scales rate per arm
Median + Weibull (shape known)| rate parameterized differently; ask for shape and use rweibull
Survival prob at 1 landmark   | rate = -log(p) / time; generator = rexp
Survival prob at K landmarks  | solvePiecewiseConstantExponentialDistribution(); generator = PiecewiseConstantExponentialRNG
Delayed treatment effect      | Piecewise risk with HR column; generator = PiecewiseConstantExponentialRNG
Crossing hazards / non-PH     | Custom generator; ask user for shape of hazard
```

### TTE endpoints — correlated PFS + OS

```
User input + analysis plan        | Helper / generator
----------------------------------|-----------------------------------------------
Medians + Kendall's tau, Cox/LR   | None — CorrelatedPfsAndOs2(median_pfs, median_os, kendall) directly
Medians + Pearson, NOT Cox/LR     | solveThreeStateModel() OFFLINE → CorrelatedPfsAndOs3(h01, h02, h12)
                                  |  (3-state model produces time-varying HR — Cox-incompatible)
+ tumor response                  | CorrelatedPfsAndOs4 with a 4x4 transition_probability matrix
                                  |  (response is TTE; wrap to convert to binary at readout if needed)
```

### Non-TTE endpoint

```
User input                          | Action
------------------------------------|-----------------------------------------------
Response rate per arm               | rbinom(n, size = 1, prob = rate)
Continuous mean ± sd                | rnorm(n, mean, sd)
Continuous + percentile reasoning   | qnorm to find sd; or wrap qXXX
Categorical with probabilities      | sample() — wrap because first arg is not n
Repeated measurements at K visits   | Custom multivariate generator (see defineLongitudinalEndpoints vignette pattern)
```

### Mixture / enrichment

```
User input                                         | Helper
---------------------------------------------------|-----------------------------------------------
Marker-pos prevalence p, marker-pos median m1,     | solveMixtureExponentialDistribution(weight1=p, median1=m1, overall_median=m)
overall median m → solve for marker-neg median m2  |  → returns m2; use in custom mixture generator
Same but knows m2, wants overall                   | solveMixtureExponentialDistribution(weight1=p, median1=m1, median2=m2)
                                                   |  → returns overall_median
```

### Correlated endpoints — anything other than PFS/OS

```
User input                                    | Action
----------------------------------------------|-----------------------------------------------
Mixed types (TTE + binary + continuous + ...) | NORTA: simdata::simdesign_norta(dist, cor_target_final)
                                              |  Build dist as list of quantile functions per marginal
                                              |  Build the design ONCE outside the generator (it runs optimization)
                                              |  Custom generator wraps simulate_data(); add <name>_event = 1L per TTE
TTE marginal is piecewise exponential         | Use qPiecewiseExponential() inside the dist list
NORTA correlation target infeasible           | simdesign_norta() will error → tell user to relax target or change marginals
```

### Dropout

```
User input                          | Action / Helper
------------------------------------|-----------------------------------------------
None                                | Omit dropout in trial()
P% by month T (single landmark)     | dropout = rexp, rate = -log(1 - P) / T
P1% at T1 and P2% at T2 (two)       | weibullDropout(time = c(T1, T2), dropout_rate = c(P1, P2)) → scale & shape
                                    |  → trial(dropout = rweibull, scale = ..., shape = ...)
Custom dropout function             | Confirm first arg is n; pass as dropout = my_fn with extra args via ...
```

### Enroller / accrual

```
User input                          | Action
------------------------------------|-----------------------------------------------
N patients/period, constant         | accrual_rate = data.frame(end_time = Inf, piecewise_rate = N)
Ramp-up                             | Multiple rows in accrual_rate (last row should usually have end_time = Inf)
50% of N by month T                 | Compute rate per phase; build accrual_rate
Total N over T months, ramped       | Solve for piecewise rates such that integral = N
```

---

## Two-Step Workflow for Slow Helpers

### Pattern: `solveThreeStateModel`

**Step 1 — Agent runs once before writing the simulation script:**

```r
# /tmp/solve_3state.R
library(TrialSimulator)
pars <- solveThreeStateModel(
  median_pfs = <m_pfs>,
  median_os  = <m_os>,
  corr       = seq(<target> - 0.05, <target> + 0.05, by = 0.01),
  h12        = seq(0.01, 0.50, length.out = 100))
best <- pars[which.min(pars$error), ]
print(best)
```

Run with `Rscript /tmp/solve_3state.R 2>&1`. Repeat for each arm if medians differ. Show the result to the user with explanation:
- `h01` — stable → progression rate
- `h02` — direct death rate from stable
- `h12` — death rate after progression
- `corr` — Pearson correlation achieved

**Step 2 — Hardcode resolved literals into the simulation script:**

```r
ep_ctrl <- endpoint(name = c("pfs","os"), type = c("tte","tte"),
                    generator = CorrelatedPfsAndOs3,
                    h01 = 0.075, h02 = 0.024, h12 = 0.090)   # literals
```

The simulation script never contains `solveThreeStateModel()`.

---

### Pattern: `simdesign_norta` for arbitrary correlated endpoints

**Step 1 — Build the design ONCE outside the generator:**

```r
Sigma <- matrix(c(1.00, 0.30, ...), nrow = K)

dist <- list(
  os        = function(p) qexp(p, rate = log(2) / 12),
  secondary = function(p) qnorm(p, mean = 1.5, sd = 0.4),
  bm        = function(p) qbinom(p, size = 1, prob = 0.6))

design <- simdata::simdesign_norta(dist = dist, cor_target_final = Sigma)
```

`design` lives in the script's global scope. The generator captures it via
closure — the optimization runs once, not per replicate.

**Step 2 — Custom generator uses the prebuilt design:**

```r
gen_norta <- function(n, ...) {
  df <- as.data.frame(simulate_data(generator = design, n = n))
  colnames(df) <- c("os", "secondary", "bm")
  df$os_event  <- 1L                # add event indicator for each TTE
  df
}
```

**Step 3 — Validate empirical correlation** (see `validation/validate.md` NORTA section).

---

## Pre-Trial Planning: estimate milestone trigger time

When the user is unsure whether their event-count trigger will fire within `duration`, run a **dry-run simulation** with `controller$run(dry_run = TRUE, n = 50)`. The default action only locks data and saves milestone time / event counts (no statistical analysis). Then summarize:

```r
ctr$run(n = 50, dry_run = TRUE, plot_event = FALSE, silent = TRUE)
out <- ctr$get_output()
summarizeMilestoneTime(out)   # returns a data.frame; plot() shows distributions
```

This is the recommended way to choose final `duration` and to verify that `eventNumber()` triggers fire in the expected window. **Do not include the dry-run code in the final script delivered to the user.**

---

## Notes for Agent

- Always **show the user** the result of any helper call (e.g., the best row from `solveThreeStateModel`) before hardcoding into the script. The user must confirm the chosen values, per their feedback rule.
- If the user provides medians but the analysis plan is unclear, ask: "Will OS/PFS be analyzed with a Cox PH model or log-rank test? That determines whether to use `CorrelatedPfsAndOs2` (PH-compatible) or `CorrelatedPfsAndOs3` (more flexible but Cox-incompatible)."
- For exponential-distribution rate calculation, the formula `rate = log(2) / median` is so common that the agent should not ask the user to compute it.
- Helper outputs are `numeric` or `data.frame` — copy literals into the script with sensible rounding (e.g., 3 significant figures).

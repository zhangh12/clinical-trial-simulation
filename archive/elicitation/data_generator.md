# Data Generator Elicitation Guide

## Goal
Design a generator function `function(n, ...)` for each arm × endpoint combination.
Default to the simplest model that fits; escalate complexity only if user requires it.

> **See `elicitation/parameter_determination.md` for the full decision flowchart from clinical inputs (medians, response rates, correlations, landmark survival/dropout probabilities) to the appropriate helper function in `knowledge/api/helpers.md`.** This guide focuses on choosing distribution families; that guide handles parameter conversion.

---

## Decision Tree by Endpoint Type

### TTE Endpoints (overall survival, PFS, etc.)

**Step 1:** "Do you expect a constant hazard over time, or does the hazard change (e.g., delayed treatment effect, piecewise pattern)?"
- Constant → exponential: `rexp(n = n, rate = log(2) / median)`
- Piecewise constant → `PiecewiseConstantExponentialRNG(n = n, rate = c(...), duration = c(...))`

**Step 2:** "What is the median survival (or hazard rate) for each arm?"
→ Control: median_control; Experimental: median_exp (or HR = median_control / median_exp)

**Step 3:** "Is there patient dropout? If so, what is the dropout pattern?"
- Simple: exponential dropout with a long median (e.g., 5× trial duration)
- None: `dropout = NULL` in `trial()`

**Step 4:** Correlated endpoints:
"Will you be modeling both PFS and OS?"
→ Yes → see **Correlated PFS + OS** section below — do NOT route to NORTA for this case.

### Non-TTE Endpoints (continuous, binary, categorical)

**Step 1:** "What type of measurement is [endpoint]?"
- Binary (e.g., response): `rbinom(n = n, size = 1, prob = prob)`; ask for response rate per arm
- Continuous (e.g., biomarker): `rnorm(n = n, mean = mean, sd = sd)`; ask for mean and SD per arm
- Categorical: `sample(x = categories, size = n, prob = ..., replace = TRUE)` — must be wrapped (first arg is not `n`)

**Step 2:** "Are there repeated measurements? If so, at which timepoints?"
→ Defines `readout` vector (including `0` for baseline if needed)
→ Generator must return one column per timepoint named consistently

### Covariates / Baseline Characteristics

All patient-level variables (covariates, biomarkers, subgroups) must go through `endpoint()` with `readout = 0`.

"What distribution should [variable] follow?"
- Binary subgroup: `rbinom(n, 1, prevalence)`
- Continuous biomarker: `rnorm(n, mean, sd)`
- Other: any distribution whose first arg is `n`; wrap if not (e.g., `sample()`)

### Correlated PFS + OS

Always use the dedicated built-in generators — do NOT use NORTA for PFS + OS.

**Collect these 4 things before writing code:**

1. **Median PFS per arm** — "What is the expected median PFS for each arm (months)?"
2. **Median OS per arm** — "What is the expected median OS for each arm (months)?"
3. **Correlation** — "How correlated do you expect PFS and OS to be? (0.5–0.8 is typical in oncology.)"
   - `CorrelatedPfsAndOs2` takes Kendall's tau; `CorrelatedPfsAndOs3` takes Pearson — ask once method is chosen
4. **Analysis model** — "Will you analyze OS (or PFS) with a Cox model or log-rank test?"

**Method selection:**

| | `CorrelatedPfsAndOs2` | `CorrelatedPfsAndOs3` |
|---|---|---|
| Correlation input | Kendall's tau | Pearson (via `solveThreeStateModel`) |
| Marginal distributions | Exponential (simple) | 3-state illness-death model |
| PH assumption | Compatible — exponential margins | May violate — produces time-varying HR between arms |
| Parameters | `median_pfs`, `median_os`, `kendall` | `h01`, `h02`, `h12` derived by helper |
| Use when | Cox model / log-rank planned | Parametric or mechanistic analysis |

**Rule:** If the user plans a Cox PH model or log-rank test → recommend `CorrelatedPfsAndOs2`. If they choose V3 with a Cox analysis, warn explicitly: *"CorrelatedPfsAndOs3 generates a time-varying hazard ratio between arms; this is inconsistent with the proportional hazards assumption of a Cox model. Consider CorrelatedPfsAndOs2 instead."*

---

#### CorrelatedPfsAndOs2 — Gumbel copula (recommended when Cox/LR analysis planned)

Takes medians and Kendall's tau directly — no helper function needed. Each arm gets its own `endpoint()` call with its own medians; `kendall` is typically the same across arms.

```r
ep_ctrl <- endpoint(
  name       = c("pfs", "os"),
  type       = c("tte", "tte"),
  generator  = CorrelatedPfsAndOs2,
  median_pfs = <median_pfs_ctrl>,
  median_os  = <median_os_ctrl>,
  kendall    = <kendalls_tau>,
  pfs_name   = "pfs",
  os_name    = "os"
)

ep_exp <- endpoint(
  name       = c("pfs", "os"),
  type       = c("tte", "tte"),
  generator  = CorrelatedPfsAndOs2,
  median_pfs = <median_pfs_exp>,
  median_os  = <median_os_exp>,
  kendall    = <kendalls_tau>,
  pfs_name   = "pfs",
  os_name    = "os"
)
```

---

#### CorrelatedPfsAndOs3 — 3-state illness-death model (Pearson correlation)

`solveThreeStateModel()` is slow (numerical optimization) — **never include it in the simulation script.**
Use a two-step workflow: run the helper once interactively to find h values, then hardcode the numbers.

**Step 1 — agent runs `solveThreeStateModel()` via Rscript before writing the simulation script:**

Once medians and target Pearson correlation are known, execute this in a temp file:

```r
library(TrialSimulator)
pars <- solveThreeStateModel(
  median_pfs = <median_pfs_ctrl>,
  median_os  = <median_os_ctrl>,
  corr       = seq(<target_pearson> - 0.05, <target_pearson> + 0.05, by = 0.01),
  h12        = seq(0.01, 0.50, length.out = 100)
)
best <- pars[which.min(pars$error), ]
print(best)
```

Run via `Rscript` (same as validation). Repeat for each arm. Then show the user the selected row and explain:
- `h01`: transition rate from stable → progression
- `h02`: direct death rate from stable state
- `h12`: death rate after progression
- `corr`: the Pearson correlation achieved (should be close to target)

**Step 2 — simulation script (hardcoded literals from step 1):**

The simulation script contains no `solveThreeStateModel()` call — only the resolved numbers.

```r
ep_ctrl <- endpoint(
  name      = c("pfs", "os"),
  type      = c("tte", "tte"),
  generator = CorrelatedPfsAndOs3,
  h01      = <h01_ctrl>,  # derived: stable→progression rate, control
  h02      = <h02_ctrl>,  # derived: direct death rate, control
  h12      = <h12_ctrl>,  # derived: post-progression death rate, control
  pfs_name = "pfs",
  os_name  = "os"
)

ep_exp <- endpoint(
  name      = c("pfs", "os"),
  type      = c("tte", "tte"),
  generator = CorrelatedPfsAndOs3,
  h01      = <h01_exp>,
  h02      = <h02_exp>,
  h12      = <h12_exp>,
  pfs_name = "pfs",
  os_name  = "os"
)
```

---

### Correlated Endpoints (any mix of types other than PFS + OS)

"Are any endpoints correlated with each other?"
→ Yes → use **NORTA** via `simdata` package

Key questions:
- "What is the marginal distribution of each endpoint?" (one quantile function per endpoint)
- "Do you have a target correlation matrix, or should we use a placeholder?"

Implementation notes (see `knowledge/api/building_blocks.md` for full example):
- Build `simdesign_norta(dist, cor_target_final)` **once outside** the generator (runs numerical optimization)
- Generator calls `simulate_data(generator = design, n = n)` — returns matrix, wrap with `as.data.frame()`
- NORTA has no concept of tte/non-tte; add `<name>_event = 1L` in the wrapper for each TTE endpoint
- After defining `ep`, always validate: `ep$test_generator(n = 10000)` + Pearson correlation check (see `validation/validate.md`)

---

## User-Provided Generator

If the user says they have their own generator code:
1. Ask them to paste it or describe its output columns
2. Verify: does it accept `n` as first argument? Does it return the right column names?
3. If it returns extra columns, use `arm(..., filter_condition)` or subset inside generator
4. Insert as-is with a validation placeholder:
   ```r
   # USER-PROVIDED GENERATOR — validate output structure before running
   my_generator <- function(n, ...) {
     # [user code here]
   }
   ```

---

## Output: Generator per Arm

```r
# Control arm generator
gen_control <- function(n, ...) {
  data.frame(
    os       = rexp(n = n, rate = log(2) / <median_control>),
    os_event = 1L   # assume no censoring from dropout; adjust if needed
  )
}

# Experimental arm generator
gen_exp <- function(n, hr = <hazard_ratio>, ...) {
  data.frame(
    os       = rexp(n = n, rate = log(2) / <median_control> * hr),
    os_event = 1L
  )
}
```

---

## Notes for Agent
- Always suggest the simplest adequate model first; user can request complexity
- Event indicator `<ep>_event = 1L` (always event) is valid when dropout is handled by `trial(dropout = ...)` separately
- Ask about dropout separately from the generator — usually cleaner to handle in `trial()`
- For oncology TTE, exponential is the default unless user explicitly mentions delayed effect or crossing hazards

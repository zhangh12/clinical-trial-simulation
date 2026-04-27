# Trial Object Elicitation Guide

## Goal
Collect enough information to fill `trial(name, n_patients, duration,
enroller, dropout, stratification_factors, ...)`. Most of these arguments
are simple, but the enroller and dropout are commonly under-specified by
users — defaults and probing questions below.

---

## Step 1: Sample size and duration

- "What is the planned maximum sample size?" → `n_patients` (integer)
- "What is the planned trial duration, and in what time units (months / weeks)?" → `duration` (numeric)

> The unit chosen here must be the same as `readout` in `endpoint()`, the units used in `weibullDropout`, and any user-specified milestone times. **Confirm units explicitly.**

If the user later uses `set_duration()` adaptively, the new value must exceed `duration`; same for `resize()` and `n_patients`. Set `duration` somewhat larger than the longest expected milestone time to leave headroom (e.g., the vignettes use `duration = 500` and let an `eventNumber` milestone close the trial earlier).

---

## Step 2: Enroller (almost always `StaggeredRecruiter`)

"How will patients enroll? Constant rate, or ramp-up?"

| User answer | Code |
|---|---|
| "X patients per month, constant" | `accrual <- data.frame(end_time = Inf, piecewise_rate = X)` |
| "Y for the first T months, then Z thereafter" | `accrual <- data.frame(end_time = c(T, Inf), piecewise_rate = c(Y, Z))` |
| "Ramp-up: starts at A, increases to B over T1..T2 months" | Multiple rows; share the schedule with `solveThreeStateModel`-style helper if needed |

```r
tr <- trial(name = "...", n_patients = 1000, duration = 36,
            enroller = StaggeredRecruiter, accrual_rate = accrual)
```

If the user has a custom enroller function, confirm its first argument is `n` and pass it to `trial(enroller = my_fn, ...)`; extra args go through `...`.

---

## Step 3: Dropout

"Is there patient dropout? If so, how is it specified?"

| User answer | Code | Helper |
|---|---|---|
| "No dropout" | omit `dropout` arg | — |
| "P% by month T (single landmark)" | `dropout = rexp, rate = -log(1 - P) / T` | none |
| "P1% at T1 and P2% at T2 (two landmarks)" | `dropout = rweibull, scale = ..., shape = ...` | `weibullDropout(time = c(T1, T2), dropout_rate = c(P1, P2))` |
| Custom dropout (user-provided function) | `dropout = my_fn` | confirm first arg is `n` |

Always remind the user that the unit of dropout time must match `duration` and `readout`.

---

## Step 4: Stratification factors (often skipped)

"Are there baseline characteristics to stratify randomization on (e.g., disease stage, biomarker status, region)?"

If yes:
1. Each stratification factor must be defined as a `non-tte` endpoint with `readout = 0`.
2. The factor name is passed to `stratification_factors`:

```r
ep_region <- endpoint(name = "region", type = "non-tte",
                      readout = c(region = 0),
                      generator = function(n, ...) {
                        data.frame(region = sample(c("US","EU","ROW"), n,
                                                   replace = TRUE,
                                                   prob = c(.4,.4,.2)))
                      })
# attach to every arm
ctrl$add_endpoints(ep_region); exp1$add_endpoints(ep_region); ...

tr <- trial(..., stratification_factors = c("region"))
```

`TrialSimulator` assumes baseline characteristics share the same distribution across arms (consistent with randomization). If the user wants different distributions per arm for a baseline, that's a flag that something else is intended (e.g., enrichment / different inclusion criteria — use `arm(name, biomarker == "positive")` instead).

---

## Step 5: Other arguments

- `seed`: omit (set to `NULL`) for per-replicate auto-seeding (recommended for simulation studies). Set to a specific integer only for debugging a single replicate.
- `silent = TRUE`: suppress runtime messages — useful when running large simulation batches.
- `description = name`: only matters if the user wants a verbose label in printed output.

---

## Output Template

```r
# Enroller
accrual <- data.frame(
  end_time       = c(<t1>, <t2>, Inf),
  piecewise_rate = c(<r1>, <r2>, <r3>)
)

# Optional: dropout (Weibull example)
dpars <- weibullDropout(time = c(12, 18), dropout_rate = c(0.08, 0.18))

tr <- trial(
  name         = "<trial_id>",
  n_patients   = <n>,
  duration     = <max_duration>,
  enroller     = StaggeredRecruiter,
  accrual_rate = accrual,
  dropout      = rweibull,
  scale        = dpars["scale"],
  shape        = dpars["shape"],
  stratification_factors = NULL,   # or c("region", "stage")
  silent       = TRUE
)

tr$add_arms(sample_ratio = c(1, 1, 1), ctrl, exp1, exp2)
```

---

## Notes for Agent

- **Always confirm time units.** This is the #1 source of silent bugs.
- For SIMPLE designs where the user has not pre-specified accrual, suggest a reasonable default (e.g., `n_patients / duration` patients per period) and ask for confirmation.
- When in doubt about whether a baseline variable should be a stratification factor, ask: "Does randomization need to be balanced across this variable's levels?" Yes → stratify. No → just include as a covariate (`endpoint(readout = 0)`) without listing in `stratification_factors`.

# Data Generator Elicitation Guide

## Goal
Design a generator function `function(n, ...)` for each arm × endpoint combination.
Default to the simplest model that fits; escalate complexity only if user requires it.

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

**Step 4:** Correlated endpoints (e.g., PFS + OS):
"Are PFS and OS correlated? (They usually are in oncology.)"
→ Yes → suggest `CorrelatedPfsAndOs3()` or `CorrelatedPfsAndOs4()` built-ins

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

### Correlated Endpoints (any mix of types)

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

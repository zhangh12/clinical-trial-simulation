# Endpoint Elicitation Guide

## Goal
Collect enough information to write `endpoint(name, type, readout, generator, ...)` and the generator function body.

---

## Question Sequence

### Step 1: Endpoint names
"What endpoints will you measure? Give each a short name (e.g., `os`, `pfs`, `orr`, `biomarker`)."
→ `name` (character vector)

### Step 2: Endpoint types
For each endpoint: "Is [name] time-to-event (e.g., survival, progression) or measured at a fixed time (e.g., response rate, biomarker level)?"
→ `type`: `"tte"` per TTE endpoint, `"non-tte"` per fixed-time endpoint

### Step 3: Readout times (non-TTE only)
For each non-TTE endpoint: "When is [name] assessed after enrollment? (e.g., week 8, month 3)"
→ `readout = c(ep_name = numeric_value)` — must be in same units as trial duration
Skip entirely if all endpoints are TTE.

### Step 4: Covariates
"Are there any baseline characteristics (biomarkers, subgroups) needed for data generation or analysis?"
→ If yes: define as endpoints with `readout = 0` (baseline) and `type = "non-tte"`
→ These enable stratified randomization via `stratification_factors` in `trial()`

### Step 5: Data generator
→ Defer to `data_generator.md` elicitation.
→ Output: a function `generator(n, ...)` returning a data.frame with:
  - Columns named exactly as `name` values
  - For TTE endpoints: additional column `<ep_name>_event` (1 = event, 0 = censored)
→ If user input requires conversion (medians+correlation, landmark survival probs, mixture, dropout rates at landmarks), see `elicitation/parameter_determination.md` to invoke the right helper from `knowledge/api/helpers.md` BEFORE writing the script.

---

## Output Template

```r
# Generator function (filled after data_generator.md elicitation)
my_generator <- function(n, ...) {
  data.frame(
    # <endpoint_name> = ...,          # TTE: time to event/censoring
    # <endpoint_name>_event = ...,    # TTE: 1=event, 0=censored
    # <endpoint_name> = ...           # non-TTE: observed value
  )
}

ep <- endpoint(
  name      = c("<ep1>", "<ep2>"),           # fill from Step 1
  type      = c("<tte|non-tte>", "..."),     # fill from Step 2
  readout   = c(<ep2> = <value>),            # fill from Step 3; NULL if all TTE
  generator = my_generator
)
```

---

## Notes for Agent
- Each arm typically has its own `endpoint()` call with its own generator (different treatment effects)
- Control arm and experimental arm(s) share endpoint *names* and *types* but have different generators
- A single `endpoint()` can bundle multiple endpoints if they share a generator (e.g., correlated PFS + OS)
- Built-in generators available: `PiecewiseConstantExponentialRNG()`, `CorrelatedPfsAndOs2()` (Gumbel copula, PH-compatible), `CorrelatedPfsAndOs3()` (3-state model), `CorrelatedPfsAndOs4()` (4-state model with response), `rconst()`, `StaggeredRecruiter()` (for enroller)
- Parameter-determination helpers (called once *outside* the simulation script and hardcoded): `solveThreeStateModel()`, `solveMixtureExponentialDistribution()`, `solvePiecewiseConstantExponentialDistribution()`, `weibullDropout()`, `qPiecewiseExponential()`. See `knowledge/api/helpers.md`.

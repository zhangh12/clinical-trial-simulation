# Trials Class Member Functions (Action Function API)

These are called on the `trial` object inside action functions.
The `trial` argument in `action(trial, ...)` is an instance of the Trials R6 class.

---

## Data Access

### `trial$get_locked_data(milestone_name)`
Returns a data.frame snapshot censored/truncated at the milestone trigger time.
- `milestone_name` (character): must match a defined milestone name
- Contains columns: `arm`, all endpoint columns, `<ep>_event` for TTE, covariates

---

## Saving Results

### `trial$save(value, name, overwrite = FALSE)`
Save a scalar or 1-row data.frame per replicate. Accumulates across replicates.
- `value`: scalar or 1-row data.frame (e.g., a filtered row from a fit result)
- `name`: column name/prefix in `get_output()` result
- Use distinct `name` values for different metrics

### `trial$bind(value, name)`
Row-bind a multi-row data.frame. Resets between replicates.

### `trial$save_custom_data(value, name, overwrite = FALSE)`
Save any object (list, vector, etc.) for within-replicate workflow control.
Retrieve with `trial$get(name)`.

### `trial$get(name)`
Retrieve data saved by `save_custom_data()`. Returns NULL if not yet set — use a fallback if retrieved in a later milestone.

### `trial$get_output(cols = NULL, simplify = TRUE, tidy = FALSE)`
Retrieve all results saved via `save()` across replicates. Returns a data.frame.

---

## Adaptive Modifications

### `trial$resize(n_patients)`
Increase maximum sample size (sample size reassessment). New value must exceed current.

### `trial$set_duration(duration)`
Extend trial duration. New value must exceed current.

### `trial$remove_arms(arms_name)`
Drop one or more arms by name (character vector). Used for arm selection or futility stopping.

### `trial$update_sample_ratio(arm_names, sample_ratios)`
Update randomization ratios for active arms.
- `arm_names` (character vector): arm identifiers
- `sample_ratios` (numeric vector): new ratios (same length)

### `trial$add_arms(sample_ratio, ...)`
Add new arm(s) mid-trial. Arms (with endpoints) can be defined inside the action function.
- `sample_ratio` (integer vector): ratios for new arms
- `...`: arm objects from `arm()`

### `trial$update_generator(arm_name, endpoint_name, generator, ...)`
Replace the data generator for one arm's endpoint(s). Used in enrichment designs.

### `trial$add_regimen(regimen)`
Register a regimen (treatment switching rules). Call before `add_arms()`.

---

## Statistical Testing (Group Sequential / Adaptive)

### `trial$dunnettTest(formula, placebo, treatments, milestones, alternative, planned_info, ...)`

| Arg | Notes |
|-----|-------|
| `formula` | `survival::coxph`-style, e.g., `os ~ arm` |
| `placebo` | reference arm name |
| `treatments` | character vector of experimental arm names |
| `milestones` | all milestone names contributing data (e.g., `c("interim", "final")`) |
| `alternative` | `"greater"` or `"less"` |
| `planned_info` | pre-specified event counts per stage, or `"oracle"` |
| `...` | filter conditions for subsetting data |

### `trial$closedTest(dunnett_test, treatments, milestones, alpha, alpha_spending)`
Closed testing using Dunnett combination test; controls FWER.
- `alpha_spending`: `"asOF"` (O'Brien-Fleming) or `"asP"` (Pocock)
- Returns data.frame: `arm`, `decision` ("reject"/"accept"), `milestone_at_reject`, `reject_time`

---

## Built-in Analytic Wrappers

All wrappers are called directly (not on `trial`). All tests are one-sided.
All return a data.frame with one row per experimental arm.

### `fitCoxph(formula, placebo, data, alternative, scale, ...)`
Cox proportional hazards model for TTE endpoints.
- `formula`: `Surv(time, event) ~ arm` or with covariates
- `scale`: `"hazard ratio"` (default) or `"log hazard ratio"`
- Returns: `arm`, `placebo`, `estimate` (HR), `p`, `z`, `info`

```r
fit <- fitCoxph(
  formula     = Surv(os, os_event) ~ arm,
  placebo     = "control",
  data        = data,
  alternative = "less",
  scale       = "hazard ratio"
)
trial$save(value = fit[fit$arm == "exp1", c("estimate", "p")], name = "os_exp1")
```

### `fitLogrank(formula, placebo, data, alternative, ...)`
Log-rank test for TTE endpoints.
- `formula`: `Surv(time, event) ~ arm`
- Returns: `arm`, `placebo`, `p`, `z`, `info` (+ `n_pbo`, `n_trt`, `info_pbo`, `info_trt` with `tidy = FALSE`)

```r
fit <- fitLogrank(
  formula     = Surv(os, os_event) ~ arm,
  placebo     = "control",
  data        = data,
  alternative = "less"
)
trial$save(value = as.integer(fit$p[fit$arm == "exp1"] < 0.025), name = "reject_h0")
```

### `fitLogistic(formula, placebo, data, alternative, scale, ...)`
Logistic regression for binary endpoints.
- `scale`: `"coefficient"`, `"odds ratio"`, `"risk ratio"`, or `"risk difference"`
- Returns: `arm`, `placebo`, `estimate`, `p`, `z`, `info`

```r
fit <- fitLogistic(
  formula     = response ~ arm,
  placebo     = "control",
  data        = data,
  alternative = "greater",
  scale       = "risk difference"
)
trial$save(value = as.integer(fit$p[fit$arm == "exp1"] < 0.025), name = "reject_h0")
```

### `fitLinear(formula, placebo, data, alternative, ...)`
Linear model for continuous endpoints.
- Returns: `arm`, `placebo`, `estimate`, `p`, `z`, `info`

```r
fit <- fitLinear(
  formula     = change ~ arm,
  placebo     = "control",
  data        = data,
  alternative = "greater"
)
trial$save(value = fit[fit$arm == "exp1", c("estimate", "p")], name = "change_exp1")
```

### `fitFarringtonManning(endpoint, placebo, data, alternative, ...)`
Rate difference test for binary endpoints (no covariate adjustment).
- `endpoint` (character): column name, not a formula
- Returns: `arm`, `placebo`, `estimate`, `p`, `z`, `info`

```r
fit <- fitFarringtonManning(
  endpoint    = "response",
  placebo     = "control",
  data        = data,
  alternative = "greater"
)
trial$save(value = as.integer(fit$p[fit$arm == "exp1"] < 0.025), name = "reject_h0")
```

---

## What to Save: Operating Characteristics by Design Type

### Efficacy / Power
```r
trial$save(value = as.integer(fit$p[fit$arm == "exp1"] < alpha), name = "reject_h0")
trial$save(value = fit$p[fit$arm == "exp1"],                      name = "pvalue")
trial$save(value = fit$estimate[fit$arm == "exp1"],               name = "hr")  # or RD, OR
```

### Seamless / Arm selection designs
```r
trial$save_custom_data(value = best_arm, name = "selected_arm")  # pass to final action
trial$save(value = best_arm,                      name = "selected_arm")
trial$save(value = as.integer(best_arm == "exp1"), name = "correct_selection")
```

### Sample size / Duration
```r
trial$save(value = nrow(data),                                name = "n_total")
trial$save(value = sum(data$arm == "exp1"),                   name = "n_exp1")
trial$save(value = sum(data$os_event, na.rm = TRUE),          name = "n_events")
# Trial duration not directly accessible in action; use calendarTime milestone to record it
```

### Early stopping
```r
trial$save(value = as.integer(stopped_early),  name = "early_stop")
trial$save(value = as.integer(stopped_efficacy), name = "stop_efficacy")
trial$save(value = as.integer(stopped_futility), name = "stop_futility")
```

### RAR / Allocation
```r
alloc <- table(data$arm)
for (a in names(alloc)) {
  trial$save(value = as.integer(alloc[a]), name = paste0("n_", a))
}
trial$save(value = t(round(new_ratios, 3)), name = paste0("ratio_", milestone_name))
```

### Multi-endpoint (save per-arm, per-endpoint)
```r
# Save a 1-row slice from fit result directly
trial$save(value = fit[fit$arm == "low",  c("estimate", "p", "info")], name = "pfs_low")
trial$save(value = fit[fit$arm == "high", c("estimate", "p", "info")], name = "pfs_high")
```

### Summarizing output after simulation
```r
out <- ctr$get_output()

# Power
mean(out$reject_h0, na.rm = TRUE)

# Mean HR / effect estimate
mean(out$hr, na.rm = TRUE)

# Correct selection rate
mean(out$selected_arm == "exp1", na.rm = TRUE)

# Early stop probability
mean(out$early_stop, na.rm = TRUE)

# Mean sample size
mean(out$n_total, na.rm = TRUE)

# Mean allocation per arm
mean(out$n_exp1, na.rm = TRUE)
```

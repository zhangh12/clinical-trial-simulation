# Trials & Controllers Class Member Functions (Action Function API)

These are called on the `trial` object inside action functions, plus the
controller methods invoked at simulation top-level. The `trial` argument
in `action(trial, ...)` is an instance of the Trials R6 class.

Most adaptation methods also have **standalone wrapper functions** with the
trial as the first argument: `remove_arms(trial, ...)` ≡ `trial$remove_arms(...)`,
`add_arms(trial, ...)`, `resize(trial, ...)`, `set_duration(trial, ...)`,
`update_sample_ratio(trial, ...)`, `update_generator(trial, ...)`. Either
form is valid; the `$method()` form is shown below.

---

## Data Access

### `trial$get_locked_data(milestone_name)`
Returns a data.frame snapshot censored/truncated at the milestone trigger time.
- `milestone_name` (character): must match a defined milestone name
- Contains columns: `arm`, all endpoint columns, `<ep>_event` for TTE, covariates
- Always the first call inside any non-`doNothing` action function.

### `trial$get_event_number(milestone_name = NULL)`
Returns observed event/sample counts at the lock time of one or all triggered milestones.

### `trial$get_milestone_time(milestone_name = NULL)`
Returns the calendar time at which the named milestone was triggered (or all triggered milestones if `NULL`). Useful for saving trial duration as an operating characteristic.

### Pre-trial planning helpers (also on `trial`)

These three helpers return the data-lock time **without mutating** the trial — useful when planning the trial or in a `doNothing` action to record what the trigger condition resolves to:

- `trial$get_data_lock_time_by_event_number(endpoints, arms, target_n_events, type, ...)`
- `trial$get_data_lock_time_by_enrollment(arms, target_n_patients, min_treatment_duration, ...)`
- `trial$get_data_lock_time_by_calendar_time(calendar_time)`

`...` accepts `dplyr::filter` subset conditions in all three.

---

## Saving Results

### `trial$save(value, name = "", overwrite = FALSE)`
Persistent across replicates — accumulates into the `controller$get_output()` data frame.
- `value`: scalar or 1-row data.frame
- `name`: column name (or prefix when `value` is a multi-column 1-row data.frame). Empty string preserves the value's column names as-is.

### `trial$bind(value, name)`
Row-binds a multi-row data.frame across milestones **within a single replicate**. Resets between replicates. Use this to accumulate stage-wise p-values that need to be tested together at the end (e.g., `GraphicalTesting` p-values).

### `trial$save_custom_data(value, name, overwrite = FALSE)`
Save any object (list, vector, data frame, etc.) for **within-replicate** workflow control. Resets between replicates. Common use: pass `selected_arm` from interim → final, or store the `fwer` once before the trial runs.

> **Namespace warning:** `save()` and `save_custom_data()` share a name registry. Calling both with the same `name` errors with "X has been used to name something in custom data". Use **distinct** names: e.g. `save_custom_data(name = "selected")` + `save(name = "selected_arm")`.
>
> **Cross-replicate warning:** even though custom data resets between replicates, the *name registry* persists. Set `overwrite = TRUE` on every `save_custom_data()` call to avoid "X has been used to name something" errors at replicate 2+.

### `trial$get(name)` / `trial$get_custom_data(name)`
Retrieve data saved by `save_custom_data()` or `bind()`. Returns NULL if not yet set — guard with a fallback when called in a later milestone whose predecessor may not have run.

### `trial$get_output(cols = NULL, simplify = TRUE, tidy = FALSE)`
Retrieve all results saved via `save()` across replicates. Returns a data.frame.
- `cols`: subset of columns; `NULL` returns all
- `tidy = TRUE`: drops auto-saved bookkeeping columns matching `^n_events_<.*?>_<.*?>$` and `^milestone_time_<.*?>$`; speeds up large simulations. **See `knowledge/api/auto_outputs.md` — agent must understand what is auto-saved before deciding what to save manually.**
- `trial$tidy_output(tidy)` toggles a per-replicate flag that skips event-count saving entirely (up to ~40% speedup; downstream `cols` won't have those columns).

---

## Adaptive Modifications

### `trial$resize(n_patients)`
Increase max sample size (sample size reassessment). New value must exceed current.

### `trial$set_duration(duration)`
Extend trial duration. New value must exceed current. Patients enrolled before the call are censored/truncated at the original duration to maintain independent increments.

### `trial$remove_arms(arms_name)`
Drop one or more arms. Used for arm selection, futility stopping, dose dropping.
- New patients can no longer be randomized to removed arms; existing patients in those arms are censored at removal time for any future data lock.

### `trial$update_sample_ratio(arm_names, sample_ratios)`
Update randomization ratios for active arms.
- Whole-number ratios → permuted block randomization; fractional → `sample()` (small chance of imbalance).

### `trial$add_arms(sample_ratio, ...)`
Add new arm(s) mid-trial. Define the full `arm()` (including endpoints) inside the action function before calling.

### `trial$update_generator(arm_name, endpoint_name, generator, ...)`
Replace the data generator for one arm's endpoint(s). Used in enrichment designs to switch to an enriched-population data model after interim.

### `trial$add_regimen(regimen)`
Register a `regimen()` (treatment switching rules). **Must be called immediately after `trial()` and before `add_arms()`** — otherwise an error is thrown.

---

## Statistical Testing (Group Sequential / Adaptive)

### `trial$independentIncrement(formula, placebo, milestones, alternative, planned_info, ...)`

Compute inverse-normal combination z-statistics across a sequence of milestones for a **single endpoint, single arm-pair** (one experimental arm vs placebo). For multi-arm, use `dunnettTest`.

| Arg | Notes |
|-----|-------|
| `formula` | `Surv(time, event) ~ arm` (TTE only); `strata(...)` allowed; no covariates |
| `placebo` | Reference arm name |
| `milestones` | Character vector of milestone names contributing data |
| `alternative` | `"greater"` or `"less"` |
| `planned_info` | Vector of pre-specified accumulative event counts named by milestone, **or `"oracle"`** to set planned = observed (debugging only — biases toward true null) |
| `...` | `dplyr::filter` subset conditions |

Returns a data.frame with columns `p_inverse_normal`, `z_inverse_normal`, `p_lr`, `z_lr`, `info`, `planned_info`, `info_pbo`, `info_trt`, `wt`. Pass `p_inverse_normal`/`observed_info`/`is_final` to `GroupSequentialTest$test()` for boundary testing.

### `trial$dunnettTest(formula, placebo, treatments, milestones, alternative, planned_info, ...)`

Stage-wise Dunnett intersection p-values for **multiple experimental arms** vs a common placebo, used as input to `closedTest()`.

| Arg | Notes |
|-----|-------|
| `formula` | `Surv(time, event) ~ arm` or `non_tte_var ~ arm` |
| `placebo` | Reference arm name |
| `treatments` | Character vector of experimental arm names |
| `milestones` | All milestone names contributing data (need not be sorted) |
| `alternative` | `"greater"` or `"less"` |
| `planned_info` | **Either** a `data.frame` with milestone names as row names and arm names as column names (stage-wise, NOT cumulative event counts), **OR** the string `"default"` — `"default"` uses **patients newly randomized between consecutive milestones** in the placebo arm as a proxy. If no patients enroll between two milestones (e.g., enrollment finished before the interim), `"default"` errors and you MUST supply a pre-fixed data.frame. **`"oracle"` is NOT a valid value here** (it belongs to `independentIncrement`). For FWER-controlled simulation, always pre-fix the data.frame; `"default"` is only for rapid prototyping when enrollment overlaps the milestones. |
| `...` | `dplyr::filter` subset conditions |

### `trial$closedTest(dunnett_test, treatments, milestones, alpha, alpha_spending)`
Closed testing using the Dunnett combination test; controls FWER strongly.
- `alpha_spending`: `"asOF"` (O'Brien-Fleming) or `"asP"` (Pocock); `"asUser"` is theoretically allowed but untested.
- Returns data.frame: `arm`, `decision` (`"reject"`/`"accept"`), `milestone_at_reject`, `reject_time`. `milestone_at_reject` is `NA` and `reject_time` is `Inf` for accepted arms.

---

## Built-in Analytic Wrappers (called outside `trial`)

All wrappers are called directly with `data` (typically the locked data). All tests are one-sided. All return a data.frame with one row per experimental arm × placebo pair.

### `fitCoxph(formula, placebo, data, alternative, scale, ..., tidy = TRUE)`
Cox proportional hazards model for TTE endpoints — supports covariate adjustment.
- `formula`: `Surv(time, event) ~ arm` or with covariates / `strata(...)`
- `scale`: `"hazard ratio"` (default) or `"log hazard ratio"`
- Returns: `arm`, `placebo`, `estimate` (HR or logHR), `p`, `z`, `info`

### `fitLogrank(formula, placebo, data, alternative, ..., tidy = TRUE)`
Log-rank test for TTE endpoints (no covariate adjustment, but `strata(...)` is allowed).
- Returns: `arm`, `placebo`, `p`, `info`, `z` (and `n_pbo`, `n_trt`, `info_pbo`, `info_trt` with `tidy = FALSE`)

### `fitLogistic(formula, placebo, data, alternative, scale, ...)`
Logistic regression for binary endpoints — supports covariate adjustment.
- `scale`: `"coefficient"`, `"odds ratio"`, `"risk ratio"`, or `"risk difference"`
- Returns: `arm`, `placebo`, `estimate`, `p`, `z`, `info`

### `fitLinear(formula, placebo, data, alternative, ...)`
Linear model for continuous endpoints — supports covariate adjustment.
- Returns: `arm`, `placebo`, `estimate` (ATE via `emmeans`), `p`, `z`, `info`

### `fitFarringtonManning(endpoint, placebo, data, alternative, ...)`
Rate-difference test for binary endpoints — **no covariate adjustment**, `endpoint` is a column name (not a formula).
- Returns: `arm`, `placebo`, `estimate`, `p`, `z`, `info`

`...` is `dplyr::filter` syntax in all wrappers, e.g. `fitLogrank(Surv(os, os_event) ~ arm, placebo = "pbo", data = data, alternative = "less", biomarker == "positive")`.

---

## Controller Methods

### `controller$run(n = 1, n_workers = 1, plot_event = TRUE, silent = FALSE, dry_run = FALSE)`

| Arg | Notes |
|-----|-------|
| `n` | Number of replicates (NOT `n_trials`) |
| `n_workers` | Parallel workers via the `mirai` package (must be installed). On Apple Silicon, set to the number of *performance* cores (e.g., 3 on M1). Auto-disables `plot_event`. |
| `plot_event` | Cumulative event plot — auto-disabled when `n > 1` or `n_workers > 1` |
| `silent` | Suppress messages (warnings still shown) |
| `dry_run` | Substitute the user action with `.default_action`, which only locks data and saves milestone time / event counts. **Use for fixed designs to estimate triggering-time distributions before writing real action functions.** Not useful for adaptive designs (adaptation must execute before timing is meaningful). |

Run more than once on the same controller? Call `controller$reset()` first — otherwise the previous output is retained and the trial will not re-randomize cleanly.

### `controller$get_output(cols = NULL, simplify = TRUE, tidy = FALSE)`
Same semantics as `trial$get_output()`.

### `controller$reset()`
Clears trial + listener state for re-execution. Call between successive `run()` calls.

---

## What to Save: Operating Characteristics by Design Type

> **Important:** every triggered milestone *automatically* saves `milestone_time_<name>`, `n_events_<milestone>_<endpoint>`, `n_events_<milestone>_<patient_id>`, and `n_events_<milestone>_<arms>` (data frame). **Don't redundantly save these manually.** See `knowledge/api/auto_outputs.md`.

### Efficacy / Power
```r
trial$save(value = as.integer(fit$p[fit$arm == "exp1"] < alpha), name = "reject_h0")
trial$save(value = fit$p[fit$arm == "exp1"],                      name = "pvalue")
trial$save(value = fit$estimate[fit$arm == "exp1"],               name = "hr")  # or RD, OR
```

### Seamless / Arm selection designs
```r
# IMPORTANT: save_custom_data and save share a namespace — use DISTINCT names.
# Always set overwrite = TRUE on save_custom_data to clear the cross-replicate name registry.
trial$save_custom_data(value = best_arm, name = "selected", overwrite = TRUE)  # within-replicate
trial$save(value = best_arm,                       name = "selected_arm")
trial$save(value = as.integer(best_arm == "exp1"), name = "correct_selection")
```

### Group sequential — independentIncrement
```r
ii <- trial$independentIncrement(
        Surv(os, os_event) ~ arm, placebo = "pbo",
        milestones = c("interim", "final"),
        alternative = "less",
        planned_info = c(interim = 150, final = 300))   # pre-fixed cumulative

gst <- GroupSequentialTest$new(alpha = 0.025, alpha_spending = "asOF",
                               planned_max_info = 300)
res <- gst$test(observed_info = ii$info,
                is_final      = c(FALSE, TRUE),
                p_values      = ii$p_inverse_normal)
trial$save(value = as.integer(any(res$decision == "reject")), name = "reject_h0")
```

### Sample size / Duration
```r
trial$save(value = nrow(data),                         name = "n_total")
trial$save(value = sum(data$arm == "exp1"),            name = "n_exp1")
# milestone time auto-saved as milestone_time_<final>; no manual save needed
```

### Multi-endpoint (save per-arm, per-endpoint)
```r
# Save a 1-row slice from fit result directly; column names preserved with name = ""
trial$save(value = fit[fit$arm == "low",  c("estimate", "p", "info")], name = "pfs_low")
trial$save(value = fit[fit$arm == "high", c("estimate", "p", "info")], name = "pfs_high")
```

### Summarizing output after simulation
```r
out <- ctr$get_output(tidy = TRUE)   # drop auto-bookkeeping columns

mean(out$reject_h0,             na.rm = TRUE)   # power
mean(out$selected_arm == "exp1", na.rm = TRUE)  # correct selection rate

# Use built-in helpers for milestone-time summaries
mt <- summarizeMilestoneTime(ctr$get_output())  # data.frame + plot method
plot(mt)
```

# Trials Class Member Functions (Action Function API)

These are called on the `trial` object inside action functions.
The `trial` argument in `action(trial, ...)` is an instance of the `Trials` R6 class.

---

## Data Access

### `trial$get_locked_data(milestone_name)`
Returns data.frame snapshot at the named milestone — censored/truncated at trigger time.
- `milestone_name` (character): must match a defined milestone name

---

## Saving Results

### `trial$save(value, name = "", overwrite = FALSE)`
Save a scalar or 1-row data.frame per replicate. Accumulates across replicates for summary.
- `value`: scalar or 1-row data.frame
- `name`: column name/prefix in output
- `overwrite`: replace existing entry if TRUE

### `trial$bind(value, name)`
Row-bind a multi-row data.frame. Resets between replicates.
- `value`: data.frame
- `name`: identifier for retrieval

### `trial$save_custom_data(value, name, overwrite = FALSE)`
Save arbitrary object (any type). Use for workflow control, parameters, intermediate state.

### `trial$get(name)`
Retrieve data saved by `bind()` or `save_custom_data()`.

### `trial$get_output(cols = NULL, simplify = TRUE, tidy = FALSE)`
Retrieve all results saved via `save()`. `tidy = TRUE` excludes standard metrics.

---

## Adaptive Modifications

### `trial$set_duration(duration)`
Extend trial duration. New value must exceed current.

### `trial$resize(n_patients)`
Increase maximum sample size (sample size reassessment).

### `trial$remove_arms(arms_name)`
Drop one or more arms by name (character vector). Used for arm selection, futility stopping.

### `trial$update_sample_ratio(arm_names, sample_ratios)`
Update randomization ratios for existing arms.
- `arm_names` (character vector): arm identifiers
- `sample_ratios` (numeric vector): new ratios (same length as arm_names)

### `trial$update_generator(arm_name, endpoint_name, generator, ...)`
Change data generator for one arm's endpoint(s). Used in enrichment designs.
- `arm_name` (character): single arm
- `endpoint_name` (character vector): endpoint(s) to update
- `generator` (function): new generator

### `trial$add_arms(sample_ratio, ...)`
Add new arm(s) during trial. Used in dose-ranging or adaptive addition designs.
- `sample_ratio` (integer vector): ratios for new arms
- `...`: arm objects from `arm()`

### `trial$add_regimen(regimen)`
Register a regimen (treatment switching rules) to the trial.

---

## Statistical Testing

### `trial$dunnettTest(formula, placebo, treatments, milestones, alternative, planned_info, ...)`
Perform Dunnett's test for multiple comparisons under group sequential design.

| Arg | Notes |
|-----|-------|
| `formula` | `survival::coxph`-style; includes arm and endpoint |
| `placebo` | reference arm name |
| `treatments` | character vector of comparison arm names |
| `milestones` | character vector of analysis milestone names |
| `alternative` | `"greater"` or `"less"` |
| `planned_info` | numeric vector of pre-specified event counts, or `"oracle"` |
| `...` | filter conditions for subsetting data |

Returns list of data.frames per intersection hypothesis (p-values, z-stats, info).

### `trial$closedTest(dunnett_test, treatments, milestones, alpha, alpha_spending)`
Closed testing using Dunnett combination test; controls FWER.

| Arg | Notes |
|-----|-------|
| `dunnett_test` | output of `dunnettTest()` |
| `treatments` | arms to test |
| `milestones` | analysis stages |
| `alpha` | significance level (e.g., 0.025) |
| `alpha_spending` | `"asP"` (Pocock) or `"asOF"` (O'Brien-Fleming) |

Returns data.frame: arm, decision, milestone_at_reject, reject_time.

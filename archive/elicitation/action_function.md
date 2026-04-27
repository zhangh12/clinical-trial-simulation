# Action Function Elicitation Guide

## Goal
Design the body of each `action(trial, ...)` function completely enough to generate and validate R code.

This guide is used alongside `milestone.md` — milestone.md identifies *which* milestones exist;
this guide goes deep on *what happens inside* each action function.

> **Read `knowledge/api/auto_outputs.md` first** — many "metrics" (trial duration, event counts, per-arm sample sizes) are auto-saved by the controller at every triggered milestone. Don't redundantly save them via `trial$save()`.

---

## Core Concepts to Establish Early

Before writing any action function, clarify with the user:

### 1. Operating characteristics of interest
"What metrics do you want to report across simulation replicates?"

Common examples:
- Power (probability of rejecting H0)
- Type I error rate
- Probability of correct arm selection
- Expected sample size at trial end
- Expected trial duration
- Probability of early stopping (efficacy / futility)
- Response rate in selected arm

→ These determine what gets `trial$save()`-d. Every metric needs a corresponding save call.

### 2. Decision rules
"What decisions are made at each interim? What thresholds trigger them?"

Examples:
- "Stop for efficacy if p < 0.001 at interim"
- "Drop arm if response rate < 20%"
- "Update randomization ratio proportional to observed response"
- "Select arm with highest response rate for phase III"

→ Translates to `if/else` logic inside action functions.

---

## Adaptation Patterns (ask about each if relevant to design)

### Early stopping
```r
# Efficacy stop
if (p_value < alpha_interim) {
  trial$remove_arms(losing_arms)  # remove all but winner + control
  # note: full trial stop may require all arms removed; confirm with user
}
# Futility stop  
if (conditional_power < 0.1) {
  trial$remove_arms(arms_name = c("experimental"))
}
```

### Arm selection (seamless design)
```r
# Select arm with best response
responses <- tapply(data$response, data$arm, mean, na.rm = TRUE)
best_arm <- names(which.max(responses[experimental_arms]))
arms_to_drop <- setdiff(experimental_arms, best_arm)
trial$remove_arms(arms_name = arms_to_drop)
```

### Response-adaptive randomization
```r
# Update ratios proportional to observed response
responses <- tapply(data$response, data$arm, mean, na.rm = TRUE)
new_ratios <- responses / sum(responses)
trial$update_sample_ratio(arm_names = names(new_ratios), sample_ratios = new_ratios)
```

### Sample size reassessment
```r
# Blinded SSR based on observed variance
observed_var <- var(data$endpoint, na.rm = TRUE)
new_n <- ceiling(2 * (qnorm(0.975) + qnorm(0.8))^2 * observed_var / delta^2)
trial$resize(n_patients = max(new_n, current_n))
```

---

## User-Provided Code Integration

If the user has existing R code for an analysis or adaptation:

1. Ask them to share it or describe its inputs/outputs
2. Identify what it needs: data frame structure, parameters
3. Wrap it in the action function — it receives `data` from `trial$get_locked_data()`
4. Add placeholder comment if code is not yet ready:
   ```r
   # USER CODE PLACEHOLDER: [description of what goes here]
   # Expected input: data frame with columns: arm, <endpoint>, ...
   # Expected output: <describe>
   result <- NULL  # replace with user code
   ```
5. Ensure at least one `trial$save(value = result, name = "placeholder")` so validation can run

---

## Saving Results

Always confirm: "For each metric you mentioned, which milestone should save it?"

```r
# Scalar per replicate
trial$save(value = value, name = "metric_name")

# Multi-row data per replicate
trial$bind(value = data_frame, name = "dataset_name")

# Intermediate state (passed between milestones)
trial$save_custom_data(value = object, name = "state_key")
intermediate <- trial$get(name = "state_key")  # retrieve in later milestone
```

---

## Dummy but Runnable Actions

If the user has not specified the exact decision rule, do NOT omit the adaptive call or use a placeholder.
Instead, generate a runnable dummy condition that:
1. Reads from locked data (e.g., event counts, response rates)
2. Applies a simple threshold or ranking
3. Makes the adaptive call
4. Is guarded against edge cases

Label it clearly: `# DUMMY CONDITION — replace with actual rule`

The code must run without errors. A dummy action is better than a broken or incomplete one.

---

## Cross-Milestone State

Use `trial$save_custom_data()` + `trial$get()` for arbitrary objects (lists, vectors) within a single replicate. Use `trial$bind()` to row-accumulate a data.frame across milestones (useful for collecting per-stage statistics tested together at the final action with `GraphicalTesting`). Both reset between replicates. Always guard `trial$get()` with a NULL check — the saving milestone may not have fired (e.g., very small trial).

## Treatment Switching (Pre-Trial Setup, Not in Action)

If the design includes treatment switching via `regimen()`, the regimen is registered **before any action runs** and **before `add_arms()`**:

```r
tr <- trial(...)
tr$add_regimen(reg)                      # <-- BEFORE add_arms; package errors otherwise
tr$add_arms(sample_ratio = c(...), ...)
```

Inside action functions you can use `expandRegimen(data)` to convert the compact `regimen_trajectory` column into one row per regimen segment per patient.

## Checklist Before Generating Code

- [ ] All operating characteristics identified → mapped to `trial$save()` calls (and noted which are auto-saved instead)
- [ ] All decision rules defined → translated to if/else conditions (or dummy if unknown)
- [ ] All adaptation methods chosen → mapped to `trial$<method>()` calls
- [ ] Every action calls `trial$get_locked_data()` as its first step
- [ ] Every adaptive call is guarded against edge cases (length > 0, arm exists, value > current)
- [ ] User code (if any) located and wrapped
- [ ] At least one `trial$save()` in every non-`doNothing` action
- [ ] If using `dunnettTest`, `planned_info = "default"` (not `"oracle"`)
- [ ] If using `regimen`, `add_regimen()` precedes `add_arms()`
- [ ] Code runs end-to-end with `n = 3` before returning to user

# Pattern: Dynamic Treatment Switching (Crossover via `regimen()`)

## What it is
A trial where some patients **switch treatment mid-study** based on a
patient-level event (progression, non-response, deterioration, scheduled
visit). Examples: control-arm crossover after progression, rescue
medication for non-responders, dose escalation for poor response, switch
after an adverse event.

This is implemented via `regimen()` — a triple of functions:
- `what(patient_data)` — selects who switches and the new treatment
- `when(patient_data)` — assigns switching time (from enrollment)
- `how(patient_data)` — modifies post-switch outcome data

The regimen is registered to the trial **immediately after `trial()` and
before `add_arms()`** — order matters and the package errors otherwise.

For *crossover with washout* (patients receive a sequence of treatments at
fixed intervals — like Latin-square AB/BA designs), use the longitudinal-
endpoints approach (multiple `readout` times) instead — see the
`crossoverWashout` vignette pattern.

## Key Characteristics
- A single arm definition still represents the originally randomized arm — switching modifies post-switch *data*, not arm membership
- `what` returns one row per *switcher*: `data.frame(patient_id, new_treatment)`. Patients with `NA` `new_treatment` are skipped.
- `when` returns one row per row of input data: `data.frame(patient_id, switch_time)`. **No NAs allowed.**
- `how` returns one row per switcher with **only the modified columns** + `patient_id`. Unmodified cells are `NA` (or filled with original values; both are OK).
- **Never apply dropout/censoring inside `how`** — `TrialSimulator` handles that automatically when the milestone fires.
- `what`, `when`, `how` can each be a **list** of functions for multi-stage switching (executed sequentially).

## TrialSimulator Call Sequence

```
1. endpoint() per arm × endpoint   (often correlated PFS+OS)
2. arm() × K
3. trial()
   trial$add_regimen(regimen(what, when, how))   ← MUST come before add_arms()
   trial$add_arms(sample_ratio, ...)
4. milestone() / listener() / controller() / run()
```

## Decision Points

| Decision | Question to ask |
|----------|-----------------|
| Switching trigger | "What event causes a patient to switch treatments? (progression, non-response, scheduled visit, etc.)" |
| Switching population | "All patients in a specific arm? Only non-responders? Subgroup-defined?" |
| New treatment(s) | "Switch to which arm/regimen? Single destination or distribution?" |
| Switching time | "At progression? At a specific visit? A random time between two events?" |
| Outcome modification | "Which endpoints change post-switch? (e.g., extend OS by a factor; replace post-switch hazard rate)" |
| Multi-stage switching | "Just one switch, or can patients switch multiple times?" |

## Example: Crossover After Progression (Post-Progression Crossover)

Control patients can switch to low or high dose at progression; OS is extended via a causal-AFT-style multiplier.

```r
# what: who switches and to what
treatment_allocator <- function(patient_data) {
  switch_to <- sample(c("low dose", "high dose", "stay"),
                      nrow(patient_data),
                      replace = TRUE, prob = c(.3, .4, .3))
  data.frame(
    patient_id = patient_data$patient_id,
    new_treatment = dplyr::case_when(
      patient_data$os == patient_data$pfs                       ~ NA_character_,  # died at progression
      patient_data$arm == "placebo" & switch_to == "low dose"   ~ "low dose",
      patient_data$arm == "placebo" & switch_to == "high dose"  ~ "high dose",
      TRUE                                                      ~ NA_character_
    )
  )
}

# when: switch at progression time
time_selector <- function(patient_data) {
  data.frame(
    patient_id  = patient_data$patient_id,
    switch_time = patient_data$pfs       # all rows here progressed before death
  )
}

# how: extend residual survival by a treatment-specific factor
data_modifier <- function(patient_data) {
  f <- ifelse(patient_data$new_treatment == "low dose", 1.10, 1.15)
  data.frame(
    patient_id = patient_data$patient_id,
    os = patient_data$switch_time + f * (patient_data$os - patient_data$switch_time)
  )
}

reg <- regimen(treatment_allocator, time_selector, data_modifier)

tr <- trial(name = "...", n_patients = 600, duration = 36,
            enroller = StaggeredRecruiter, accrual_rate = accrual)
tr$add_regimen(reg)                                   # BEFORE add_arms()
tr$add_arms(sample_ratio = c(1, 1, 1), pbo, low, high)
```

## Example: Crossover for Non-Responders

Patients in low dose who don't respond switch to high dose at the response readout.

```r
treatment_allocator <- function(patient_data) {
  data.frame(
    patient_id = patient_data$patient_id,
    new_treatment = dplyr::case_when(
      patient_data$arm == "low dose" & patient_data$response == 0 ~ "high dose",
      TRUE                                                         ~ NA_character_
    )
  )
}

time_selector <- function(patient_data) {
  data.frame(
    patient_id  = patient_data$patient_id,
    switch_time = patient_data$response_readout   # at response assessment
  )
}

data_modifier <- function(patient_data) {
  # update only the modified columns; e.g., reset response to a new draw
  data.frame(
    patient_id = patient_data$patient_id,
    response   = rbinom(nrow(patient_data), 1, prob = 0.40)   # high-dose response rate
  )
}
```

## Multi-Stage Switching

Pass lists of functions:

```r
reg <- regimen(what = list(allocator1, allocator2, allocator3),
               when = list(selector1,  selector2,  selector3),
               how  = list(modifier1,  modifier2,  modifier3))
```

Each set of (allocator, selector, modifier) executes sequentially. Patients passed to a later stage are a subset of those who switched in earlier stages.

## Locked Data with Regimen — `expandRegimen()`

When a regimen is registered, locked data includes a compact `regimen_trajectory` column (semicolon-separated `name@time` entries). To work with one row per regimen segment per patient:

```r
locked <- trial$get_locked_data("final")
long   <- expandRegimen(locked)
# long has `regimen` and `switch_time_from_enrollment` columns; `regimen_trajectory` removed
```

## Operating Characteristics

- **Treatment effect under crossover** — fit the same model (e.g., `fitCoxph` on OS) and observe how power degrades vs. the no-crossover scenario
- **Crossover frequency** — `mean(table(long$patient_id) > 1)` to count patients who switched
- **Time-to-switch distribution** — `summary(long$switch_time_from_enrollment)`

## Key Elicitation Questions

1. "What clinical event triggers switching? (progression, response status at readout, AE, scheduled visit?)"
2. "Which patients are eligible to switch? (specific arm, biomarker-defined, all?)"
3. "What is the destination treatment? Single regimen or randomized?"
4. "When do they switch — at the trigger event, after a delay, between two events?"
5. "Which endpoints are affected by the switch? How? (extend survival; replace post-switch hazard; replace response status?)"
6. "Single switch only, or can it happen multiple times?"
7. "Will the analysis use intent-to-treat (no adjustment) or causal methods (e.g., AFT)?"

## Template File
See `templates/treatment_switching.R`

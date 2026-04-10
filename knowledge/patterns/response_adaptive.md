# Pattern: Response-Adaptive Randomization (RAR) Design

## What it is
Randomization ratios are updated during the trial based on accumulating response data.
Arms performing better attract more patients. Ethically appealing; more patients on better treatment.
Typically used with binary or short-readout endpoints.

## Key Characteristics
- Multiple arms enrolled with initial equal (or specified) ratios
- Periodic interim milestones update randomization via `update_sample_ratio()`
- Update rule: ratios shift toward arms with better observed response
- Final milestone: primary hypothesis test on all accumulated data
- Requires careful type I error control (randomization not fixed)

## TrialSimulator Call Sequence

```
1. endpoint()     — response endpoint (non-TTE preferred; fast readout) + primary (may differ)
2. arm() × K+1   — K experimental + 1 control; each with generator
3. trial()        — total planned sample size
   trial$add_arms(sample_ratio = c(1,...,1), ctrl, exp1, ..., expK)
4. milestone(name = "rar_1", when = enrollment(n = n1), action = action_rar)
5. milestone(name = "rar_2", when = enrollment(n = n2), action = action_rar)   # repeat as needed
   ...
6. milestone(name = "final", when = enrollment(n = N) | calendarTime(time = T), action = action_final)
7. listener()
8. controller(trial = tr, listener = l) → $run(n_trials = N)
```

## Decision Points (What Varies Per User)

| Decision | Question to ask |
|----------|-----------------|
| Adaptive endpoint | "What endpoint drives the randomization update? (often different from primary)" |
| Number of RAR updates | "How often do you want to update ratios? (every N patients, every M months?)" |
| Update rule | "How should ratios be computed from observed responses?" |
| Minimum allocation floor | "Is there a minimum allocation to any arm? (e.g., always ≥10% to control)" |
| Burn-in period | "How many patients enroll before the first update?" |
| Final analysis endpoint | "What is the primary endpoint for the final test?" |
| Type I error control | "Are you using group sequential boundaries or a fixed alpha at final?" |

## Common RAR Update Rules

### Proportional to observed response rate
```r
ratios <- pmax(response_rates, floor)  # floor = minimum allocation (e.g., 0.1)
ratios <- ratios / sum(ratios)
```

### Square-root transformation (reduces variance, closer to equal allocation)
```r
ratios <- sqrt(pmax(response_rates, floor))
ratios <- ratios / sum(ratios)
```

### Doubly-adaptive biased coin (DBCD) — ask if user wants more sophisticated rule

## Action Function: RAR Update

```r
action_rar <- function(trial, floor = 0.1, ...) {
  data <- trial$get_locked_data("<milestone_name>")
  
  # Compute response rates per arm (non-missing readout observations)
  arms <- c("control", "exp1", ...)  # fill from user
  rates <- sapply(arms, function(a) {
    arm_data <- data[data$arm == a & !is.na(data$<response_ep>), ]
    if (nrow(arm_data) == 0) return(NA_real_)
    mean(arm_data$<response_ep>)
  })
  
  # Handle NAs (arms with no data yet keep current ratio)
  if (any(is.na(rates))) return(invisible(NULL))
  
  # Update rule: proportional (customize per user)
  new_ratios <- pmax(rates, floor)
  new_ratios <- new_ratios / sum(new_ratios)
  
  trial$update_sample_ratio(arm_names = arms, sample_ratios = new_ratios)
  trial$save(value = t(new_ratios), name = paste0("ratios_", "<milestone_name>"))
}
```

## Action Function: Final Analysis

```r
action_final <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "final")

  # Primary analysis (customize per user — may be TTE even if RAR used binary response)
  # Example: logrank test for TTE primary
  # fit <- fitLogrank(formula = os ~ arm, data = data, reference = "control")
  # trial$save(value = fit$pvalue, name = "pvalue")
  # trial$save(value = as.integer(fit$pvalue < 0.025), name = "reject_h0")

  # Example: logistic for binary primary
  # fit <- fitLogistic(formula = response ~ arm, data = data)
  # trial$save(value = fit$pvalue["exp1"], name = "pvalue_exp1")
}
```

## Key Elicitation Questions for This Pattern

1. "What endpoint drives the adaptive randomization? (binary response is most common)"
2. "What is the primary confirmatory endpoint? (may differ from adaptive endpoint)"
3. "How frequently should randomization be updated? (every N patients)"
4. "What is the initial allocation ratio?"
5. "Is there a minimum allocation floor for any arm? (especially control)"
6. "What is the update rule? (proportional, sqrt, other)"
7. "How many total patients are planned?"
8. "How do you plan to control type I error given adaptive randomization?"
9. "What do you want to report? (power, average allocation to better arm, etc.)"

## Template File
See `templates/response_adaptive.R`

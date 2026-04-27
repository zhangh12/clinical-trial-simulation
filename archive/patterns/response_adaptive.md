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
   listener$add_milestones(m_rar1, m_rar2, m_final)
8. controller(trial = tr, listener = l) → $run(n = N)
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
action_rar <- function(trial, milestone_name, floor_ratio = 0.10, ...) {
  data <- trial$get_locked_data(milestone_name = milestone_name)
  arms <- c("control", "exp1", "exp2")  # fill from elicitation

  # DUMMY CONDITION: proportional to observed response rate with floor
  # Replace with actual rule (e.g., Thompson sampling, sqrt transformation, DBCD)
  rates <- sapply(arms, function(a) {
    d <- data[data$arm == a & !is.na(data$response), , drop = FALSE]
    if (nrow(d) == 0) return(NA_real_)
    mean(d$response)
  })

  if (any(is.na(rates))) return(invisible(NULL))  # skip if insufficient data

  new_ratios <- pmax(rates, floor_ratio)
  new_ratios <- new_ratios / sum(new_ratios)

  trial$update_sample_ratio(arm_names = arms, sample_ratios = as.numeric(new_ratios))
  trial$save(value = t(round(new_ratios, 3)), name = paste0("ratio_", milestone_name))
}
```

## Action Function: Final Analysis

```r
action_final <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "final")

  # Save observed allocation per arm
  alloc <- table(data$arm)
  for (a in names(alloc)) {
    trial$save(value = as.integer(alloc[a]), name = paste0("n_", a))
  }

  # DUMMY: logistic test — replace with actual primary analysis
  # For TTE primary: use fitLogrank() or fitCoxph()
  d_test <- data[data$arm %in% c("control", "exp1") & !is.na(data$response), ]
  if (nrow(d_test) > 0 && length(unique(d_test$arm)) == 2) {
    fit <- fitLogistic(formula = response ~ arm, placebo = "control",
                       data = d_test, alternative = "greater",
                       scale = "risk difference")
    trial$save(value = as.integer(fit$p[fit$arm == "exp1"] < 0.025), name = "reject_h0")
  } else {
    trial$save(value = NA_integer_, name = "reject_h0")
  }
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

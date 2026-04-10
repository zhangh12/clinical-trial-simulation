# Pattern: Seamless Phase II/III Adaptive Design

## What it is
A single trial that combines phase II (arm selection) and phase III (confirmatory) without a gap.
Phase II data is reused in the phase III analysis (statistically combined).
Saves time and patients compared to running two separate trials.

## Key Characteristics
- Multiple experimental arms + control enrolled from the start
- Interim milestone: select one (or few) experimental arm(s), drop the rest
- Phase III: selected arm + control continue enrollment
- Final milestone: combined phase II + III data for confirmatory analysis
- FWER controlled via closed testing / combination test (Dunnett)

## TrialSimulator Call Sequence

```
1. endpoint()     — primary TTE endpoint (usually); optional secondary
2. arm() × K+1   — K experimental arms + 1 control; each with its own generator
3. trial()        — combined phase II+III capacity (n_patients = phase2 + phase3)
   trial$add_arms(sample_ratio = c(1,...,1), ctrl, exp1, ..., expK)
4. milestone(name = "interim", when = eventNumber(endpoint = ep, n = n_interim), action = action_interim)
5. milestone(name = "final",   when = eventNumber(endpoint = ep, n = n_final),   action = action_final)
6. listener()
7. controller(trial = tr, listener = l) → $run(n_trials = N)
```

## Decision Points (What Varies Per User)

| Decision | Question to ask |
|----------|-----------------|
| Number of experimental arms K | "How many experimental arms?" |
| Arm selection criterion | "What metric decides which arm continues? (response rate, early OS, biomarker?)" |
| Selection rule | "Best arm only? Or all arms above a threshold?" |
| Phase II sample size / event count | "How many events trigger the interim?" |
| Phase III total event count | "How many total events for the final analysis?" |
| Whether to resize at interim | "Should total sample size be updated after arm selection?" |
| Alpha spending | "O'Brien-Fleming (asOF) or Pocock (asP)?" |
| Secondary endpoints | "Any secondary endpoints to test or save?" |

## Action Function: Interim (arm_selection)

```r
action_interim <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "interim")

  # --- Arm selection criterion (customize per user) ---
  # Example: select arm with highest response rate
  exp_arms <- c("exp1", "exp2")  # fill from user
  responses <- tapply(data$<response_ep>, data$arm, mean, na.rm = TRUE)
  best_arm <- names(which.max(responses[exp_arms]))
  arms_to_drop <- setdiff(exp_arms, best_arm)

  trial$remove_arms(arms_name = arms_to_drop)

  # Optional: resize for phase III
  # trial$resize(n_patients = <phase3_n>)

  trial$save(value = best_arm, name = "selected_arm")
}
```

## Action Function: Final Analysis

```r
action_final <- function(trial, ...) {
  
  dt <- trial$dunnettTest(
    formula      = <ep> ~ arm,
    placebo      = "control",
    treatments   = trial$get("selected_arm"),  # dynamically use selected arm
    milestones   = c("interim", "final"),       # combine both stages
    alternative  = "greater",
    planned_info = "oracle"
  )
  
  result <- trial$closedTest(
    dunnett_test   = dt,
    treatments     = trial$get("selected_arm"),
    milestones     = c("interim", "final"),
    alpha          = 0.025,
    alpha_spending = "asOF"
  )
  
  trial$save(value = as.integer(any(result$decision == "reject")), name = "reject_h0")
  trial$save(value = result$milestone_at_reject[1], name = "reject_at")
}
```

## Key Elicitation Questions for This Pattern

1. "What is the primary endpoint? Is it TTE?"
2. "How many experimental arms are you comparing to control?"
3. "What is the arm selection rule at the interim? (best responder, threshold, etc.)"
4. "What endpoint determines the interim trigger? (events, enrollment, time?)"
5. "What is the target number of events for the interim and final?"
6. "Should patients already enrolled continue after arm selection? (yes = seamless)"
7. "What alpha spending function do you prefer?"
8. "What operating characteristics do you want to report? (power, correct selection rate, etc.)"

## Template File
See `templates/seamless.R`

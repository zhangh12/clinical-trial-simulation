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
   listener$add_milestones(m_interim, m_final)
7. controller(trial = tr, listener = l) → $run(n = N)
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

## Action Function: Interim (arm selection)

```r
action_interim <- function(trial, ...) {
  data     <- trial$get_locked_data(milestone_name = "interim")
  exp_arms <- c("exp1", "exp2")  # fill from elicitation

  # DUMMY CONDITION: select arm with most OS events — replace with actual rule
  counts       <- tapply(data$os_event, data$arm, sum, na.rm = TRUE)
  best_arm     <- names(which.max(counts[exp_arms]))
  arms_to_drop <- setdiff(exp_arms, best_arm)

  if (length(arms_to_drop) > 0) {
    trial$remove_arms(arms_name = arms_to_drop)
  }

  # Optional SSR — DUMMY: inflate if event rate below expected
  # obs_rate <- mean(data$os_event, na.rm = TRUE)
  # new_n    <- ceiling(<n_events_final> / max(obs_rate, 0.01))
  # trial$resize(n_patients = max(new_n, <total_n_patients>))

  # Use distinct names for save_custom_data (within-replicate) and save (cross-replicate)
  # — they share a namespace; collisions error. Always set overwrite = TRUE on
  # save_custom_data so the registry resets between replicates.
  trial$save_custom_data(value = best_arm, name = "selected", overwrite = TRUE)
  trial$save(value = best_arm, name = "selected_arm")
}
```

## Action Function: Final Analysis

```r
action_final <- function(trial, ...) {
  data     <- trial$get_locked_data(milestone_name = "final")
  selected <- trial$get(name = "selected")
  if (is.null(selected)) selected <- "exp1"  # guard for edge cases

  dt <- trial$dunnettTest(
    formula      = Surv(os, os_event) ~ arm,   # TTE formula MUST use Surv()
    placebo      = "control",
    treatments   = selected,
    milestones   = c("interim", "final"),
    alternative  = "less",                     # "less" = lower hazard in treatment is good
    planned_info = "default"  # see knowledge/api/trial_methods.md for "default" vs pre-fixed data.frame
  )

  result <- trial$closedTest(
    dunnett_test   = dt,
    treatments     = selected,
    milestones     = c("interim", "final"),
    alpha          = 0.025,
    alpha_spending = "asOF"
  )

  trial$save(value = as.integer(any(result$decision == "reject")), name = "reject_h0")
  trial$save(value = as.character(result$milestone_at_reject[1]),  name = "reject_at")
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

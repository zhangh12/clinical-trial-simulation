# Pattern: Fixed Design

## What it is
A non-adaptive trial with a single (or small number of) milestone(s) for
final analysis. No interim selection, no resizing, no randomization
updates. The simplest design — and a good starting point when the user is
unsure about adaptation.

## Key Characteristics
- Fixed sample size and randomization ratios throughout
- One final-analysis milestone (sometimes one or two checkpoint milestones for diagnostics)
- Composite triggering condition is common: e.g., enroll N AND observe K events of endpoint E
- Statistical analysis at final via wrapper functions (`fitCoxph`, `fitLogrank`, `fitFarringtonManning`, `fitLogistic`, `fitLinear`)
- Multiplicity (if any) handled with Bonferroni or graphical testing

## TrialSimulator Call Sequence

```
1. endpoint() per arm × endpoint  (use helpers for correlated PFS+OS, mixtures, etc.)
2. arm() × K                       (K = #treatment arms incl. control)
3. trial()                         (n_patients, duration, enroller, dropout)
   trial$add_arms(sample_ratio = c(1,...,1), ctrl, exp1, ..., expK)
4. milestone(name = "final", when = <composite>, action = action_final)
   (optionally: 1-2 doNothing checkpoints to record event-count timing)
5. listener()
   listener$add_milestones(m_final)
6. controller(trial = tr, listener = l) → $run(n = N)
```

## Decision Points (What Varies Per User)

| Decision | Question to ask |
|----------|-----------------|
| Number of arms K | "How many arms?" |
| Endpoint(s) and types | (route to `elicitation/endpoint.md`) |
| Trigger for final analysis | "What ends the trial — enrollment, calendar time, event count, or a combination?" |
| Statistical test | "Cox / log-rank / logistic / linear / Farrington-Manning?" → choose one wrapper per endpoint |
| Multiplicity adjustment | "Single test? Or multiple endpoints with FWER control?" → Bonferroni or `GraphicalTesting` |
| Dry-run for timing | (suggest if user is uncertain about composite trigger timing) |

## Action Function: Final Analysis

```r
action_final <- function(trial, ...) {
  data <- trial$get_locked_data("final")

  # One wrapper per endpoint; pick the one matching endpoint type and analysis plan
  fit_pfs <- fitCoxph(Surv(pfs, pfs_event) ~ arm, placebo = "control",
                      data = data, alternative = "less", scale = "hazard ratio")
  fit_os  <- fitLogrank(Surv(os, os_event) ~ arm, placebo = "control",
                        data = data, alternative = "less")

  # Bonferroni split: 0.05/4 across PFS_low, PFS_high, OS_low, OS_high
  fit_pfs$decision <- ifelse(fit_pfs$p < 0.05/4, "reject", "accept")
  fit_os$decision  <- ifelse(fit_os$p  < 0.05/4, "reject", "accept")

  trial$save(value = fit_pfs[fit_pfs$arm == "low",  c("estimate", "decision", "info")], name = "pfs_low")
  trial$save(value = fit_pfs[fit_pfs$arm == "high", c("estimate", "decision", "info")], name = "pfs_high")
  trial$save(value = fit_os[fit_os$arm   == "low",  c("decision", "info")],            name = "os_low")
  trial$save(value = fit_os[fit_os$arm   == "high", c("decision", "info")],            name = "os_high")
}
```

## Pre-Simulation Sanity Check (recommended)

For composite event-count triggers, the user is often unsure if the trigger fires within `duration`. Run a small `dry_run` first to check:

```r
ctr$run(n = 50, dry_run = TRUE, plot_event = FALSE, silent = TRUE)
summarizeMilestoneTime(ctr$get_output())
ctr$reset()
ctr$run(n = 1000, plot_event = FALSE, silent = TRUE)   # real run
```

This is recommended in the `fixedDesign` vignette and worth offering when the user has not pre-validated the trigger threshold.

## Key Elicitation Questions for This Pattern

1. "Endpoints, types, distributions per arm" → `elicitation/endpoint.md` + `elicitation/data_generator.md`
2. "Sample size, duration, enrollment" → `elicitation/trial.md`
3. "What ends the trial?" → composite of `enrollment()`, `calendarTime()`, `eventNumber()`
4. "Statistical test per endpoint" → choose wrapper
5. "Multiplicity adjustment?" → Bonferroni / `GraphicalTesting`
6. "What to report?" → `elicitation/operating_chars.md`

## Template File
See `templates/fixed.R`

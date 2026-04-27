# Operating Characteristics Elicitation Guide

## Goal
Determine which metrics the user wants to summarize across simulation
replicates, and **which** are saved automatically vs. need manual
`trial$save()` calls.

> **First read `knowledge/api/auto_outputs.md`.** Many metrics the user
> requests (trial duration, event count at interim, sample size by arm)
> are saved **automatically** at every milestone — never duplicate them
> with manual saves.

---

## Common Metrics → Save Calls Reference

| Metric | Source | How to access / save |
|---|---|---|
| Trial duration | auto-saved | `out[["milestone_time_<final>"]]` |
| Time at interim | auto-saved | `out[["milestone_time_<interim>"]]` |
| Number of events at interim | auto-saved | `out[["n_events_<interim>_<os>"]]` |
| Number of patients at milestone | auto-saved | `out[["n_events_<milestone>_<patient_id>"]]` |
| Per-arm allocation at final | auto-saved (data.frame col) | `out[["n_events_<final>_<arms>"]]` |
| Power (reject H0) | manual | `trial$save(value = as.integer(p < alpha), name = "reject_h0")` |
| p-value | manual | `trial$save(value = fit$p[fit$arm == "exp1"], name = "pvalue")` |
| Effect estimate (HR / OR / RD) | manual | `trial$save(value = fit$estimate[fit$arm == "exp1"], name = "hr")` |
| Selected arm (seamless) | manual | `trial$save(value = best_arm, name = "selected_arm")` |
| Correct selection indicator | manual | `trial$save(value = as.integer(best_arm == "exp1"), name = "correct_selection")` |
| Early stop indicator | manual | `trial$save(value = as.integer(stopped_efficacy), name = "stop_efficacy")` |
| Updated randomization ratios (RAR) | manual | `trial$save(value = t(round(new_ratios, 3)), name = paste0("ratio_", milestone_name))` |
| Per-arm/per-endpoint stats | manual (1-row slice) | `trial$save(value = fit[fit$arm=="low", c("estimate","p","info")], name = "pfs_low")` |

---

## Question Sequence

### Step 1: Confirm headline metrics

"What are the headline operating characteristics you want to report?"

Common answers (probe each):
- **Power** — "What significance level? One-sided or two-sided?" → choose alpha (default one-sided 0.025) and direction
- **Type I error rate** — agent should remind user that a separate null-hypothesis simulation is needed (run with HR = 1)
- **Correct arm selection probability** (seamless / dose-finding)
- **Expected sample size at trial end** (already auto-saved per arm; just summarize)
- **Expected trial duration** (auto-saved as `milestone_time_<final>`)
- **Probability of early stopping** (efficacy and/or futility)
- **Average response rate / HR estimate** (effect summary)

### Step 2: Per-endpoint detail

"For each endpoint, do you want power for that endpoint specifically, or is one combined power sufficient?"

- One combined → save `reject_h0` only
- Per-endpoint → save `reject_pfs`, `reject_os`, etc., and a combined "any reject" indicator
- Family-wise (multi-endpoint with FWER): use `GraphicalTesting` — see `knowledge/api/advanced_testing.md`

### Step 3: Adaptation diagnostics (if applicable)

For seamless / dose-ranging / RAR designs, also ask:
- "Do you want to track which arm was selected at each interim?" → `trial$save(name = "selected_arm")`
- "Do you want to record the futility decision distribution?" → `trial$save(name = "futility_decision")`
- "For RAR, do you want to record the randomization ratio after each update?" → save per-update ratios

---

## Output: Save Plan

Before code generation, present a parameter table summarizing **what will be saved manually** vs. **what is auto-saved**, with column names and how each maps to a downstream summary statistic. Get explicit user confirmation per the feedback rule.

Example presentation:

```
Manual saves (one row per replicate in get_output()):
  reject_h0          ← integer 0/1; for "power = mean(reject_h0)"
  selected_arm       ← character; for "correct selection rate"
  hr                 ← numeric; for "mean HR estimate"

Auto-saved (every triggered milestone):
  milestone_time_<interim>         ← time of arm selection
  milestone_time_<final>           ← trial duration
  n_events_<final>_<os>            ← total OS events
  n_events_<final>_<arms>          ← per-arm event counts (data.frame col)
```

---

## Post-Simulation Summary Code

After validation, the script should also include compact summary code at the end:

```r
out <- ctr$get_output(tidy = TRUE)   # drop auto bookkeeping unless user wants it

cat("Power:                  ", mean(out$reject_h0,        na.rm = TRUE), "\n")
cat("Correct selection rate: ", mean(out$selected_arm == "exp1", na.rm = TRUE), "\n")
cat("Mean HR estimate:       ", mean(out$hr,               na.rm = TRUE), "\n")

# Milestone timing distributions (auto-saved)
mt <- summarizeMilestoneTime(ctr$get_output())
print(mt)
```

---

## Notes for Agent

- **Default to recording** `reject_h0`, the effect estimate, and (for adaptive designs) the adaptation decision. These are universal.
- **Don't re-save trial duration** — it's `milestone_time_<final>` automatically.
- Use `t(round(ratios, 3))` to save a 1-row vector of ratios (not a matrix); otherwise `trial$save()` errors.
- For metrics that need the data frame from a fit, use `trial$save(value = fit[fit$arm == "X", c("estimate","p","info")], name = "X")` — this saves a 1-row data.frame and `name` is used as a prefix.
- If the user mentions "Type I error", remind them simulations under H0 require flipping the data generators to no-effect (HR = 1, equal response rates). Same script structure, different `endpoint()` parameters.

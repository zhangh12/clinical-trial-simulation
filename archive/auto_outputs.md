# Automatically Saved Outputs at Milestones

Whenever a milestone is triggered, `TrialSimulator` automatically records a
fixed set of bookkeeping columns in `controller$get_output()` — even when
`action = doNothing`. **The agent must not redundantly save these via
`trial$save()`.**

## Auto-saved columns (one per replicate)

| Column pattern | Type | What it records |
|---|---|---|
| `milestone_time_<name>` | scalar | Calendar time at which milestone `<name>` triggered |
| `n_events_<milestone>_<endpoint>` | scalar | Observed events (TTE) or non-missing readouts (non-TTE) for `<endpoint>` at `<milestone>` |
| `n_events_<milestone>_<patient_id>` | scalar | Number of enrolled patients at `<milestone>` |
| `n_events_<milestone>_<arms>` | data.frame | Per-arm event/sample counts at `<milestone>` |

Examples: `milestone_time_<interim>`, `n_events_<final>_<os>`, `n_events_<dose selection>_<patient_id>`, `n_events_<final>_<arms>`.

## Implications for action-function design

- **Trial duration**: don't save `milestone_time_*` manually — it's already there. To compute mean trial duration across replicates: `mean(out[["milestone_time_<final>"]])`.
- **Event counts at interim**: don't save `n_events_*` manually. To extract: `out[["n_events_<interim>_<os>"]]`.
- **Sample size by arm**: read `out[["n_events_<final>_<arms>"]]` (a list-column of data.frames), don't save `tapply(...)` derivatives.

## What you DO need to save manually

- Hypothesis-test decisions: `reject_h0`, `selected_arm`, `pvalue`, `estimate` (HR / RD / coef)
- Custom decision flags: `interim_decision`, `kept_arm`, `early_stop`, `correct_selection`
- Model-output slices: `trial$save(value = fit[fit$arm == "exp1", c("estimate", "p")], name = "exp1")`
- Cross-milestone state (within a replicate): `trial$save_custom_data(value = best_arm, name = "selected_arm")` — retrieved with `trial$get(...)`

## Speeding up large simulations

Auto-saving every milestone × endpoint combination can balloon the output
when there are many milestones / endpoints / arms. Two options:

```r
# (a) Drop them from the returned data.frame at retrieval time
out <- ctr$get_output(tidy = TRUE)   # keeps user-saved columns only

# (b) Skip computing them at all (faster, ~40%):
trial$tidy_output(TRUE)              # call before controller$run()
```

`tidy = TRUE` matches the regex `^n_events_<.*?>_<.*?>$` and
`^milestone_time_<.*?>$` — if you save a custom column whose name matches
that pattern, it will be dropped too. Pick distinctive `name` values when
calling `trial$save()` to avoid collisions.

## Naming convention summary (for parsing in post-processing)

```
milestone_time_<MS>
n_events_<MS>_<ENDPOINT>            # one column per (milestone, endpoint)
n_events_<MS>_<patient_id>          # enrolled count
n_events_<MS>_<arms>                # data.frame: rows = arms, cols = endpoints
```

`<MS>` and `<ENDPOINT>` are the names from `milestone(name = ...)` and
`endpoint(name = ...)` respectively. They are *not* sanitized — spaces
and punctuation are preserved, so column access requires backticks or
double-bracket: ``out[["n_events_<dose selection>_<pfs>"]]``.

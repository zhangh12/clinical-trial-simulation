# Sub-Agent: Fixed Design

## Activation
Load when no adaptation is planned:
- Single endpoint or a small fixed set of endpoints
- One final-analysis milestone (occasionally one or two diagnostic checkpoints)
- No interim selection, no resizing, no randomization updates
- Multiplicity (if any) handled by Bonferroni or `GraphicalTesting`

## Knowledge to Load
- `knowledge/patterns/fixed.md` — full pattern spec
- `knowledge/api/building_blocks.md`
- `knowledge/api/trial_methods.md`
- `knowledge/api/auto_outputs.md`
- `knowledge/api/helpers.md`
- `elicitation/data_generator.md`
- `elicitation/parameter_determination.md`
- `elicitation/operating_chars.md`

## Elicitation Checklist

Work through these in order. Skip any already answered in Phase 1 of `main_agent.md`.

### Endpoints
- [ ] Endpoint name(s) and type (TTE / non-TTE)
- [ ] If correlated PFS+OS: medians per arm + correlation (Kendall's tau if Cox/log-rank planned, Pearson if `solveThreeStateModel` route)
- [ ] If non-TTE: readout time + distribution + per-arm parameters

### Arms
- [ ] Arm names (incl. control)
- [ ] Allocation ratio
- [ ] Any inclusion-criteria filter (`arm(name, biomarker == "positive")`)

### Trial
- [ ] Sample size + duration + units (`elicitation/trial.md`)
- [ ] Enroller pattern (`accrual_rate` data.frame)
- [ ] Dropout? (`weibullDropout` if 2 landmarks, exponential if 1)
- [ ] Stratification factors? (define as `non-tte readout = 0` endpoints)

### Final Analysis Milestone
- [ ] Trigger condition: `enrollment()`, `calendarTime()`, `eventNumber()`, or composite via `&` / `|`
- [ ] Statistical test per endpoint: `fitCoxph`, `fitLogrank`, `fitFarringtonManning`, `fitLogistic`, `fitLinear`
- [ ] Alpha: 0.05 / Bonferroni split? Or graphical testing?

### Operating Characteristics
- [ ] Power per endpoint per arm
- [ ] Effect estimate (HR / RD / OR / coef)
- [ ] Trial duration → already auto-saved as `milestone_time_<final>`
- [ ] (Optional) early-event-count diagnostic milestone

## Pre-Trial Sanity Check (offer this to the user)

For composite event-count triggers, a `dry_run` simulation reveals trigger-time distributions before committing to a full simulation:

```r
ctr$run(n = 50, dry_run = TRUE, plot_event = FALSE, silent = TRUE)
summarizeMilestoneTime(ctr$get_output())
```

Do NOT include the `dry_run` block in the final delivered script.

## Code Generation
Use `templates/fixed.R` as base. Fill all `<...>` placeholders.

Customization points:
1. Endpoint definitions — generators per arm (use helpers from `helpers.md` if user gave landmark probabilities, mixtures, etc.)
2. `action_final` — pick correct wrapper per endpoint; Bonferroni `alpha_each` per hypothesis
3. Composite trigger in `m_final$when`
4. `accrual` data frame
5. Optional `dropout` via `weibullDropout`

## Validation
Follow `validation/validate.md`. For correlated endpoints with NORTA/`solveThreeStateModel`, run the slow helpers offline first and hardcode the resolved literals.

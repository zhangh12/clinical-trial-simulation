# Sub-Agent: Response-Adaptive Randomization (RAR) Design

## Activation
Load when main agent has identified a RAR pattern:
- User wants randomization ratios to change during the trial
- Better-performing arms should attract more patients
- Usually involves a fast-readout response endpoint

## Knowledge to Load
- `knowledge/patterns/response_adaptive.md` — full pattern spec and action function templates
- `knowledge/api/building_blocks.md`
- `knowledge/api/trial_methods.md`
- `elicitation/data_generator.md`
- `elicitation/action_function.md`

## Elicitation Checklist

### Adaptive Endpoint (drives randomization updates)
- [ ] Endpoint name and type (usually binary non-TTE; confirm)
- [ ] Readout time (how many weeks/months after enrollment?)
- [ ] Response rate per arm (control + each experimental)

### Primary Endpoint (for final hypothesis test)
- [ ] Same as adaptive endpoint, or different? (e.g., binary response drives RAR, TTE is primary)
- [ ] If different: also elicit generator for primary endpoint

### Arms
- [ ] Control arm name
- [ ] Number and names of experimental arms
- [ ] Initial allocation ratio (default: equal)
- [ ] Minimum allocation floor per arm (default: 10%; especially important for control)

### RAR Update Schedule
- [ ] How many updates during the trial?
- [ ] What triggers each update: enrollment(N) or calendarTime(T)?
- [ ] First update: after how many patients? (burn-in period)
- [ ] Subsequent updates: every N patients?

### Update Rule
- [ ] Proportional to observed response rate (default, simplest)
- [ ] Square-root transformation (less extreme shifts)
- [ ] User-defined rule (ask for formula or code)
- [ ] Should control arm ratio be fixed or also adaptive?

### Final Analysis
- [ ] Trigger: enrollment(N_total) or calendarTime(T_max), or whichever first
- [ ] Statistical test: logistic? logrank? Dunnett?
- [ ] Significance level and one-sided/two-sided

### Operating Characteristics to Save
- [ ] Power (reject H0) — always
- [ ] Mean allocation per arm — key metric for RAR
- [ ] Proportion of patients on best arm
- [ ] Trial duration (if relevant)

## Code Generation
Use `templates/response_adaptive.R` as base. Fill all `<...>` placeholders.
Key customization points:
1. Generator functions — response rates from elicitation
2. `ep_*` endpoint definitions — readout time in correct units
3. `action_rar` — arms list, response column name, update rule, floor
4. RAR milestone definitions — enrollment triggers
5. `action_final` — correct statistical test for primary endpoint
6. `trial()` — n_patients, duration, enroller parameters

## Validation
After generation, follow `validation/validate.md`.
Watch especially for:
- `readout` units match `duration` units in `trial()`
- `action_rar` milestone_name arg matches milestone `name`
- `update_sample_ratio` arm_names match defined arm names exactly
- Final analysis test matches the primary endpoint type

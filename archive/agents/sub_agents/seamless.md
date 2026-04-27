# Sub-Agent: Seamless Phase II/III Design

## Activation
Load when main agent has identified a seamless II/III pattern:
- Multiple experimental arms starting together
- Interim arm selection
- Combined phase II + III analysis for confirmatory test

## Knowledge to Load
- `knowledge/patterns/seamless.md` — full pattern spec and action function templates
- `knowledge/api/building_blocks.md`
- `knowledge/api/trial_methods.md` — note: `dunnettTest(planned_info = "default")`, NOT `"oracle"`
- `knowledge/api/auto_outputs.md`
- `knowledge/api/helpers.md`
- `elicitation/data_generator.md`
- `elicitation/parameter_determination.md`
- `elicitation/action_function.md`

## Elicitation Checklist

Work through these in order. Skip if already answered in Phase 1.

### Endpoints
- [ ] Primary endpoint name and type (usually TTE: OS or PFS)
- [ ] Generator per arm: median survival for control + HR per experimental arm
- [ ] Dropout model (if any)

### Arms
- [ ] Control arm name
- [ ] Number and names of experimental arms
- [ ] Initial allocation ratio (default: equal)

### Interim (Arm Selection) Milestone
- [ ] Trigger: number of events of which endpoint? or enrollment count?
- [ ] Selection criterion: response rate? early TTE signal? biomarker? best-of-K?
- [ ] Selection rule: strictly best arm, or all above threshold?
- [ ] What happens to dropped arms' enrolled patients? (they continue follow-up, just no new enrollment)
- [ ] Sample size update at interim? If yes, new N?

### Final Analysis Milestone
- [ ] Total event count for final analysis
- [ ] Alpha spending: asOF (O'Brien-Fleming, default) or asP (Pocock)?
- [ ] Significance level (default: one-sided 0.025)

### Operating Characteristics to Save
- [ ] Power (reject H0) — always
- [ ] Correct arm selection rate — usually
- [ ] Expected sample size — if resize is used
- [ ] Trial duration — if set_duration is used

## Code Generation
Use `templates/seamless.R` as base. Fill all `<...>` placeholders.
Key customization points:
1. `gen_control` and `gen_exp` functions — parameters from elicitation
2. `action_interim` — selection criterion + arms_to_drop logic
3. `action_final` — dunnettTest formula, treatments arg (use saved selected_arm)
4. milestone `when` conditions — event counts from elicitation
5. `trial()` call — n_patients, duration, enroller parameters

## Validation
After generation, follow `validation/validate.md`.
Watch especially for:
- `selected_arm` saved in interim and correctly retrieved in final
- `milestones = c("interim", "final")` in both dunnettTest and closedTest
- Arm names consistent throughout

# Sub-Agent: Dynamic Treatment Switching

## Activation
Load when user describes:
- Patients changing treatment mid-study based on a patient-level event
  (progression, non-response, AE, scheduled visit, etc.)
- Crossover after progression / rescue therapy / dose escalation on poor response
- Causal AFT-style analysis OR ITT with crossover

For *crossover with washout* (sequential treatments at fixed visits — Latin
square AB/BA), use the longitudinal-endpoints approach instead — see
`crossoverWashout.Rmd` vignette pattern, NOT `regimen()`.

## Knowledge to Load
- `knowledge/patterns/treatment_switching.md` — full spec
- `knowledge/api/building_blocks.md` — `regimen()` definition
- `knowledge/api/trial_methods.md` — `add_regimen()`, `expandRegimen()`
- `knowledge/api/helpers.md` — `expandRegimen()`
- `elicitation/data_generator.md`
- `elicitation/action_function.md`

## Elicitation Checklist

### Switching Population
- [ ] Which arm(s) eligible to switch?
- [ ] Subgroup filters (biomarker, response status, demographic)?
- [ ] Edge case: patients who die at the trigger event (e.g., `os == pfs`) — usually excluded

### Destination
- [ ] Single destination treatment, or randomized among options?
- [ ] If randomized, what probabilities? (e.g., 30% low / 40% high / 30% stay)

### Switching Time (`when`)
- [ ] At a specific event (progression / response readout)?
- [ ] At a fixed delay after the event?
- [ ] Random time between two events (e.g., between PFS and OS)?
- [ ] **No NAs allowed** in `switch_time` for any selected switcher

### Outcome Modification (`how`)
- [ ] Which endpoints change post-switch?
- [ ] Modification model:
  - "Extend residual survival by factor f": `os_new = switch_time + f * (os - switch_time)`
  - "Replace post-switch hazard": draw new tail from new distribution
  - "Reset response to a new draw"
- [ ] Endpoints not modified can be omitted from the returned data.frame
- [ ] **NEVER apply dropout/censoring inside `how`** — the package handles it

### Multi-Stage Switching
- [ ] Single switch only, or multiple rounds?
- [ ] If multi-stage: `what`/`when`/`how` become **lists** of functions

### Analysis
- [ ] ITT (analyze original arm assignment) or causal-adjustment?
- [ ] Test wrapper for primary endpoint
- [ ] Diagnostic: crossover rate, time-to-switch distribution

## Code Generation
Use `templates/treatment_switching.R` as base. Fill all `<...>` placeholders.

Critical ordering — error if violated:
```r
tr <- trial(...)
tr$add_regimen(reg)        # <-- MUST come BEFORE add_arms
tr$add_arms(...)
```

Customization points:
1. `treatment_allocator` (`what`) — `case_when` logic for who switches and to what; return `data.frame(patient_id, new_treatment)`
2. `time_selector` (`when`) — return `data.frame(patient_id, switch_time)` with no NAs
3. `data_modifier` (`how`) — return `data.frame(patient_id, <modified columns>)`
4. `expandRegimen()` in action function for crossover diagnostics

## Important Conventions

- All three regimen functions take `patient_data` as the only argument
- `what` returns one row per *switcher only* (others omitted via `NA` in `new_treatment`)
- `when` returns one row per row in its input (input is the subset that `what` selected)
- `how` returns only the modified columns + `patient_id`; unchanged cells = `NA`
- A single arm definition still represents the original randomized assignment — switching modifies *data*, not arm labels (the `arm` column in locked data preserves randomized assignment)

## Validation
Follow `validation/validate.md`. Common pitfalls:
- Calling `add_regimen()` after `add_arms()` → package errors
- `when` returning NAs → error
- Modifying censoring/event indicators in `how` → undefined behavior
- `expandRegimen()` called on data without a registered regimen → no `regimen_trajectory` column → error

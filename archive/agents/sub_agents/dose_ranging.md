# Sub-Agent: Dose-Ranging / Adaptive Arm Addition

## Activation
Load when user describes:
- Starting with placebo + few doses (often only the highest)
- Adding more doses mid-trial based on an interim signal
- Final dose-response analysis (often MCPMod via `DoseFinding`)

## Knowledge to Load
- `knowledge/patterns/dose_ranging.md`
- `knowledge/api/building_blocks.md`
- `knowledge/api/trial_methods.md` — emphasis on `add_arms()` mid-trial
- `knowledge/api/auto_outputs.md`
- `elicitation/data_generator.md`
- `elicitation/parameter_determination.md`
- `elicitation/action_function.md`

## Elicitation Checklist

### Endpoint
- [ ] Endpoint name + type (binary response or continuous biomarker most common)
- [ ] Readout time
- [ ] Per-arm response (incl. arms that will be added later)

### Initial Arms
- [ ] Placebo + 1 (usually highest dose)
- [ ] Initial allocation ratio (default 1:1)

### Dose Levels (full set, including those added at interim)
- [ ] All dose levels under consideration
- [ ] Assumed response per dose

### Interim Trigger + Decision
- [ ] When does interim fire? (`eventNumber(<endpoint>, n = ?)`)
- [ ] Test used at interim: `fitLogistic` / `fitFarringtonManning` / `fitLinear`
- [ ] Decision rule: z-stat threshold (default 1.64 for one-sided 0.05)

### Post-Go Configuration
- [ ] Arms to add
- [ ] New randomization ratio across all arms (e.g., 1:2:2:2:1)

### Final Analysis
- [ ] Final trigger (`eventNumber(<endpoint>, n = N_total)`)
- [ ] Dose-response model: MCPMod is typical; ask which candidate models (`emax`, `sigEmax`, `betaMod`, `quadratic`)
- [ ] Final go/no-go thresholds (MCP p-value AND model-averaged effect threshold)

### Operating Characteristics
- [ ] Overall "go" probability (interim go AND final go)
- [ ] Early termination probability (interim no-go)
- [ ] Mean interim z-statistic
- [ ] (Optional) Per-dose response estimate distribution

## Code Generation
Use `templates/dose_ranging.R` as base. Fill all `<...>` placeholders.

Customization points:
1. `ep_pbo` and `ep_top` — initial endpoints
2. `go_nogo()` helper — define **outside** the action function; uses `DoseFinding::Mods`, `MCTtest`, `maFitMod`
3. `action_at_interim` — dose arms added inside; in simulation we always add them and recover the early-termination rate from `interim_decision`
4. `action_at_final` — calls `go_nogo()` and saves `decision`
5. Trigger thresholds: `<n_interim>`, `<n_final>`, `<go_threshold>`
6. `accrual` rate change after interim is common (slower while waiting for go signal, faster after)

## Important Conventions
- Define new arms **inside** the action function — they cannot exist before they are added
- Arms have full endpoint definitions (own `endpoint()` + `arm()` + `add_endpoints()`) right before `trial$add_arms()`
- Assumed response rates for added arms must be specified up front by the user — they are part of the simulation's data-generating model

## Validation
Follow `validation/validate.md`. Common pitfalls:
- `DoseFinding` package must be installed and loaded
- `mu_hat` and `S` from `glm` must align with the dose vector order
- `add_arms()` ratios are appended to existing ratios — confirm the post-add ratio is what the user wants (not just "1:2:2:2:1" but specifically the second-half pattern)

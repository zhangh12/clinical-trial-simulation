# PFS Group-Sequential Trial — Simulation Report

Trial: Phase 3 oncology, two-arm 1:1 (placebo vs. experimental), PFS primary
endpoint, group-sequential with one interim and one final analysis.

Companion script: `pfs_gs_sim.R`. Output: `pfs_gs_output.rds`,
`pfs_gs_milestone_summary.rds`, `milestone_times.png`.

---

## 1. Why this design

The brief was an implementation-mode spec: fixed group-sequential design
with a known target (HR 0.74, α 0.025 one-sided, 80% power), one interim at
66% information fraction, OBF α-spending, log-rank test. PFS is modeled as
exponential with a 60-month placebo median and a constant hazard ratio of
0.74, so Cox PH is valid and log-rank is the natural test. The main
modeling choices the user did not specify — trial duration cap, accrual
ramp discretization, GS test handling — were resolved with the user's
explicit confirmation in the parameter table below. The team's
follow-up about adaptive sample-size reassessment was deferred per the
user's instruction.

## 2. Confirmed parameters

| Group | Parameter | Value | Source |
|---|---|---|---|
| Endpoint | PFS distribution (placebo) | Exponential, rate `log(2)/60 ≈ 0.01155` | spec: median 60 mo |
| Endpoint | PFS distribution (experimental) | Exponential, rate `log(2)/60 × 0.74 ≈ 0.00855` | spec: HR 0.74 |
| Trial | n_patients | 1200 | spec |
| Trial | duration cap | 120 months | proposed default, user-confirmed |
| Trial | dropout | `rexp(rate = -log(0.975)/12 ≈ 0.00211)`, both arms | spec: 2.5% by 12 mo |
| Trial | accrual | piecewise: 9, 15, 21, 27, 33, 39 (months 1–6), 42 thereafter | linear ramp 6→42 over 6 mo, monthly bins |
| Trial | stratification | none | spec |
| Milestone | interim trigger | `eventNumber("pfs", n = 228)` | 66% × 346 |
| Milestone | final trigger | `eventNumber("pfs", n = 346)` | `4(z_α + z_β)² / log(HR)² = 345.7 → 346` |
| GS test | interim z-boundary | **2.413** (STUB, OBF α-spending at IF=0.66) | Lan-DeMets, hardcoded |
| GS test | final z-boundary | **1.985** (STUB, OBF α-spending at IF=1.0, accounting for ρ = √0.66) | Lan-DeMets, hardcoded |
| Run | replicates | 1000 | spec |
| Run | workers | 4 (`mirai`) | laptop default |

**STUB items** are in §9 Caveats.

## 3. Endpoints

PFS is the only endpoint. Two `endpoint()` calls, one per arm, sharing the
same exponential generator with arm-specific rates. The event indicator
column `pfs_event` is supplied automatically by `rexp` because PFS is the
only TTE; censoring at trial duration and dropout is handled by the
trial-level `duration` and `dropout` arguments.

```r
ep_pfs_placebo <- endpoint(
  name      = "pfs",  type = "tte",
  generator = rexp,   rate = log(2) / 60
)

ep_pfs_experimental <- endpoint(
  name      = "pfs",  type = "tte",
  generator = rexp,   rate = log(2) / 60 * 0.74
)
```

## 4. Arms

Two arms, 1:1 randomization, each carrying its arm-specific PFS endpoint.

```r
arm_placebo      <- arm(name = "placebo");      arm_placebo$add_endpoints(ep_pfs_placebo)
arm_experimental <- arm(name = "experimental"); arm_experimental$add_endpoints(ep_pfs_experimental)
```

## 5. Trial setup

1200 patients, accrued via `StaggeredRecruiter` with the piecewise schedule
(monthly bins approximating the 6→42 linear ramp, then 42/mo thereafter).
Expected accrual completion ≈ 31.1 months (144 in ramp + 1056 / 42 mo).
Dropout is exponential with rate calibrated to 2.5% by month 12.
Trial-level `duration = 120` is a generous calendar cap so the final
milestone never starves.

```r
accrual_rate <- data.frame(
  end_time       = c(1, 2, 3, 4, 5, 6, Inf),
  piecewise_rate = c(9, 15, 21, 27, 33, 39, 42)
)

dropout_fn <- local({
  rate <- -log(0.975) / 12
  function(n, ...) rexp(n = n, rate = rate)
})

tr <- trial(
  name = "pfs_gs", n_patients = 1200, duration = 120,
  enroller = StaggeredRecruiter, accrual_rate = accrual_rate,
  dropout  = dropout_fn
)
tr$add_arms(sample_ratio = c(1, 1), arm_placebo, arm_experimental)
```

The dropout rate is captured in a closure so `mirai` workers don't need
the script's global env at parallel-run time.

## 6. Milestones

Two event-driven milestones, in chronological order. OBF z-boundaries are
passed as extra arguments to each `milestone(...)` so the action functions
do not depend on globals (same parallelism reason as dropout).

| Milestone | When | Action | Expected trigger time (calibration) |
|---|---|---|---|
| `interim` | 228 PFS events accumulated | log-rank, save reject flag and z/p/HR | ~38.7 mo (median 38.6, SD 1.5) |
| `final` | 346 PFS events accumulated | log-rank, save reject flag and reject_overall | ~52.6 mo (median 52.6, SD 2.1) |

```r
m_interim <- milestone(
  name    = "interim",
  when    = eventNumber(endpoint = "pfs", n = 228),
  action  = action_interim,
  p_bound = p_bound_interim   # = 1 - pnorm(2.413) ≈ 0.00792
)

m_final <- milestone(
  name    = "final",
  when    = eventNumber(endpoint = "pfs", n = 346),
  action  = action_final,
  p_bound = p_bound_final     # = 1 - pnorm(1.985) ≈ 0.02358
)
```

## 7. Action functions

Both actions follow the same template: lock data, run log-rank, save the
rejection decision and diagnostics. `fitCoxph` is called for the
descriptive HR estimate only — the decision is driven by the log-rank
statistic.

### `action_interim`

- **Trigger:** 228 PFS events.
- **Data lock:** all enrolled patients with PFS observed (or censored) up
  to the trigger time.
- **Analysis:** one-sided log-rank, `Surv(pfs, pfs_event) ~ arm` with
  `placebo` as reference and `alternative = "less"` (treatment-better-when-lower).
  The p-value is compared to the OBF nominal bound `p_bound = 0.00792`.
- **Saves:** `reject_interim`, `z_interim`, `p_interim`,
  `hr_interim_estimate`. Also `save_custom_data("reject_interim_state",
  overwrite = TRUE)` so the final action can compute `reject_overall`.

### `action_final`

- **Trigger:** 346 PFS events.
- **Analysis:** same log-rank wrapper; p-value compared to `p_bound = 0.02358`.
- **Saves:** `reject_final`, `reject_overall = reject_interim_state OR reject_final`,
  `z_final`, `p_final`, `hr_final_estimate`.

The trial does not stop early in simulation: the final milestone fires
unconditionally so each replicate yields both the interim and final
decisions, enabling the standard tally `power_overall = mean(reject_overall)`.

## 8. Operating characteristics

**Run:** 1000 replicates, 4 workers, ~15 seconds total (~0.015 s/replicate).
0 errors.

| Question | Answer | MCSE | Source |
|---|---|---|---|
| Power at interim (early stop) | **0.426** | 0.016 | `mean(out$reject_interim)` |
| Overall power | **0.792** | 0.013 | `mean(out$reject_overall)` |
| Expected trial duration | **52.6 months** | — | `mean(out[["milestone_time_<final>"]])` |
| Mean interim trigger time | 38.7 months | — | `mean(out[["milestone_time_<interim>"]])` |

Overall power 0.792 is within one MCSE of the 0.80 target — the design
delivers approximately the planned operating characteristics. The small
shortfall is consistent with the 346-event ceiling rounding (target was
345.7) and the rounded OBF boundaries; expect a small upward bump if the
real `GroupSequentialTest` boundaries replace the stub.

### Stagewise rejection cross-tab

|                 | reject_final = 0 | reject_final = 1 |
|---|---|---|
| reject_interim = 0 | 208 | 366 |
| reject_interim = 1 | 8   | 418 |

Note: `reject_final` is computed on every replicate (the trial does not
stop in simulation), so the 8 cases that reject at interim but not final
reflect downstream event-accumulation noise — the design would have
stopped at the interim, so the final result is hypothetical.

### Milestone times (1000 replicates)

| Milestone | mean | median | SD |
|---|---|---|---|
| interim | 38.69 | 38.57 | 1.54 |
| final   | 52.61 | 52.60 | 2.05 |

See `milestone_times.png` for the distribution plot
(`summarizeMilestoneTime(out) %>% plot()`).

### HR estimate diagnostics (sanity check)

| Stage | mean | median | SD |
|---|---|---|---|
| interim | 0.746 | 0.742 | 0.098 |
| final   | 0.743 | 0.742 | 0.081 |

Centered on 0.74 as designed; SD shrinks from interim to final as more
events accumulate.

## 9. Caveats and limitations

- **STUB: O'Brien-Fleming z-boundaries are hardcoded** (interim 2.413,
  final 1.985). Per skill convention, the real `GroupSequentialTest` is
  not yet wired. The hardcoded values are derived from the standard
  Lan-DeMets OBF α-spending function with one-sided α = 0.025 and the
  stage correlation `√0.66`; replacing them with rpact-computed
  boundaries (or `GroupSequentialTest` once supported) is straightforward
  and likely shifts overall power by < 0.01.
- **Event-count rounding.** Target events from the closed-form formula
  is 345.7; we use 346. Interim is round(0.66 × 346) = 228, exactly 65.9%
  IF in practice. Both round-offs are conservative (slightly fewer events
  → slightly less power).
- **Accrual ramp discretization.** The user's linear 6→42 ramp is
  approximated by 1-month bins with averaged rates. Total patients in
  the ramp (144) match the linear average exactly; the patient-level
  accrual time distribution differs slightly from the strict linear
  ramp.
- **Constant HR / PH assumption** is built into the data generator
  (independent exponentials with constant rates). If the team wants to
  stress-test under non-PH (delayed effect, crossing hazards), switch
  the generator to `PiecewiseConstantExponentialRNG` with arm-specific
  hazard ratios per period.
- **Adaptive SSR not modeled** per user instruction. Hook for a future
  iteration: replace the interim action with one that computes
  conditional power and calls `trial$resize()` based on a pre-specified
  promising-zone rule.
- **No reproducible seed.** `seed = NULL` lets TrialSimulator pick a per-replicate
  seed; the run summary at the top of the script log shows it. For
  exact reproducibility set `trial(..., seed = <int>)`.

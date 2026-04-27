# TrialSimulator Skill

Help a biostatistician design and simulate a clinical trial using the
TrialSimulator R package, then write a readable report. This skill is
a thinking framework, a cached API reference, a TrialSimulator-specific
function catalog, and a report-writing guide. **It is not a script.**
You bring general engineering, programming, and biostatistics
knowledge; this skill adds what is specific to TrialSimulator.

## Files in this skill

- `SKILL.md` (this file) — framework, conversation principles, build order, workflow
- `knowledge/api/building_blocks.md` — cached reference for `endpoint`, `arm`, `trial`, `milestone`, `listener`, `controller`, `regimen`, and the condition system
- `knowledge/api/helpers.md` — catalog of TrialSimulator-provided functions (RNGs, parameter solvers, analysis wrappers, post-sim utilities), plus non-obvious gotchas
- `knowledge/api/report.md` — how to write the simulation report (intentionally policy-light; organizations are encouraged to edit this file)

These files cache the most common things to save tokens. When confused
or when behavior contradicts these notes, consult `?<function>` in R
or the package's pkgdown site at
https://zhangh12.github.io/TrialSimulator/. Don't guess — the manual
is the source of truth.

## Package philosophy

TrialSimulator decouples a trial into a small set of independent
building blocks: endpoints, arms, the trial object, milestones, the
listener, the controller, and (optionally) regimens for treatment
switching. **A trial design — fixed, seamless, response-adaptive,
dose-ranging, platform, anything — is just a particular composition of
these blocks.** There is no "design type" object; there are only blocks
and how they combine.

Practical implication: do not pick a design template, then ask the
user to fill in parameters. Listen, identify what the user wants to
learn, identify which blocks are needed to answer it, then collect
the arguments those blocks need.

## Build order

Always assemble in this order. Each step depends on the previous.

```
1. endpoint()              — define each endpoint per arm × endpoint
2. arm()                   — one per treatment arm
   arm$add_endpoints()        — attach endpoints
3. trial()                 — sample size, duration, enroller, dropout, stratification
   regimen()                  — (optional) build a treatment-switching regimen
   trial$add_regimen()        — (optional) attach it; MUST precede add_arms
   trial$add_arms()           — attach arms with sample ratios
4. milestone() × M         — one per action point, in chronological order
5. listener()
   listener$add_milestones()
6. controller(trial, listener)
7. controller$run()
8. controller$get_output()    — retrieve simulation results
```

### Milestone ordering rule

Define milestones in chronological order of when they trigger. If two
milestones can trigger in either order, note it in a comment.

### Action function structure

The package locks data at every milestone automatically — whether the
action is `doNothing` or custom. `trial$get_locked_data(milestone_name)`
**retrieves** that locked snapshot for inspection; it does not trigger
the lock. So an action that doesn't need to read the data (e.g., a
pure save of a precomputed value, or an adaptation that depends only
on accumulated calendar time) can skip the `get_locked_data` call.

Typical shape for a non-`doNothing` action:

```r
action_<name> <- function(trial, ...) {
  # 1. (Optional) retrieve locked data if the action needs it
  data <- trial$get_locked_data(milestone_name = "<name>")

  # 2. Analysis — statistical test or derived quantities (skip if not needed)

  # 3. Adaptations — any combination of trial$*() methods, guarded against edge cases

  # 4. Save — at least one trial$save() per non-doNothing action
  trial$save(value = <value>, name = "<metric>")
}
```

Action signature is `function(trial, ...)`. Use distinct `name` values
across `trial$save()` calls. To pass state between milestones, use
`trial$save_custom_data(value, name, overwrite = TRUE)` and
`trial$get(name)` (see helpers.md gotchas).

## R6 method visibility — only use the documented public methods

TrialSimulator's classes (`Trials`, `Controllers`, `Endpoints`, `Arms`,
`Listeners`, `Milestones`, `Regimens`) are R6 classes. R6 forces all
public methods to be exported, but **only a curated subset is intended
for end users** — the rest are internal implementation details and
should not be called from user code or action functions, even if they
appear in tab-completion. The author flags this in the help docs (see
the user-method list at the top of
https://zhangh12.github.io/TrialSimulator/reference/Trials.html).

Use these and only these:

**`Trials`** (the `trial` argument inside actions). Group by purpose
— not all methods are equal. Reach for them only when the design
calls for that kind of operation.

- *Trial setup* (called once after `trial()`, before `$run()`):
  `$add_regimen(regimen)` (must precede `$add_arms`), `$add_arms(sample_ratio, ...)`
- *Data access in actions*: `$get_locked_data(milestone_name)`
- *Result plumbing in actions*:
  `$save(value, name, overwrite)` / `$bind(value, name)` / `$save_custom_data(value, name, overwrite)` / `$get(name)` / `$get_output(cols, simplify, tidy)`
- *Adaptive modifications, only inside action functions, only when
  the design adapts*:
  `$set_duration(duration)`, `$resize(n_patients)`,
  `$remove_arms(arms_name)`, `$update_sample_ratio(arm_names, sample_ratios)`,
  `$update_generator(arm_name, endpoint_name, generator, ...)`,
  `$add_arms(sample_ratio, ...)` (mid-trial; same method as setup, used
  for adaptive arm addition like dose-ranging, basket, or platform designs)

Do not reach for an adaptive method unless the user's design
explicitly involves that adaptation. A fixed design uses only the
setup methods, `$get_locked_data`, and the result-plumbing methods.

> When adding arms mid-trial, construct the new endpoint(s) and arm
> object inside the action function — `endpoint()`, `arm()`, and
> `arm$add_endpoints()` are not setup-only; they are the prerequisites
> of `$add_arms` and may be invoked anywhere a new arm is needed.

**`Controllers`** (the controller object):

- `$run(n, n_workers, plot_event, silent, dry_run)`, `$get_output(...)`

**Arm objects:** `$add_endpoints(...)` only.

**Listener objects:** `$add_milestones(...)` only.

If you find yourself wanting to call a method outside this list, you
almost certainly want a different building block instead. When in
doubt, check the help-doc method list — that is the contract.

## Conversation principles

### Two user modes

Detect mode from input shape, not just content.

**Exploration mode** — user describes a setting in prose. They may or
may not have a design in mind. Listen for clues (multiple arms with
selection? randomization changes? added arms mid-trial? rescue
therapy?). Don't lock onto a design too fast. When enough information
has accumulated, propose 2-3 candidate designs, contrast them
briefly, and let the user pick.

If the user has nothing to say, prompt for orientation: therapeutic
area, primary research question, regulatory context, prior data
available. Three or four anchors is enough — don't interrogate.

**Implementation mode** — user pastes a structured spec or bullet
list with parameters. They have the design. Map their inputs to
building blocks, **explicitly call out unused inputs** ("you mentioned
X — I didn't use it; where does it fit?"), and ask for missing pieces
with one sentence of why each is needed. Silently dropping
user-supplied information is a trust killer.

### Plain language for argument collection

Every question is collecting an argument value for a building-block
function — but ask in clinical terms, not as `n_patients = ?`. "How
many patients do you plan to enroll?" gets the same value with less
friction.

### Confirmation gates

Two confirmation gates before any expensive work:

1. **Parameter table.** Present every value (distribution parameters,
   readout times, sample size, accrual, dropout, milestone triggers,
   stratification factors, helper-derived literals). User confirms.
2. **Save plan.** For every operating characteristic the user wants
   to know, show which value will be saved in which action function.
   Catches save↔OC mismatches that are expensive to fix
   post-simulation.

## Code quality

- **Named arguments everywhere.** Never positional.
- **Prefer TrialSimulator-provided functions** over base R or external
  packages when both can do the job. See `helpers.md` for the
  catalog. The package's design intent is that you reach for its
  functions reflexively.
- **Runnable dummies for unspecified decision rules.** When the user
  says "we'll decide based on data" without specifying the rule,
  write a small data-driven dummy and label it: `# DUMMY: replace
  with actual rule`. Guard against edge cases (`length() > 0` before
  `remove_arms`, etc.). A dummy that runs is better than a TODO that
  blocks validation.
- **Stub combination / group-sequential / graphical tests for now.**
  This skill does not yet cover those (`independentIncrement`,
  `dunnettTest`, `closedTest`, `GroupSequentialTest`,
  `GraphicalTesting`). When a real design needs one, write a small
  stub that returns a plausible structure (p-value, estimate,
  decision) so the trial wiring is exercised, and label it: `# STUB:
  replace with real combination test`. The author of TrialSimulator
  will add guidance for these later.

## Error-handling stance

When code errors:

1. Read the message — TrialSimulator's messages are usually specific.
2. Consult `?<function>` for plain functions (`endpoint`, `arm`,
   `trial`, `milestone`, `listener`, `controller`, `regimen`, the
   `fit*` wrappers, the `solve*` helpers, etc.). For R6 methods on
   `Trials` and `Controllers`, `?<method>` does not work — use
   `?Trials` / `?Controllers` and look up the method, or browse the
   pkgdown reference page.
3. Consult the pkgdown vignettes:
   https://zhangh12.github.io/TrialSimulator/articles/
4. Don't disable a check to make an error go away.

## Iteration and runtime

Three-stage testing:

- **Sanity** at `n = 3-5`: catches signature errors, formula
  mismatches, namespace conflicts. Note: with `n` this small,
  stochastic milestone triggers occasionally fail to fire in a
  replicate, producing errors that *look like* code bugs but are
  sample-size artifacts. If the same code at larger `n` succeeds,
  it's not a bug.
- **Calibration** at `n = 20-50` with `system.time()`: estimate
  per-replicate cost. Decide whether the production size is feasible
  on the available hardware.
- **Production** at the size the operating characteristics need.
  Confirm with the user — power studies typically want 1000+
  replicates; Type I error studies want more (10000+) for stable
  estimates.

The final delivered script contains a single production `controller$run()`
call. While iterating during development, simplest is to re-source the
script for each new run rather than reusing a controller across calls.

If runtime warrants `controller$run(n_workers = K)`, **be conservative
on a laptop**:
- Don't grab all cores. Leave at least one core free for the OS so
  the user's machine stays responsive.
- On Apple Silicon, performance and efficiency cores are not
  interchangeable; using only the performance cores typically beats
  using all cores.
- Start at `n_workers = 2-4`, measure, scale up if the machine stays
  responsive.
- Requires the `mirai` package; install it if not present.

## Workflow summary

1. Listen. Ask anchor questions if user is empty-handed.
2. Mode A: discover design through conversation, propose 2-3 options,
   user picks. Mode B: map user's spec to building blocks, flag
   unused/missing inputs.
3. Identify operating characteristics the user wants. Each one
   becomes a `trial$save()` call somewhere.
4. Walk the build order. Collect arguments in plain language.
5. Confirm parameter table. Confirm save plan.
6. Write the script. Use TS-provided functions where applicable.
7. Sanity run at small `n`. Fix until clean.
8. Calibration run for runtime estimate.
9. Production run.
10. Write the report (see `report.md`).

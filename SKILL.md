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

Data is locked automatically at every milestone; `trial$get_locked_data()`
only **retrieves** the snapshot when the action needs to inspect it.
Typical shape for a non-`doNothing` action:

```r
action_<name> <- function(trial, ...) {
  # 1. (Optional) retrieve locked data
  data <- trial$get_locked_data(milestone_name = "<name>")

  # 2. Analysis — skip if not needed

  # 3. Adaptations — guarded trial$*() calls

  # 4. Save — at least one trial$save() per non-doNothing action
  trial$save(value = <value>, name = "<metric>")
}
```

Signature is `function(trial, ...)`. Use distinct `name`s across
`trial$save()` calls. For state between milestones use
`trial$save_custom_data(..., overwrite = TRUE)` + `trial$get(name)`
(see helpers.md gotchas).

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

Detect from input shape, not content.

**Exploration mode** — user describes a setting in prose, may or may
not have a design in mind. Don't lock onto a design too fast. When
enough has accumulated, propose 2-3 candidate designs, contrast them
briefly, let the user pick. If the user has nothing to say, prompt
for orientation (therapeutic area, primary research question,
regulatory context, prior data) — a few anchors, not an
interrogation.

**Implementation mode** — user pastes a spec with parameters. Map
to building blocks, **explicitly call out unused inputs** ("you
mentioned X — I didn't use it; where does it fit?"), and ask for
missing pieces with one sentence of why each matters. Silently
dropping user-supplied information is a trust killer.

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

Read the message — TrialSimulator's are usually specific. Consult
`?<function>` for plain functions; for R6 methods on `Trials` /
`Controllers`, use `?Trials` / `?Controllers` (method-level `?` does
not work) or the pkgdown reference page. Vignettes live at
https://zhangh12.github.io/TrialSimulator/articles/. Don't disable a
check to make an error go away.

## Iteration and runtime

Validate iteratively: sanity at `n = 3-5` to catch real errors, a
short calibration at `n = 20-50` to estimate per-replicate cost, then
production at the size the operating characteristics require (1000+
for power; 10000+ for Type I error). Re-source the script between
runs rather than reusing a controller.

One TS-specific quirk: at very small `n`, stochastic milestone
triggers occasionally fail to fire in a replicate, producing errors
that look like code bugs but are sample-size artifacts. If the same
code succeeds at larger `n`, it's not a bug.

### Output organization

Create a dedicated folder for each simulation run — the script, the
saved output (`.rds`), the report (`.md` and rendered `.html`), and
any plots all go in that folder. A common convention is
`runs/<trial_name>/` or just `<trial_name>/` at the project root, with
files named consistently inside (`sim.R`, `report.md`, `output.rds`,
`milestone_times.png`, etc.). This keeps the project root clean,
makes side-by-side comparison of design variants trivial, and means
the user can zip a single folder to share results.

### Parallelism

**Default `n_workers = 1`** (single process). Most simulations in
this skill's typical territory — a few thousand replicates with
simple endpoints — finish in seconds single-process, and the script
is universally readable. Reach for `n_workers > 1` only when runtime
warrants it.

When `n_workers > 1` is used, pass per-call configuration through the
package's `...` mechanism: `trial(dropout = fn, my_arg = X)`,
`endpoint(generator = fn, my_arg = Y)`, `milestone(name, when,
action, my_arg = Z)`. The functions then receive their arguments via
their own signature. Don't reference script-level globals from
inside generators / dropout / enroller / action functions — `mirai`
workers don't share the script env and globals break. The `...`
pattern is also the idiomatic style in the package's vignettes.
Start at 2-4 workers on a laptop; requires the `mirai` package.

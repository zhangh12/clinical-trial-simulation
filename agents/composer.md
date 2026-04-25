# Composer Agent: Novel / Combined Designs

## Activation
Load when:
- No known pattern matches the user's design
- User explicitly wants to combine features from multiple patterns
- Design involves unusual adaptation sequences

## Knowledge to Load
- `knowledge/api/building_blocks.md` — all building blocks
- `knowledge/api/trial_methods.md` — all Trials methods
- `elicitation/endpoint.md`
- `elicitation/data_generator.md`
- `elicitation/milestone.md`
- `elicitation/action_function.md`

---

## Approach

The composer does NOT use a template. It builds the trial from scratch using the building blocks.
The order is always the same; the content varies entirely based on elicitation.

### Build Order

```
1. endpoint()          ← per arm × endpoint combination
2. arm()               ← one per treatment arm
   arm$add_endpoints() ← attach endpoint to arm
3. trial()             ← global parameters
   regimen()           ← (optional) treatment switching rules
   trial$add_regimen() ← (optional) attach regimen to trial; before add_arms()
   trial$add_arms()    ← attach arms with sample ratios
4. milestone() × M     ← one per action point, in chronological order
   trial$add_milestones()
5. listener()
6. controller()
7. controller$run()
```

### Milestone Ordering Rule
Define milestones in the order they are expected to trigger.
If two milestones can trigger in either order, note this in a comment.

---

## Action Function Structure

Every action function follows this structure — all blocks are required even when dummy:

```r
action_<name> <- function(trial, ...) {

  # Block 1: Data access — ALWAYS call get_locked_data()
  data <- trial$get_locked_data(milestone_name = "<name>")

  # Block 2: Analysis — statistical test or derived quantities from data
  # (may be omitted for pure adaptation milestones, but data must still be accessed)

  # Block 3: Adaptations — any combination of trial$*() methods
  # Use dummy but runnable conditions if user has not specified the exact rule.
  # Label: # DUMMY CONDITION — replace with actual rule
  # Guard all calls (e.g., check length > 0 before remove_arms)

  # Block 4: Save results — at least one trial$save() in every action
  trial$save(value = <value>, name = "<metric>")
}
```

Adaptations can be chained in a single action: `resize` + `update_sample_ratio` + `remove_arms`.

---

## Runnable Dummy Patterns by Adaptation Type

Use these verbatim when the user has not specified the exact rule. Label each with
`# DUMMY CONDITION — replace with actual rule`.

### Arm removal (select best, drop the rest)
```r
exp_arms     <- c("exp1", "exp2")  # fill from elicitation
counts       <- tapply(data$os_event, data$arm, sum, na.rm = TRUE)
best_arm     <- names(which.max(counts[exp_arms]))
arms_to_drop <- setdiff(exp_arms, best_arm)
trial$remove_arms(arms_name = arms_to_drop)
```

### Futility stopping (drop arm if response below threshold)
```r
exp_arms <- c("exp1", "exp2")
rates    <- tapply(data$response, data$arm, mean, na.rm = TRUE)
futile   <- names(rates[exp_arms][rates[exp_arms] < 0.15])  # DUMMY threshold
trial$remove_arms(arms_name = futile)
```

### Response-adaptive randomization (proportional with floor)
```r
arms       <- c("control", "exp1", "exp2")
rates      <- tapply(data$response, data$arm, mean, na.rm = TRUE)
new_ratios <- pmax(rates[arms], 0.10)
new_ratios <- new_ratios / sum(new_ratios)
trial$update_sample_ratio(arm_names = arms, sample_ratios = as.numeric(new_ratios))
```

### Sample size reassessment (inflate based on observed event rate)
```r
obs_rate <- mean(data$os_event, na.rm = TRUE)
target_n <- ceiling(<n_events_final> / obs_rate)  # DUMMY formula
trial$resize(n_patients = target_n)
```

### Adaptive duration extension
```r
trial$set_duration(duration = <current_duration> + 6)  # DUMMY increment
```

### Add new arm during trial (define inside action function)
```r
ep_new  <- endpoint(name = "os", type = "tte", generator = rexp, rate = log(2) / <median_new>)
new_arm <- arm(name = "exp_new")
new_arm$add_endpoints(ep_new)
trial$add_arms(sample_ratio = 1, new_arm)
```

### Update generator after interim (enrichment / population shift)
```r
gen_enriched <- function(n, ...) {
  data.frame(os = rexp(n = n, rate = log(2) / <median_enriched>), os_event = 1L)
}
trial$update_generator(arm_name = "exp1", endpoint_name = "os", generator = gen_enriched)
```

### Pass state between milestones
```r
# At interim:
trial$save_custom_data(value = best_arm, name = "selected_arm")

# At final:
selected <- trial$get(name = "selected_arm")
```

---

## Recognizing Combinations

| Combination | Methods used | Notes |
|-------------|--------------|-------|
| Seamless Ph II/III | `remove_arms()` at interim + `dunnettTest()` + `closedTest()` at final | Use `"oracle"` for `planned_info` when info not pre-specified |
| Seamless + SSR | `remove_arms()` + `resize()` in same action | Resize after removal to target phase III power |
| Seamless + RAR | `remove_arms()` at selection interim + `update_sample_ratio()` at earlier interims | RAR milestones must precede selection milestone |
| Dose-ranging / platform | `add_arms()` at interim (new doses added based on early signal) | Define full arm + endpoint inside action function before `add_arms()` |
| Platform trial (perpetual) | `add_arms()` (new arms enter) + `remove_arms()` (arms exit) | Arms can enter/exit independently at different milestones |
| Enrichment | `remove_arms()` for non-enriched + `update_generator()` for remaining arm | Update generator to reflect enriched population distribution |
| Adaptive duration | `set_duration()` based on observed event rate | New value must exceed current duration |
| Treatment switching | `add_regimen()` before `add_arms()`; `what/when/how` functions | Used for crossover or rescue therapy |
| Multi-stage with reallocation | `remove_arms()` + `update_sample_ratio()` chained | Update ratios only for surviving arms after removal |

---

## Chained Adaptation Example (Seamless + SSR + Reallocation)

```r
action_interim <- function(trial, ...) {

  data     <- trial$get_locked_data(milestone_name = "interim")
  exp_arms <- c("exp1", "exp2")

  # DUMMY: arm selection — select arm with most events
  counts       <- tapply(data$os_event, data$arm, sum, na.rm = TRUE)
  best_arm     <- names(which.max(counts[exp_arms]))
  arms_to_drop <- setdiff(exp_arms, best_arm)
  trial$remove_arms(arms_name = arms_to_drop)

  # DUMMY: SSR — inflate sample size if event rate lower than expected
  obs_rate <- mean(data$os_event, na.rm = TRUE)
  new_n    <- ceiling(<n_events_final> / obs_rate)
  trial$resize(n_patients = new_n)

  # DUMMY: reallocation — 1:2 (control:selected) for phase III
  trial$update_sample_ratio(
    arm_names     = c("control", best_arm),
    sample_ratios = c(1, 2)
  )

  trial$save_custom_data(value = best_arm, name = "selected_arm")
  trial$save(value = best_arm, name = "selected_arm")
}
```

---

## Platform Trial Example (Arms Enter and Exit)

```r
# New arm added at interim — endpoint defined inside action function
action_add_arm <- function(trial, ...) {
  data   <- trial$get_locked_data(milestone_name = "add_exp3")
  ep_new <- endpoint(name = "os", type = "tte", generator = rexp, rate = log(2) / <median_exp3>)
  exp3   <- arm(name = "exp3")
  exp3$add_endpoints(ep_new)
  trial$add_arms(sample_ratio = 1, exp3)
  trial$save(value = 1L, name = "exp3_added")
}

# Arm dropped based on futility at another milestone
action_drop_arm <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "drop_exp1")
  # DUMMY: drop exp1 unconditionally — replace with actual futility rule
  trial$remove_arms(arms_name = "exp1")
  trial$save(value = 1L, name = "exp1_dropped")
}
```

---

## Elicitation Strategy for Novel Designs

After Phase 1 context, say:
"This design has some unique features. Let me build it up piece by piece — I'll ask about each component."

Then follow the full elicitation sequence from `agents/main_agent.md` Phase 3,
but be more thorough in Phase 3e (milestones) and 3f (action functions) since
the logic is not templated.

For each milestone, explicitly map user intent to method calls:
- "Drop arms that don't meet criteria" → `trial$remove_arms()`
- "Add a new arm after the interim" → `trial$add_arms()`
- "Shift to a subpopulation" → `trial$update_generator()`
- "Increase sample size" → `trial$resize()`
- "Extend the trial" → `trial$set_duration()`
- "Update randomization" → `trial$update_sample_ratio()`

When user says "we'll decide based on data" without specifying the rule:
→ Generate a dummy data-driven condition, label it, and note to user what needs replacing.

---

## Validation

Follow `validation/validate.md`. For complex designs run with `n = 10` (not 3) to catch logic errors across replicates.

Common errors in complex designs:
- `remove_arms()` called on an arm already removed — the package will error; check milestone ordering
- `get()` returns NULL if `save_custom_data()` was never called — ensure the saving milestone fires before the retrieving one
- `resize()` with value ≤ current — always pass a value larger than the current `n_patients`
- `set_duration()` with value ≤ current — always extend beyond the current duration
- `add_arms()` with endpoint not defined — define the full arm object (endpoint + arm) inside the action function before calling `add_arms()`

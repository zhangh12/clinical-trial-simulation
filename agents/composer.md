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

## Approach

The composer does NOT use a template. It builds the trial from scratch using the building blocks.
The order is always the same; the content varies entirely based on elicitation.

### Build Order

```
1. endpoint()          ← per arm × endpoint combination
2. arm()               ← one per treatment arm
   arm$add_endpoints() ← attach endpoint to arm
3. trial()             ← global parameters
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

### Action Function Composition
Each action function is built modularly:
```r
action_<name> <- function(trial, ...) {
  # Block 1: Data access (if needed)
  # Block 2: Analysis (if needed)
  # Block 3: Adaptations (if needed) — any combination of trial$*() methods
  # Block 4: Save results
}
```

Any `trial$*()` method can appear in any action function.
Adaptations can be chained: resize + update_sample_ratio + remove_arms in one action.

### Recognizing Combinations
Common combinations the composer handles:

| Combination | Methods used |
|-------------|--------------|
| Seamless + RAR | remove_arms() at interim 1 + update_sample_ratio() at multiple interims |
| Platform trial | add_arms() (new arms enter) + remove_arms() (arms exit) |
| Enrichment | update_generator() to shift distribution + remove_arms() for non-responders |
| Adaptive duration | set_duration() based on observed event rate |
| Treatment switching | add_regimen() with what/when/how functions |

## Elicitation Strategy for Novel Designs

After Phase 1 context, say:
"This design has some unique features. Let me build it up piece by piece — I'll ask about each component."

Then follow the full elicitation sequence from `agents/main_agent.md` Phase 3,
but be more thorough in Phase 3e (milestones) and 3f (action functions) since
the logic is not templated.

For each milestone, explicitly map user intent to method calls:
- "You want to drop arms that don't meet criteria" → `trial$remove_arms()`
- "You want to add a new arm after the interim" → `trial$add_arms()`
- "You want to update the data model for remaining arms" → `trial$update_generator()`

## Validation
Follow `validation/validate.md`. For complex designs, run with `n_trials = 10` to
also catch logic errors (e.g., removing an arm that was already removed).

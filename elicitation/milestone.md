# Milestone Elicitation Guide

## Goal
Collect information to write each `milestone(name, when, action)` and its action function body.

---

## Step 1: Identify All Milestones

"At what point(s) during the trial should something happen — an analysis, an adaptation, or just a checkpoint?"

Probe questions:
- "Is there an interim analysis for early stopping or arm selection?"
- "Do you plan to adapt the randomization ratio during the trial?"
- "Is there a sample size reassessment?"
- "What marks the end of the trial? (final analysis)"

→ Each distinct timepoint = one milestone.
→ Collect: name, trigger type, trigger value, intended actions.

---

## Step 2: Triggering Condition (`when`)

For each milestone: "What triggers this milestone?"

| User answer | Code |
|-------------|------|
| "After X months" | `calendarTime(time = X)` |
| "After N patients enrolled" | `enrollment(n = N)` |
| "After N events of [endpoint]" | `eventNumber(endpoint = "<ep>", n = N)` |
| "After N non-missing observations" | `eventNumber(endpoint = "<ep>", n = N)` |
| "Whichever comes first: X months OR N events" | `calendarTime(time = X) \| eventNumber(endpoint = "<ep>", n = N)` |

→ `when` arg of `milestone()`

---

## Step 3: Action Function (`action`)

For each milestone with a non-trivial action, work through these sub-questions.

### 3a: Data access
"Do you need trial data at this milestone?"
→ Yes → `data <- trial$get_locked_data("<milestone_name>")`
→ Ask: "Which endpoints/arms do you need?" (data frame contains all arms/endpoints by default)

### 3b: Statistical analysis
"Do you want to run a statistical test at this milestone?"
- Log-rank / Cox → `fitLogrank()` or `fitCoxph()` on locked data, or `trial$dunnettTest()`
- Linear / logistic → `fitLinear()` / `fitLogistic()`
- Custom → ask user to describe or provide code

### 3c: Adaptations (ask only if relevant to design)
"Based on the analysis, do you want to modify the trial?"

| Adaptation | Function |
|------------|----------|
| Drop underperforming arm(s) | `trial$remove_arms(c("arm1", "arm2"))` |
| Update randomization ratios | `trial$update_sample_ratio(arm_names, ratios)` |
| Increase sample size | `trial$resize(new_n)` |
| Extend trial duration | `trial$set_duration(new_duration)` |
| Add new arm | `trial$add_arms(sample_ratio, arm_obj)` |
| Change data generator | `trial$update_generator(arm, ep, new_gen)` |

For each: "Under what condition? (e.g., if p-value < threshold, if response rate < X%)"

### 3d: What to save for operating characteristics
"What results do you need to summarize across simulations?"

Probe: "What are your key operating characteristics? Power? Type I error? Expected sample size? Duration?"

| Metric | Save call |
|--------|-----------|
| Reject H0 (yes/no) | `trial$save(value = as.integer(p < alpha), name = "reject")` |
| p-value | `trial$save(value = p_value, name = "pvalue")` |
| Actual sample size | `trial$save(value = trial$get_locked_data(milestone_name = ...) \|> nrow(), name = "n")` |
| Trial duration | `trial$save(value = milestone_time, name = "duration")` |
| Custom metric | `trial$save(value = value, name = "metric_name")` |

### 3e: User-provided code
"Do you have any custom code to run at this milestone?"
→ If yes: ask for the code; wrap it correctly and note where it plugs in
→ If not ready: insert `# TODO: [description]` placeholder
→ Ensure at least one `trial$save()` call exists so validation can confirm execution

---

## Output Template

```r
action_<milestone_name> <- function(trial, ...) {
  
  # --- Data access ---
  data <- trial$get_locked_data(milestone_name = "<milestone_name>")
  
  # --- Analysis ---
  # <statistical test or custom analysis>
  
  # --- Adaptations ---
  # if (<condition>) {
  #   trial$<adaptation_method>(...)
  # }
  
  # --- Save results ---
  trial$save(value = <value>, name = "<metric>")
}

m_<name> <- milestone(
  name   = "<name>",
  when   = <triggering_condition>,
  action = action_<milestone_name>
)
```

---

## Notes for Agent
- `doNothing` is valid for pure checkpoints (no analysis, just record timing)
- The action function signature must be `function(trial, ...)` — `trial` is the Trials R6 object
- Multiple `trial$save()` calls are fine; use distinct `name` values
- If user has no custom code and no adaptation, ask: "Do you want to stop early for efficacy or futility?" — very common
- Final analysis milestone almost always needs `trial$dunnettTest()` + `trial$closedTest()` + `trial$save()`

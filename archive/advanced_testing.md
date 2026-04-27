# Advanced Testing Classes: GroupSequentialTest & GraphicalTesting

These are R6 classes for testing strategies that go beyond a single Dunnett
closed test. They are **not** members of `Trials` — they are constructed
directly in action functions (or after the simulation) and consume p-values
that the agent has computed via `trial$independentIncrement()`,
`trial$dunnettTest()`, or wrapper-function fits.

---

## GroupSequentialTest

One-sided group sequential test for a **single hypothesis** with selectable
alpha-spending. Boundaries computed via `rpact`. Supports under-/over-running
adjustment by passing the observed final information.

### Constructor

```r
gst <- GroupSequentialTest$new(
  alpha            = 0.025,
  alpha_spending   = c("asP", "asOF", "asUser"),
  planned_max_info = <integer>,    # max events (TTE) or patients (non-TTE) at final
  name             = "H0",
  silent           = TRUE)
```

### Key methods

- `gst$test(observed_info, is_final, p_values = NULL, alpha_spent = NULL)`
  - Compute boundaries (and reject/accept decisions if `p_values` supplied) for one or more stages at once. `observed_info` is the cumulative count at each stage; `is_final = c(FALSE, ..., TRUE)` flags the final stage.
  - For `alpha_spending = "asUser"`, supply cumulative `alpha_spent` per stage.
  - Can be called incrementally (one stage at a time) or once with all stages.
- `gst$reset()` — required between simulation replicates if reusing the same `gst` object across replicates (or just construct a fresh one).
- `gst$set_max_info(obs_max_info)` — update planned max info at the final stage to handle under-/over-running.

### Typical use inside an action

```r
action_final <- function(trial, ...) {
  ii <- trial$independentIncrement(
          Surv(os, os_event) ~ arm,
          placebo      = "pbo",
          milestones   = c("interim", "final"),
          alternative  = "less",
          planned_info = c(interim = 150, final = 300))   # pre-fixed cumulative

  gst <- GroupSequentialTest$new(
           alpha = 0.025, alpha_spending = "asOF",
           planned_max_info = 300)
  res <- gst$test(observed_info = ii$info,
                  is_final      = c(FALSE, TRUE),
                  p_values      = ii$p_inverse_normal)

  trial$save(value = as.integer(any(res$decision == "reject")), name = "reject_h0")
}
```

### When to use

- Single endpoint, single experimental arm vs placebo, multiple looks, **no closed-test multiplicity**.
- For multi-arm Dunnett: use `closedTest` (which embeds GST machinery internally).
- For multi-endpoint with fixed structure: use `GraphicalTesting` (see below).

---

## GraphicalTesting

Maurer–Bretz graphical hypothesis test under group sequential design. Models
multiple hypotheses (endpoints × subgroups × arms) as a directed graph;
when one hypothesis is rejected, its alpha is propagated to neighbors via a
transition matrix. Each hypothesis has its own alpha-spending function and
planned max info.

### Constructor

```r
gt <- GraphicalTesting$new(
  alpha            = c(0.01, 0.01, 0.005, 0, 0, 0),    # initial alpha per hypothesis
  transition       = <K x K matrix>,                   # row sums = 1 (or 0 for sinks); diag = 0
  alpha_spending   = c("asOF", "asOF", "asUser", ...), # one per hypothesis
  planned_max_info = c(295, 800, 310, 750, 500, 1100), # one per hypothesis
  hypotheses       = c("H1: OS sub", "H2: OS all", ...),
  silent           = FALSE)
```

### Key method: `gt$test(stats)`

`stats` is a data.frame with columns:

| Column | Meaning |
|---|---|
| `order` | Stage label — same `order` value = tested simultaneously (e.g., one interim look). Optional if all rows are at the same stage. |
| `hypotheses` | Hypothesis name (must match constructor) |
| `p` | Nominal p-value at this stage |
| `info` | Observed events/samples at this stage |
| `max_info` | Planned max info (usually equal to constructor's `planned_max_info` until the final stage; can be updated to observed final at last stage) |
| `alpha_spent` | Cumulative alpha allocation (only for `asUser` hypotheses; `NA_real_` otherwise) |

Call once with all stages at once, or incrementally as p-values arrive across milestones.

### Other useful methods

- `gt$get_current_decision()` — named vector of `"reject"` / `"accept"` for every hypothesis
- `gt$get_current_testing_results()` — full per-step trajectory data.frame
- `gt$reset()` — required between replicates
- `gt$reject_a_hypothesis(name)` — manually drop a hypothesis (dry-run / behavior study)

### Use inside an action — accumulate stage-wise stats with `trial$bind()`

```r
# At each milestone, compute per-hypothesis p-values and bind them
action_interim <- function(trial, ...) {
  d <- trial$get_locked_data("interim")
  fit_pfs <- fitLogrank(Surv(pfs, pfs_event) ~ arm, placebo = "pbo",
                        data = d, alternative = "less")
  trial$bind(value = data.frame(
    order      = 1L,
    hypotheses = "H_PFS",
    p          = fit_pfs$p[fit_pfs$arm == "trt"],
    info       = fit_pfs$info[fit_pfs$arm == "trt"],
    max_info   = 300L,
    alpha_spent = NA_real_
  ), name = "stats")
}

action_final <- function(trial, ...) {
  d <- trial$get_locked_data("final")
  fit_pfs <- fitLogrank(Surv(pfs, pfs_event) ~ arm, placebo = "pbo",
                        data = d, alternative = "less")
  trial$bind(value = data.frame(
    order      = 2L,
    hypotheses = "H_PFS",
    p          = fit_pfs$p[fit_pfs$arm == "trt"],
    info       = fit_pfs$info[fit_pfs$arm == "trt"],
    max_info   = 300L,
    alpha_spent = NA_real_
  ), name = "stats")

  stats <- trial$get("stats")
  gt <- GraphicalTesting$new(
          alpha = 0.025, transition = matrix(0, 1, 1),
          alpha_spending = "asOF", planned_max_info = 300,
          hypotheses = "H_PFS", silent = TRUE)
  gt$test(stats)
  trial$save(value = as.integer(gt$get_current_decision()["H_PFS"] == "reject"),
             name = "reject_h0")
}
```

### When to use

- Multiple hypotheses (endpoints × subpopulations) with a **pre-specified
  alpha-recycling graph** — common in confirmatory oncology trials.
- Cleaner than chained Dunnett+closed-test calls when there are >2
  endpoints or when alpha needs to flow between endpoints/subpopulations
  in a non-tree pattern.
- Pair with `trial$bind()` to accumulate stage-wise stats across milestones,
  test in one call at the final action.

For a single multi-arm endpoint with multiple looks, `dunnettTest +
closedTest` is simpler and well-tested.

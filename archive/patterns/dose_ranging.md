# Pattern: Dose-Ranging / Adaptive Arm Addition

## What it is
Start with a placebo arm and one or more active doses (often only the highest).
At an interim, observe accumulating data; if a "go" signal is met, **add one
or more new dose arms** mid-trial to better characterize the dose-response
curve. The final analysis fits a dose-response model (e.g., MCPMod /
multiple-contrast test) to all arms.

## Key Characteristics
- Initial arms: placebo + a small number of dose arms (often 2)
- Interim: a `go/no-go` rule based on a treatment-effect z-statistic
- On "go": new dose arms (with their own endpoints + generators) are constructed **inside the action function** and registered via `trial$add_arms(sample_ratio, ...)`
- Final analysis: dose-response modeling across all randomized arms — typically `DoseFinding::MCTtest()` plus model-averaged predictions
- Trial may simulate the "go" arm-addition unconditionally and recover the early-termination rate from saved decision indicators in post-processing

## TrialSimulator Call Sequence

```
1. endpoint() per (initial) arm × endpoint   (binary or continuous)
2. arm() × 2  (placebo + highest dose)
3. trial()
   trial$add_arms(sample_ratio = c(1, 1), pbo, top_dose)
4. milestone(name = "interim", when = eventNumber(<endpoint>, n = ...), action = action_at_interim)
5. milestone(name = "final",   when = eventNumber(<endpoint>, n = N_total), action = action_at_final)
6. listener() / controller() / run()
```

## Decision Points

| Decision | Question to ask |
|----------|-----------------|
| Endpoint type | "Binary response, continuous, or TTE? Readout time?" |
| Initial vs. added arms | "Which arms enroll from day 1, and which are added at interim?" |
| Per-arm response model | "Response rate / mean per arm, including the to-be-added doses (we use these to simulate the 'go' branch even if no-go is later inferred)" |
| Interim trigger | "How many readouts/events trigger the interim?" |
| Go/no-go rule | "What threshold? (e.g., z-statistic from `fitLogistic` > 1.64)" |
| Post-go ratio | "When new arms are added, what's the new randomization ratio? (e.g., 1:2:2:2:1)" |
| Final analysis | "Dose-response model? (MCPMod is common — needs `DoseFinding`)" |

## Action Function: Interim (decision + arm addition)

```r
action_at_interim <- function(trial, ...) {

  data <- trial$get_locked_data("interim")

  # Compare top dose vs placebo on z-statistic
  fit <- fitLogistic(response ~ arm, placebo = "dose = 0.0",
                     data = data, alternative = "greater",
                     scale = "risk difference")
  z <- fit$z[fit$arm == "dose = 4.0"]

  # Save go/no-go decision for later (we add arms either way in simulation;
  # actual trial would stop on no-go — recovered in post-processing)
  trial$save(value = z,                                   name = "z_value")
  trial$save(value = ifelse(z > 1.64, "go", "no-go"),     name = "interim_decision")

  # DUMMY CONDITION (or always-add for simulation): construct new dose arms
  ep1 <- endpoint(name = "response", type = "non-tte", readout = c(response = 1),
                  generator = rbinom, size = 1, prob = 0.112)
  trt1 <- arm(name = "dose = 0.5"); trt1$add_endpoints(ep1)

  ep2 <- endpoint(name = "response", type = "non-tte", readout = c(response = 1),
                  generator = rbinom, size = 1, prob = 0.208)
  trt2 <- arm(name = "dose = 1.5"); trt2$add_endpoints(ep2)

  ep3 <- endpoint(name = "response", type = "non-tte", readout = c(response = 1),
                  generator = rbinom, size = 1, prob = 0.241)
  trt3 <- arm(name = "dose = 2.5"); trt3$add_endpoints(ep3)

  trial$add_arms(sample_ratio = c(2, 2, 2), trt1, trt2, trt3)
}
```

## Action Function: Final (dose-response analysis)

```r
action_at_final <- function(trial, ...) {

  data <- trial$get_locked_data("final")

  # Project-specific helper — define separately above
  decision <- go_nogo(data)   # returns "go" / "no-go" via DoseFinding::MCTtest etc.

  trial$save(value = decision, name = "decision")
}

# Helper (defined OUTSIDE the action function):
go_nogo <- function(data) {
  doses <- c(0, 0.5, 1.5, 2.5, 4)
  candidates <- DoseFinding::Mods(
    emax    = c(.25, 1),
    sigEmax = rbind(c(1, 3), c(2.5, 4)),
    betaMod = c(1.1, 1.1),
    placEff = log(.1/(1 - .1)),
    maxEff  = log(.25/(1 - .25)) - log(.1/(1 - .1)),
    doses   = doses)

  fit  <- glm(response ~ factor(arm) + 0, data = data, family = binomial)
  test <- DoseFinding::MCTtest(dose = doses, mu_hat = coef(fit),
                               S = vcov(fit), models = candidates,
                               type = "general")
  model <- DoseFinding::maFitMod(dose = doses, mu_hat = coef(fit),
                                 S = vcov(fit),
                                 models = c("emax", "sigEmax", "betaMod"))
  prd      <- predict(model, summaryFct = median, doseSeq = doses)
  prd_rate <- 1 / (1 + exp(-prd))

  ifelse(min(attr(test$tStat, "pVal")) < 0.05 &
           max(prd_rate - prd_rate[1]) > 0.10, "go", "no-go")
}
```

## Operating Characteristics — Post-Simulation

```r
out <- ctr$get_output()

# Combined "go" probability: must not stop at interim AND go at final
mean(out$interim_decision == "go" & out$decision == "go")

# Early termination probability
mean(out$interim_decision == "no-go")
```

## Key Elicitation Questions

1. "What endpoint drives the dose-response? (binary response, continuous biomarker?)"
2. "What dose levels are you considering? Which start enrolling, which get added at interim?"
3. "What is the assumed response per dose level? (used to populate every arm's generator)"
4. "What's the interim trigger? (events / patients / readouts)"
5. "What's the go/no-go rule at interim? (z-stat threshold from which test?)"
6. "After 'go', what is the new randomization ratio across all arms?"
7. "Final-analysis test? (MCPMod via `DoseFinding`? Multiple contrast test?)"
8. "What to report? (early termination rate, overall go rate, dose-response curve?)"

## Template File
See `templates/dose_ranging.R`

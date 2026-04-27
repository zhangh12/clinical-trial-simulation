library(TrialSimulator)
library(DoseFinding)   # for MCTtest, maFitMod, Mods

# =============================================================================
# DOSE-RANGING / ADAPTIVE ARM ADDITION TEMPLATE
# Start with placebo + highest dose. At interim, if z > threshold, add three
# more dose arms. Final analysis fits a dose-response model.
# Placeholders <...> must be filled from elicitation before validation.
# =============================================================================

# --- Initial Endpoints (placebo + top dose) ----------------------------------

ep_pbo <- endpoint(name = "response", type = "non-tte",
                   readout = c(response = <readout_weeks>),
                   generator = rbinom, size = 1, prob = <rate_pbo>)

ep_top <- endpoint(name = "response", type = "non-tte",
                   readout = c(response = <readout_weeks>),
                   generator = rbinom, size = 1, prob = <rate_top_dose>)

pbo <- arm(name = "dose = 0.0"); pbo$add_endpoints(ep_pbo)
top <- arm(name = "dose = 4.0"); top$add_endpoints(ep_top)

# --- Helper: go/no-go decision (define OUTSIDE action functions) -------------

go_nogo <- function(data) {
  doses <- c(0, 0.5, 1.5, 2.5, 4)
  candidates <- DoseFinding::Mods(
    emax    = c(0.25, 1),
    sigEmax = rbind(c(1, 3), c(2.5, 4)),
    betaMod = c(1.1, 1.1),
    placEff = log(<rate_pbo>     / (1 - <rate_pbo>)),
    maxEff  = log(<rate_top_dose>/ (1 - <rate_top_dose>)) -
              log(<rate_pbo>     / (1 - <rate_pbo>)),
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

# --- Action: Interim (decision + arm addition) -------------------------------

action_at_interim <- function(trial, ...) {

  data <- trial$get_locked_data("interim")

  fit <- fitLogistic(response ~ arm, placebo = "dose = 0.0",
                     data = data, alternative = "greater",
                     scale = "risk difference")
  z <- fit$z[fit$arm == "dose = 4.0"]

  trial$save(value = z,                                  name = "z_value")
  trial$save(value = ifelse(z > <go_threshold>, "go", "no-go"),
             name = "interim_decision")

  # In simulation we ALWAYS add arms (early termination is recovered in
  # post-processing as a combination of interim_decision and final decision)
  ep1 <- endpoint(name = "response", type = "non-tte",
                  readout = c(response = <readout_weeks>),
                  generator = rbinom, size = 1, prob = <rate_d1>)
  trt1 <- arm(name = "dose = 0.5"); trt1$add_endpoints(ep1)

  ep2 <- endpoint(name = "response", type = "non-tte",
                  readout = c(response = <readout_weeks>),
                  generator = rbinom, size = 1, prob = <rate_d2>)
  trt2 <- arm(name = "dose = 1.5"); trt2$add_endpoints(ep2)

  ep3 <- endpoint(name = "response", type = "non-tte",
                  readout = c(response = <readout_weeks>),
                  generator = rbinom, size = 1, prob = <rate_d3>)
  trt3 <- arm(name = "dose = 2.5"); trt3$add_endpoints(ep3)

  trial$add_arms(sample_ratio = c(2, 2, 2), trt1, trt2, trt3)
}

# --- Action: Final (dose-response analysis) ---------------------------------

action_at_final <- function(trial, ...) {
  data <- trial$get_locked_data("final")
  trial$save(value = go_nogo(data), name = "decision")
}

# --- Milestones --------------------------------------------------------------

m_interim <- milestone(name = "interim",
                       when = eventNumber(endpoint = "response", n = <n_interim>),
                       action = action_at_interim)

m_final <- milestone(name = "final",
                     when = eventNumber(endpoint = "response", n = <n_final>),
                     action = action_at_final)

# --- Trial -------------------------------------------------------------------

accrual <- data.frame(
  end_time       = c(<initial_period>, Inf),
  piecewise_rate = c(<rate_initial>, <rate_post_addition>)
)

tr <- trial(name = "dose_ranging",
            n_patients = <total_n_patients>,
            duration   = <max_duration>,
            enroller   = StaggeredRecruiter,
            accrual_rate = accrual,
            silent     = TRUE)

tr$add_arms(sample_ratio = c(1, 1), pbo, top)

# --- Run Simulation ----------------------------------------------------------

l   <- listener(silent = TRUE)
l$add_milestones(m_interim, m_final)
ctr <- controller(trial = tr, listener = l)
ctr$run(n = <n_replicates>, plot_event = FALSE, silent = TRUE)

# --- Summarize Results -------------------------------------------------------

out <- ctr$get_output()

cat("Overall go probability:   ",
    mean(out$interim_decision == "go" & out$decision == "go"), "\n")
cat("Early termination prob.:  ",
    mean(out$interim_decision == "no-go"), "\n")
cat("Mean interim z:           ", mean(out$z_value), "\n")

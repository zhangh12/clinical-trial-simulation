library(TrialSimulator)
library(dplyr)

# =============================================================================
# DYNAMIC TREATMENT SWITCHING (CROSSOVER) TEMPLATE
# Placebo patients can switch to low or high dose at progression.
# Post-switch OS is extended via a causal-AFT-style multiplier.
# Placeholders <...> must be filled from elicitation before validation.
# =============================================================================

# --- Endpoints (correlated PFS+OS via Gumbel copula — Cox-compatible) -------

ep_pbo  <- endpoint(name = c("pfs", "os"), type = c("tte", "tte"),
                    generator = CorrelatedPfsAndOs2,
                    median_pfs = <median_pfs_pbo>, median_os = <median_os_pbo>,
                    kendall = <kendall_tau>,
                    pfs_name = "pfs", os_name = "os")

ep_low  <- endpoint(name = c("pfs", "os"), type = c("tte", "tte"),
                    generator = CorrelatedPfsAndOs2,
                    median_pfs = <median_pfs_low>, median_os = <median_os_low>,
                    kendall = <kendall_tau>,
                    pfs_name = "pfs", os_name = "os")

ep_high <- endpoint(name = c("pfs", "os"), type = c("tte", "tte"),
                    generator = CorrelatedPfsAndOs2,
                    median_pfs = <median_pfs_high>, median_os = <median_os_high>,
                    kendall = <kendall_tau>,
                    pfs_name = "pfs", os_name = "os")

pbo  <- arm(name = "placebo");   pbo$add_endpoints(ep_pbo)
low  <- arm(name = "low dose");  low$add_endpoints(ep_low)
high <- arm(name = "high dose"); high$add_endpoints(ep_high)

# --- Regimen: who switches, when, how (DEFINE BEFORE trial$add_regimen) -----

# what: which patients switch and where to
treatment_allocator <- function(patient_data) {
  switch_to <- sample(c("low dose", "high dose", "stay"),
                      nrow(patient_data),
                      replace = TRUE,
                      prob = c(<p_low>, <p_high>, <p_stay>))
  data.frame(
    patient_id = patient_data$patient_id,
    new_treatment = dplyr::case_when(
      patient_data$os == patient_data$pfs                       ~ NA_character_,  # died at progression
      patient_data$arm == "placebo" & switch_to == "low dose"   ~ "low dose",
      patient_data$arm == "placebo" & switch_to == "high dose"  ~ "high dose",
      TRUE                                                      ~ NA_character_
    )
  )
}

# when: switch at progression
time_selector <- function(patient_data) {
  data.frame(
    patient_id  = patient_data$patient_id,
    switch_time = patient_data$pfs
  )
}

# how: extend residual survival by a treatment-specific factor
data_modifier <- function(patient_data) {
  f <- ifelse(patient_data$new_treatment == "low dose", <factor_low>, <factor_high>)
  data.frame(
    patient_id = patient_data$patient_id,
    os = patient_data$switch_time + f * (patient_data$os - patient_data$switch_time)
  )
}

reg <- regimen(treatment_allocator, time_selector, data_modifier)

# --- Action: Final Analysis (ITT — analyze original arm assignment) ---------

action_final <- function(trial, ...) {
  data <- trial$get_locked_data("final")

  fit <- fitLogrank(Surv(os, os_event) ~ arm, placebo = "placebo",
                    data = data, alternative = "less")

  trial$save(value = as.integer(fit$p[fit$arm == "low dose"]  < 0.025), name = "reject_os_low")
  trial$save(value = as.integer(fit$p[fit$arm == "high dose"] < 0.025), name = "reject_os_high")

  # Crossover diagnostics
  long <- expandRegimen(data)
  trial$save(value = mean(table(long$patient_id) > 1),                  name = "crossover_rate")
}

# --- Milestone ---------------------------------------------------------------

m_final <- milestone(name = "final",
                     when = eventNumber(endpoint = "os", n = <n_os_events>),
                     action = action_final)

# --- Trial (ORDER MATTERS: add_regimen BEFORE add_arms) ---------------------

accrual <- data.frame(
  end_time       = c(<accrual_period>, Inf),
  piecewise_rate = c(<rate_phase1>, <rate_phase2>)
)

tr <- trial(name = "treatment_switching",
            n_patients = <total_n_patients>,
            duration   = <max_duration>,
            enroller   = StaggeredRecruiter,
            accrual_rate = accrual,
            silent = TRUE)

tr$add_regimen(reg)                                      # MUST be before add_arms
tr$add_arms(sample_ratio = c(1, 1, 1), pbo, low, high)

# --- Run Simulation ----------------------------------------------------------

l   <- listener(silent = TRUE)
l$add_milestones(m_final)
ctr <- controller(trial = tr, listener = l)
ctr$run(n = <n_replicates>, plot_event = FALSE, silent = TRUE)

# --- Summarize Results -------------------------------------------------------

out <- ctr$get_output(tidy = TRUE)
cat("Power OS low:    ", mean(out$reject_os_low,  na.rm = TRUE), "\n")
cat("Power OS high:   ", mean(out$reject_os_high, na.rm = TRUE), "\n")
cat("Crossover rate:  ", mean(out$crossover_rate, na.rm = TRUE), "\n")

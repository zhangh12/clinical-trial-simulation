library(TrialSimulator)

# =============================================================================
# RESPONSE-ADAPTIVE RANDOMIZATION (RAR) DESIGN TEMPLATE
# Placeholders marked with <...> must be filled via elicitation.
# Run validation after filling all placeholders.
# =============================================================================

# --- Data Generators ---------------------------------------------------------

# Binary response endpoint (typically drives RAR)
gen_control <- function(n, p = <response_rate_control>, ...) {
  data.frame(
    response = rbinom(n = n, size = 1, prob = p)
  )
}

gen_exp <- function(n, p = <response_rate_exp>, ...) {
  data.frame(
    response = rbinom(n = n, size = 1, prob = p)
  )
}

# --- Endpoints ---------------------------------------------------------------

ep_control <- endpoint(
  name      = "response",
  type      = "non-tte",
  readout   = c(response = <readout_weeks>),  # e.g., 8 for 8-week response
  generator = gen_control
)

ep_exp <- endpoint(
  name      = "response",
  type      = "non-tte",
  readout   = c(response = <readout_weeks>),
  generator = gen_exp
)

# --- Arms --------------------------------------------------------------------

ctrl <- arm(name = "control")
ctrl$add_endpoints(ep_control)

exp1 <- arm(name = "exp1")
exp1$add_endpoints(ep_exp)

exp2 <- arm(name = "exp2")  # remove if only 1 experimental arm
exp2$add_endpoints(
  endpoint(
    name      = "response",
    type      = "non-tte",
    readout   = c(response = <readout_weeks>),
    generator = gen_exp,
    p         = <response_rate_exp2>
  )
)

# --- Action: RAR Update ------------------------------------------------------

action_rar <- function(trial, milestone_name, floor = 0.10, ...) {
  data <- trial$get_locked_data(milestone_name = milestone_name)

  arms <- c("control", "exp1", "exp2")  # update with actual arm names

  # Compute observed response rates (only patients with non-missing readout)
  rates <- sapply(arms, function(a) {
    d <- data[data$arm == a & !is.na(data$response), , drop = FALSE]
    if (nrow(d) == 0) return(NA_real_)
    mean(d$response)
  })

  if (any(is.na(rates))) {
    # Not enough data yet — skip update
    return(invisible(NULL))
  }

  # Update rule: proportional with floor (customize per user)
  new_ratios <- pmax(rates, floor)
  new_ratios <- new_ratios / sum(new_ratios)

  trial$update_sample_ratio(arm_names = arms, sample_ratios = as.numeric(new_ratios))
  trial$save(value = t(round(new_ratios, digits = 3)), name = paste0("ratio_", milestone_name))
}

# --- Action: Final Analysis --------------------------------------------------

action_final <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "final")

  # Summarize allocation actually received
  alloc <- table(data$arm)
  for (a in names(alloc)) {
    trial$save(value = as.integer(alloc[a]), name = paste0("n_", a))
  }

  # Primary hypothesis test (customize: logistic / logrank / etc.)
  # Example: logistic regression for binary response
  fit <- fitLogistic(
    formula = response ~ arm,
    data    = data[data$arm %in% c("control", "exp1"), ]
  )
  # trial$save(value = fit$pvalue["exp1"], name = "pvalue_exp1")
  # trial$save(value = as.integer(fit$pvalue["exp1"] < 0.025), name = "reject_h0")

  # TODO: replace with appropriate test for user's primary endpoint
  trial$save(value = NA_real_, name = "reject_h0")  # placeholder — remove after filling above
}

# --- Milestones --------------------------------------------------------------

# RAR update milestones — one per update interval
m_rar1 <- milestone(
  name   = "rar_1",
  when   = enrollment(n = <n_update_1>),
  action = function(trial, ...) action_rar(trial, milestone_name = "rar_1", ...)
)

m_rar2 <- milestone(
  name   = "rar_2",
  when   = enrollment(n = <n_update_2>),
  action = function(trial, ...) action_rar(trial, milestone_name = "rar_2", ...)
)

# Add more RAR milestones as needed...

m_final <- milestone(
  name   = "final",
  when   = enrollment(n = <total_n_patients>),
  action = action_final
)

# --- Trial -------------------------------------------------------------------

tr <- trial(
  name       = "rar_design",
  n_patients = <total_n_patients>,
  duration   = <max_duration_months>,
  enroller   = StaggeredRecruiter,
  rate       = c(<enroll_rate>),
  duration   = c(<accrual_duration>)
)

tr$add_arms(
  sample_ratio = c(1, 1, 1),  # initial equal allocation
  ctrl, exp1, exp2
)

tr$add_milestones(m_rar1, m_rar2, m_final)

# --- Run Simulation ----------------------------------------------------------

l   <- listener()
ctr <- controller(trial = tr, listener = l)
ctr$run(n_trials = <n_replicates>)

# --- Summarize Results -------------------------------------------------------

out <- ctr$get_output()
cat("Power (reject H0):", mean(out$reject_h0, na.rm = TRUE), "\n")
cat("Mean n control:", mean(out$n_control, na.rm = TRUE), "\n")
cat("Mean n exp1:",    mean(out$n_exp1, na.rm = TRUE), "\n")

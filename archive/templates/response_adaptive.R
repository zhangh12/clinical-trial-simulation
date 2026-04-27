library(TrialSimulator)

# =============================================================================
# RESPONSE-ADAPTIVE RANDOMIZATION (RAR) DESIGN TEMPLATE
# Placeholders <...> must be filled from elicitation before validation.
# Action functions use dummy but runnable conditions — replace with actual rules.
# =============================================================================

# --- Endpoints ---------------------------------------------------------------

ep_ctrl <- endpoint(
  name      = "response",
  type      = "non-tte",
  readout   = c(response = <readout_weeks>),
  generator = rbinom,
  size      = 1,
  prob      = <response_rate_control>
)

ep_exp1 <- endpoint(
  name      = "response",
  type      = "non-tte",
  readout   = c(response = <readout_weeks>),
  generator = rbinom,
  size      = 1,
  prob      = <response_rate_exp1>
)

ep_exp2 <- endpoint(  # remove if only 1 experimental arm
  name      = "response",
  type      = "non-tte",
  readout   = c(response = <readout_weeks>),
  generator = rbinom,
  size      = 1,
  prob      = <response_rate_exp2>
)

# --- Arms --------------------------------------------------------------------

ctrl <- arm(name = "control"); ctrl$add_endpoints(ep_ctrl)
exp1 <- arm(name = "exp1");    exp1$add_endpoints(ep_exp1)
exp2 <- arm(name = "exp2");    exp2$add_endpoints(ep_exp2)

# --- Action: RAR Update ------------------------------------------------------

action_rar <- function(trial, milestone_name, floor_ratio = 0.10, ...) {
  data <- trial$get_locked_data(milestone_name = milestone_name)
  arms <- c("control", "exp1", "exp2")  # update if arm names differ

  # DUMMY CONDITION: update ratios proportional to observed response rates
  # Replace with actual RAR rule (e.g., Thompson sampling, doubly-adaptive biased coin)
  rates <- sapply(arms, function(a) {
    d <- data[data$arm == a & !is.na(data$response), , drop = FALSE]
    if (nrow(d) == 0) return(NA_real_)
    mean(d$response)
  })

  if (any(is.na(rates))) return(invisible(NULL))  # skip if insufficient data

  new_ratios <- pmax(rates, floor_ratio)
  new_ratios <- new_ratios / sum(new_ratios)

  trial$update_sample_ratio(arm_names = arms, sample_ratios = as.numeric(new_ratios))
  trial$save(value = t(round(new_ratios, 3)), name = paste0("ratio_", milestone_name))
}

# --- Action: Final Analysis --------------------------------------------------

action_final <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "final")

  # Save observed allocation
  alloc <- as.integer(table(data$arm))
  arms  <- names(table(data$arm))
  for (i in seq_along(arms)) {
    trial$save(value = alloc[i], name = paste0("n_", arms[i]))
  }

  # DUMMY: logistic test on exp1 vs control — replace with actual primary analysis
  # For TTE primary endpoint use fitLogrank() or fitCoxph() instead
  d_test <- data[data$arm %in% c("control", "exp1") & !is.na(data$response), ]
  if (nrow(d_test) > 0 && length(unique(d_test$arm)) == 2) {
    fit <- fitLogistic(
      formula     = response ~ arm,
      placebo     = "control",
      data        = d_test,
      alternative = "greater",
      scale       = "risk difference"
    )
    trial$save(value = as.integer(fit$p[fit$arm == "exp1"] < 0.025), name = "reject_h0")
  } else {
    trial$save(value = NA_integer_, name = "reject_h0")
  }
}

# --- Milestones --------------------------------------------------------------

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

m_final <- milestone(
  name   = "final",
  when   = enrollment(n = <total_n_patients>),
  action = action_final
)

# --- Trial -------------------------------------------------------------------

accrual <- data.frame(
  end_time       = c(<max_duration_weeks>),
  piecewise_rate = c(<enroll_rate_per_week>)
)

tr <- trial(
  name         = "rar_design",
  n_patients   = <total_n_patients>,
  duration     = <max_duration_weeks>,
  enroller     = StaggeredRecruiter,
  accrual_rate = accrual
)

tr$add_arms(sample_ratio = c(1, 1, 1), ctrl, exp1, exp2)

# --- Run Simulation ----------------------------------------------------------

l   <- listener()
l$add_milestones(m_rar1, m_rar2, m_final)
ctr <- controller(trial = tr, listener = l)
ctr$run(n = <n_replicates>)

# --- Summarize Results -------------------------------------------------------

out <- ctr$get_output()
cat("Power (reject H0):", mean(out$reject_h0, na.rm = TRUE), "\n")
cat("Mean n control:", mean(out$n_control, na.rm = TRUE), "\n")
cat("Mean n exp1:",    mean(out$n_exp1,    na.rm = TRUE), "\n")
cat("Mean n exp2:",    mean(out$n_exp2,    na.rm = TRUE), "\n")

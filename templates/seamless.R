library(TrialSimulator)

# =============================================================================
# SEAMLESS PHASE II/III ADAPTIVE DESIGN TEMPLATE
# Placeholders <...> must be filled from elicitation before validation.
# Action functions use dummy but runnable conditions — replace with actual rules.
# =============================================================================

# --- Endpoints ---------------------------------------------------------------

ep_ctrl <- endpoint(
  name      = "os",
  type      = "tte",
  generator = rexp,
  rate      = log(2) / <median_ctrl_months>
)

ep_exp1 <- endpoint(
  name      = "os",
  type      = "tte",
  generator = rexp,
  rate      = log(2) / <median_exp1_months>
)

ep_exp2 <- endpoint(  # remove if only 1 experimental arm
  name      = "os",
  type      = "tte",
  generator = rexp,
  rate      = log(2) / <median_exp2_months>
)

# --- Arms --------------------------------------------------------------------

ctrl <- arm(name = "control"); ctrl$add_endpoints(ep_ctrl)
exp1 <- arm(name = "exp1");    exp1$add_endpoints(ep_exp1)
exp2 <- arm(name = "exp2");    exp2$add_endpoints(ep_exp2)

# --- Action: Interim (Arm Selection) ----------------------------------------

action_interim <- function(trial, ...) {
  data     <- trial$get_locked_data(milestone_name = "interim")
  exp_arms <- c("exp1", "exp2")  # update if arm names differ

  # DUMMY CONDITION: select arm with most OS events — replace with actual rule
  counts       <- tapply(data$os_event, data$arm, sum, na.rm = TRUE)
  best_arm     <- names(which.max(counts[exp_arms]))
  arms_to_drop <- setdiff(exp_arms, best_arm)

  if (length(arms_to_drop) > 0) {
    trial$remove_arms(arms_name = arms_to_drop)
  }

  trial$save_custom_data(value = best_arm, name = "selected_arm")
  trial$save(value = best_arm, name = "selected_arm")
}

# --- Action: Final Analysis --------------------------------------------------

action_final <- function(trial, ...) {
  data     <- trial$get_locked_data(milestone_name = "final")
  selected <- trial$get(name = "selected_arm")

  dt <- trial$dunnettTest(
    formula      = os ~ arm,
    placebo      = "control",
    treatments   = selected,
    milestones   = c("interim", "final"),
    alternative  = "greater",
    planned_info = "oracle"
  )

  result <- trial$closedTest(
    dunnett_test   = dt,
    treatments     = selected,
    milestones     = c("interim", "final"),
    alpha          = 0.025,
    alpha_spending = "asOF"  # or "asP" for Pocock
  )

  trial$save(value = as.integer(any(result$decision == "reject")), name = "reject_h0")
}

# --- Milestones --------------------------------------------------------------

m_interim <- milestone(
  name   = "interim",
  when   = eventNumber(endpoint = "os", n = <n_events_interim>),
  action = action_interim
)

m_final <- milestone(
  name   = "final",
  when   = eventNumber(endpoint = "os", n = <n_events_final>),
  action = action_final
)

# --- Trial -------------------------------------------------------------------

accrual <- data.frame(
  end_time       = c(<accrual_period_months>, <max_duration_months>),
  piecewise_rate = c(<rate_phase1>, <rate_phase2>)
)

tr <- trial(
  name         = "seamless_ph2_ph3",
  n_patients   = <total_n_patients>,
  duration     = <max_duration_months>,
  enroller     = StaggeredRecruiter,
  accrual_rate = accrual
)

tr$add_arms(sample_ratio = c(1, 1, 1), ctrl, exp1, exp2)

# --- Run Simulation ----------------------------------------------------------

l   <- listener()
l$add_milestones(m_interim, m_final)
ctr <- controller(trial = tr, listener = l)
ctr$run(n = <n_replicates>)

# --- Summarize Results -------------------------------------------------------

out <- ctr$get_output()
cat("Power (reject H0):", mean(out$reject_h0, na.rm = TRUE), "\n")
cat("Correct arm selection (exp1):", mean(out$selected_arm == "exp1", na.rm = TRUE), "\n")

library(TrialSimulator)

# =============================================================================
# SEAMLESS PHASE II/III ADAPTIVE DESIGN TEMPLATE
# Placeholders marked with <...> must be filled via elicitation.
# Run validation after filling all placeholders.
# =============================================================================

# --- Data Generators ---------------------------------------------------------

gen_control <- function(n, ...) {
  data.frame(
    os       = rexp(n = n, rate = log(2) / <median_control_months>),
    os_event = 1L
  )
}

gen_exp <- function(n, hr = <hazard_ratio>, ...) {
  data.frame(
    os       = rexp(n = n, rate = log(2) / <median_control_months> * hr),
    os_event = 1L
  )
}

# --- Endpoints ---------------------------------------------------------------

ep_control <- endpoint(name = "os", type = "tte", generator = gen_control)
ep_exp     <- endpoint(name = "os", type = "tte", generator = gen_exp)

# --- Arms --------------------------------------------------------------------

ctrl <- arm(name = "control")
ctrl$add_endpoints(ep_control)

exp1 <- arm(name = "exp1")
exp1$add_endpoints(endpoint(name = "os", type = "tte", generator = gen_exp, hr = <hr_exp1>))

exp2 <- arm(name = "exp2")  # remove if only 1 experimental arm
exp2$add_endpoints(endpoint(name = "os", type = "tte", generator = gen_exp, hr = <hr_exp2>))

# --- Action: Interim (Arm Selection) -----------------------------------------

action_interim <- function(trial, ...) {
  data <- trial$get_locked_data(milestone_name = "interim")

  # Arm selection: customize rule below
  exp_arms <- c("exp1", "exp2")  # update with actual arm names

  # Example rule: select arm with most events (proxy for faster OS improvement)
  # Replace with user's selection criterion
  event_counts <- tapply(data$os_event, data$arm, sum, na.rm = TRUE)
  best_arm <- names(which.max(event_counts[exp_arms]))
  arms_to_drop <- setdiff(exp_arms, best_arm)

  trial$remove_arms(arms_name = arms_to_drop)
  trial$save_custom_data(value = best_arm, name = "selected_arm")
  trial$save(value = best_arm, name = "selected_arm")

  # Optional sample size update for phase III
  # trial$resize(n_patients = <phase3_n_patients>)
}

# --- Action: Final Analysis --------------------------------------------------

action_final <- function(trial, ...) {
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

tr <- trial(
  name       = "seamless_ph2_ph3",
  n_patients = <total_n_patients>,
  duration   = <max_duration_months>,
  enroller   = StaggeredRecruiter,
  rate       = c(<rate_phase1>, <rate_phase2>),
  duration   = c(<accrual_period1>, <accrual_period2>)
)

tr$add_arms(
  sample_ratio = c(1, 1, 1),  # equal allocation; adjust if needed
  ctrl, exp1, exp2
)

tr$add_milestones(m_interim, m_final)

# --- Run Simulation ----------------------------------------------------------

l   <- listener()
ctr <- controller(trial = tr, listener = l)
ctr$run(n_trials = <n_replicates>)

# --- Summarize Results -------------------------------------------------------

out <- ctr$get_output()
cat("Power (reject H0):", mean(out$reject_h0, na.rm = TRUE), "\n")
cat("Correct arm selection (exp1):", mean(out$selected_arm == "exp1", na.rm = TRUE), "\n")

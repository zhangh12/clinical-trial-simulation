library(TrialSimulator)

# =============================================================================
# FIXED DESIGN TEMPLATE
# Two correlated TTE endpoints (PFS, OS) analyzed at one final milestone.
# Bonferroni split across endpoints x arms.
# Placeholders <...> must be filled from elicitation before validation.
# =============================================================================

# --- Endpoints ---------------------------------------------------------------
# For correlated PFS+OS with Cox/log-rank planned, prefer CorrelatedPfsAndOs2
# (Gumbel copula, PH-compatible). For non-Cox / mechanistic, use the literals
# resolved offline via solveThreeStateModel() and CorrelatedPfsAndOs3.

ep_ctrl <- endpoint(
  name       = c("pfs", "os"),
  type       = c("tte", "tte"),
  generator  = CorrelatedPfsAndOs2,
  median_pfs = <median_pfs_ctrl>,
  median_os  = <median_os_ctrl>,
  kendall    = <kendall_tau>,
  pfs_name   = "pfs",
  os_name    = "os"
)

ep_low <- endpoint(
  name       = c("pfs", "os"),
  type       = c("tte", "tte"),
  generator  = CorrelatedPfsAndOs2,
  median_pfs = <median_pfs_low>,
  median_os  = <median_os_low>,
  kendall    = <kendall_tau>,
  pfs_name   = "pfs",
  os_name    = "os"
)

ep_high <- endpoint(
  name       = c("pfs", "os"),
  type       = c("tte", "tte"),
  generator  = CorrelatedPfsAndOs2,
  median_pfs = <median_pfs_high>,
  median_os  = <median_os_high>,
  kendall    = <kendall_tau>,
  pfs_name   = "pfs",
  os_name    = "os"
)

# --- Arms --------------------------------------------------------------------

ctrl <- arm(name = "control"); ctrl$add_endpoints(ep_ctrl)
low  <- arm(name = "low");     low$add_endpoints(ep_low)
high <- arm(name = "high");    high$add_endpoints(ep_high)

# --- Action: Final Analysis (Bonferroni) -------------------------------------

action_final <- function(trial, ...) {

  data <- trial$get_locked_data("final")

  pfs <- fitCoxph(Surv(pfs, pfs_event) ~ arm, placebo = "control",
                  data = data, alternative = "less", scale = "hazard ratio")
  os  <- fitLogrank(Surv(os, os_event) ~ arm, placebo = "control",
                    data = data, alternative = "less")

  alpha_each <- 0.05 / 4   # PFS_low, PFS_high, OS_low, OS_high
  pfs$decision <- ifelse(pfs$p < alpha_each, "reject", "accept")
  os$decision  <- ifelse(os$p  < alpha_each, "reject", "accept")

  trial$save(value = pfs[pfs$arm == "low",  c("estimate", "decision", "info")], name = "pfs_low")
  trial$save(value = pfs[pfs$arm == "high", c("estimate", "decision", "info")], name = "pfs_high")
  trial$save(value = os[os$arm   == "low",  c("decision", "info")],            name = "os_low")
  trial$save(value = os[os$arm   == "high", c("decision", "info")],            name = "os_high")
}

# --- Milestone (composite event-count trigger) -------------------------------

m_final <- milestone(
  name   = "final",
  when   = eventNumber(endpoint = "pfs", n = <n_pfs_events>) &
           eventNumber(endpoint = "os",  n = <n_os_events>),
  action = action_final
)

# --- Trial -------------------------------------------------------------------

accrual <- data.frame(
  end_time       = c(<accrual_period>, Inf),
  piecewise_rate = c(<rate_phase1>, <rate_phase2>)
)

# Optional dropout via weibullDropout if user gives 2 landmarks; omit if none.
# dpars <- weibullDropout(time = c(12, 18), dropout_rate = c(0.08, 0.18))

tr <- trial(
  name         = "fixed_design",
  n_patients   = <total_n_patients>,
  duration     = <max_duration>,
  enroller     = StaggeredRecruiter,
  accrual_rate = accrual,
  # dropout    = rweibull, scale = dpars["scale"], shape = dpars["shape"],
  silent       = TRUE
)

tr$add_arms(sample_ratio = c(1, 1, 1), ctrl, low, high)

# --- Run Simulation ----------------------------------------------------------

l   <- listener(silent = TRUE)
l$add_milestones(m_final)
ctr <- controller(trial = tr, listener = l)
ctr$run(n = <n_replicates>, plot_event = FALSE, silent = TRUE)

# --- Summarize Results -------------------------------------------------------

out <- ctr$get_output(tidy = TRUE)

cat("Power PFS low:  ", mean(out[["pfs_low_<decision>"]]  == "reject", na.rm = TRUE), "\n")
cat("Power PFS high: ", mean(out[["pfs_high_<decision>"]] == "reject", na.rm = TRUE), "\n")
cat("Power OS low:   ", mean(out[["os_low_<decision>"]]   == "reject", na.rm = TRUE), "\n")
cat("Power OS high:  ", mean(out[["os_high_<decision>"]]  == "reject", na.rm = TRUE), "\n")
cat("Mean duration:  ", mean(ctr$get_output()[["milestone_time_<final>"]], na.rm = TRUE), "\n")

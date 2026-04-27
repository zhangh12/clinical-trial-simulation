## Phase 3 oncology PFS simulation
## Two arms (placebo vs experimental), 1:1; group-sequential with one interim
## (66% IF) and one final, O'Brien-Fleming alpha spending (STUBBED), log-rank.

suppressPackageStartupMessages({
  library(TrialSimulator)
  library(survival)
})

## ---- Parameters --------------------------------------------------------------

median_pfs_placebo <- 60
hazard_ratio       <- 0.74
rate_placebo       <- log(2) / median_pfs_placebo
rate_experimental  <- log(2) / median_pfs_placebo * hazard_ratio

dropout_rate <- -log(1 - 0.025) / 12

n_patients     <- 1200
trial_duration <- 120

accrual_rate <- data.frame(
  end_time       = c(1, 2, 3, 4, 5, 6, Inf),
  piecewise_rate = c(9, 15, 21, 27, 33, 39, 42)
)

target_events_final   <- 346
target_events_interim <- round(0.66 * target_events_final)

## STUB: O'Brien-Fleming z-boundaries (Lan-DeMets alpha spending,
## one-sided alpha = 0.025, IF1 = 0.66, IF2 = 1.0).
## Replace with GroupSequentialTest when supported.
z_bound_interim <- 2.413
z_bound_final   <- 1.985
p_bound_interim <- 1 - pnorm(z_bound_interim)
p_bound_final   <- 1 - pnorm(z_bound_final)

## Run mode: "sanity" (n=5) -> "calibration" (n=50) -> "production" (n=1000).
mode         <- "production"
n_replicates <- switch(mode, sanity = 5, calibration = 50, production = 1000)
n_workers    <- 4

## ---- Endpoints ---------------------------------------------------------------

ep_pfs_placebo <- endpoint(
  name      = "pfs",
  type      = "tte",
  generator = rexp,
  rate      = rate_placebo
)

ep_pfs_experimental <- endpoint(
  name      = "pfs",
  type      = "tte",
  generator = rexp,
  rate      = rate_experimental
)

## ---- Arms --------------------------------------------------------------------

arm_placebo <- arm(name = "placebo")
arm_placebo$add_endpoints(ep_pfs_placebo)

arm_experimental <- arm(name = "experimental")
arm_experimental$add_endpoints(ep_pfs_experimental)

## ---- Trial -------------------------------------------------------------------

## Bake the rate into the closure so mirai workers don't need the global.
dropout_fn <- local({
  rate <- dropout_rate
  function(n, ...) rexp(n = n, rate = rate)
})

tr <- trial(
  name         = "pfs_gs",
  n_patients   = n_patients,
  duration     = trial_duration,
  enroller     = StaggeredRecruiter,
  accrual_rate = accrual_rate,
  dropout      = dropout_fn
)
tr$add_arms(sample_ratio = c(1, 1), arm_placebo, arm_experimental)

## ---- Action functions --------------------------------------------------------

action_interim <- function(trial, p_bound, ...) {
  data <- trial$get_locked_data(milestone_name = "interim")

  lr <- fitLogrank(
    formula     = Surv(pfs, pfs_event) ~ arm,
    placebo     = "placebo",
    data        = data,
    alternative = "less"
  )

  cox <- fitCoxph(
    formula     = Surv(pfs, pfs_event) ~ arm,
    placebo     = "placebo",
    data        = data,
    alternative = "less",
    scale       = "hazard ratio"
  )

  reject_interim <- as.integer(lr$p <= p_bound)

  trial$save_custom_data(value = reject_interim,
                         name = "reject_interim_state",
                         overwrite = TRUE)

  trial$save(value = reject_interim, name = "reject_interim")
  trial$save(value = lr$z,           name = "z_interim")
  trial$save(value = lr$p,           name = "p_interim")
  trial$save(value = cox$estimate,   name = "hr_interim_estimate")
}

action_final <- function(trial, p_bound, ...) {
  data <- trial$get_locked_data(milestone_name = "final")

  lr <- fitLogrank(
    formula     = Surv(pfs, pfs_event) ~ arm,
    placebo     = "placebo",
    data        = data,
    alternative = "less"
  )

  cox <- fitCoxph(
    formula     = Surv(pfs, pfs_event) ~ arm,
    placebo     = "placebo",
    data        = data,
    alternative = "less",
    scale       = "hazard ratio"
  )

  reject_final <- as.integer(lr$p <= p_bound)

  reject_interim_prev <- trial$get(name = "reject_interim_state")
  if (is.null(reject_interim_prev)) reject_interim_prev <- 0L
  reject_overall <- as.integer(reject_interim_prev == 1L | reject_final == 1L)

  trial$save(value = reject_final,   name = "reject_final")
  trial$save(value = reject_overall, name = "reject_overall")
  trial$save(value = lr$z,           name = "z_final")
  trial$save(value = lr$p,           name = "p_final")
  trial$save(value = cox$estimate,   name = "hr_final_estimate")
}

## ---- Milestones --------------------------------------------------------------

m_interim <- milestone(
  name    = "interim",
  when    = eventNumber(endpoint = "pfs", n = target_events_interim),
  action  = action_interim,
  p_bound = p_bound_interim
)

m_final <- milestone(
  name    = "final",
  when    = eventNumber(endpoint = "pfs", n = target_events_final),
  action  = action_final,
  p_bound = p_bound_final
)

## ---- Listener / controller ---------------------------------------------------

l <- listener()
l$add_milestones(m_interim, m_final)

ctr <- controller(trial = tr, listener = l)

## ---- Run ---------------------------------------------------------------------

cat(sprintf("\nRunning %d replicates with %d workers (mode = %s)...\n\n",
            n_replicates, n_workers, mode))

t0 <- Sys.time()
ctr$run(n = n_replicates, n_workers = n_workers)
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("\nElapsed: %.1f seconds (%.2f sec/replicate)\n",
            elapsed, elapsed / n_replicates))

out <- ctr$get_output()

## ---- Operating characteristics ----------------------------------------------

power_interim <- mean(out$reject_interim)
power_overall <- mean(out$reject_overall)
mcse_interim  <- sqrt(power_interim * (1 - power_interim) / n_replicates)
mcse_overall  <- sqrt(power_overall * (1 - power_overall) / n_replicates)
expected_dur  <- mean(out[["milestone_time_<final>"]])

ms_summary <- summarizeMilestoneTime(out)

cat("\n================ Operating Characteristics ================\n")
cat(sprintf("Power at interim (early stop):    %.3f  (MCSE %.3f)\n",
            power_interim, mcse_interim))
cat(sprintf("Overall power:                    %.3f  (MCSE %.3f)\n",
            power_overall, mcse_overall))
cat(sprintf("Expected trial duration (mo):     %.1f\n", expected_dur))
cat(sprintf("Mean interim trigger time (mo):   %.1f\n",
            mean(out[["milestone_time_<interim>"]])))
cat("\nMilestone time summary:\n")
print(ms_summary)

## Save plot of milestone times to PNG.
tryCatch({
  ms_plot <- plot(ms_summary)
  ggplot2::ggsave(filename = "milestone_times.png",
                  plot     = ms_plot,
                  width    = 7, height = 4, dpi = 150)
  cat("\nMilestone-time plot saved to milestone_times.png\n")
}, error = function(e) {
  pdf(file = "milestone_times.pdf", width = 7, height = 4)
  on.exit(dev.off(), add = TRUE)
  print(plot(ms_summary))
  cat("\nMilestone-time plot saved to milestone_times.pdf\n")
})

saveRDS(out,        file = "pfs_gs_output.rds")
saveRDS(ms_summary, file = "pfs_gs_milestone_summary.rds")
cat("\nFull output saved to pfs_gs_output.rds\n")

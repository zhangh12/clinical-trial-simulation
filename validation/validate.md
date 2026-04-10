# Self-Validation Instructions

## Generator Validation (run before full trial validation)

### NORTA-based endpoints
Whenever a NORTA generator (`simdesign_norta`) is used, validate the empirical correlation
before proceeding to trial-level validation:

```r
dat      <- ep$test_generator(n = 10000)
emp_cor  <- cor(dat[, c("<ep1>", "<ep2>", ...)])  # Pearson correlation
max_diff <- max(abs(emp_cor - Sigma))
if (max_diff > 0.05) {
  stop(sprintf("NORTA correlation check failed: max |empirical - target| = %.3f. ",
               max_diff),
       "Check: (1) dist list order matches column order in generator, ",
       "(2) Sigma is a valid positive-definite correlation matrix.")
}
```

Threshold of 0.05 is a practical tolerance for n = 10000.
If the check fails, do not proceed to trial-level validation.

---

## Goal
After generating R code, validate it by running it in R and fixing errors before returning it to the user.

---

## Validation Steps

### Step 1: Write code to a temp file
Write the generated R code to `/tmp/trial_sim_validate.R`.

### Step 2: Run with Rscript
```bash
Rscript /tmp/trial_sim_validate.R 2>&1
```
Use a small number of replicates for speed: set `n_trials = 3` during validation.

### Step 3: Interpret output

| Output | Action |
|--------|--------|
| Clean run, results printed | Pass — restore `n_trials` to user's intended value |
| `Error in ...` | Fix the error, re-run |
| `Warning: ...` | Evaluate — warnings about units or data may be important |
| No output / silent | Check that `trial$save()` calls exist and `get_output()` is called |

### Step 4: Fix and re-run
- Fix one error at a time
- Re-run after each fix
- Maximum 3 fix cycles; if still failing, explain the issue to the user

---

## Common Errors and Fixes

| Error pattern | Likely cause | Fix |
|---------------|--------------|-----|
| `object not found: <ep>_event` | Generator missing event column | Add `<ep>_event = 1L` column to generator |
| Column name mismatch | `name` in `endpoint()` ≠ generator column names | Align names |
| `arm not found` in `remove_arms()` | Arm name typo or already removed | Check arm names match `arm("name")` calls |
| Units inconsistency warning | readout / duration / dropout in different units | Standardize all to same unit (months or weeks) |
| `milestone_name` not found in `get_locked_data()` | Milestone name mismatch | Ensure `milestone(name=)` matches `get_locked_data(name)` |
| Empty data frame from `get_locked_data()` | Trigger condition never met with small n_trials | Increase `n_trials` or check trigger threshold |

---

## Placeholder Handling
If code contains `# TODO:` or `# USER CODE PLACEHOLDER:` blocks:
- Replace with a no-op that still allows the code to run: `result <- NA`
- Ensure `trial$save()` is called with the placeholder value
- Note to user which placeholders remain and what they need to fill in

---

## After Validation
- Report: "Code validated successfully with `n_trials = 3`."
- Restore `n_trials` to the user's intended value
- List any remaining placeholders the user must fill
- Offer to run a larger validation (e.g., `n_trials = 100`) if user wants a quick operating characteristics check

---

## Delivering the Final Script

**All validation code is for the agent's internal use only — never include it in the script returned to the user.**

This includes:
- `ep$test_generator()` calls and correlation checks
- Temporary `n_trials = 3` settings (restore to intended value)
- Any `stop()` / diagnostic checks added during validation

**Never return a script with placeholders (e.g., `<median_os>`, `<n_events>`).**

The script returned to the user must be the exact script that was validated — same values, no substitutions. If a parameter value has not been provided by the user, ask for it before generating the script. A placeholder cannot be validated and a validated script cannot contain placeholders — these are mutually exclusive.

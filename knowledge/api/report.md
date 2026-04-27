# Simulation Report — Structure for QC

This file describes how to write the simulation report at the end of
the workflow. **It is the policy hook for organizational
customization** — edit this file to encode your group's reporting
standards. Defaults below are reasonable starting points.

## Purpose

The report is what the user reads. It serves three purposes:

1. **Answer the research questions.** Operating characteristics
   presented next to the questions they answer.
2. **Enable QC.** A reviewer audits each piece incrementally — code,
   rationale, and result side by side.
3. **Reproducibility.** The report plus the script is enough to rerun
   the simulation and get the same results.

## Structure: build-order spine

Mirror the build order in the report. The agent assembled the
simulation block by block; the report walks the reader through the
same sequence. Each section pairs (a) the relevant code snippet,
(b) a short paragraph explaining what was implemented and the
parameters used, (c) caveats inline if any.

```
1. Why this design                — opening rationale (thought trail)
2. Confirmed parameters           — single source of truth (table)
3. Endpoints                      — per unique endpoint structure
4. Arms                           — per arm (brief; reference §3)
5. Trial setup                    — n, duration, accrual, dropout, stratification
6. Milestones                     — per milestone (trigger + action summary)
7. Action functions               — per action (detailed)
8. Operating characteristics      — mapped back to research questions
9. Caveats and limitations        — placeholders, stubs, helper-dependencies
```

### 1. Why this design

A short paragraph (3-6 sentences) capturing the reasoning that led to
this design.

- **Mode A (exploration):** include the alternatives that were
  considered and briefly why each was set aside. This is a thought
  trail — visible reasoning is more auditable than polished claims.
- **Mode B (implementation):** restate the user's brief in the
  agent's words so the user can confirm the interpretation.

### 2. Confirmed parameters

A single table that is the source of truth for every value used in
the simulation. Subsequent sections reference this table rather than
restating numbers. Include:

- Endpoint distribution parameters per arm
- Readout times for non-TTE endpoints
- Correlation structure (and which generator implements it)
- Sample size, duration, accrual schedule, dropout
- Stratification factors
- Milestone trigger thresholds
- Helper-derived literals with the helper that produced them
  (e.g., `h01 = 0.075` from `solveThreeStateModel(median_pfs=7, median_os=15, corr=0.68)`)

If a parameter is a stub (dummy decision rule, placeholder for a
combination test), mark it clearly in this table.

### 3. Endpoints

Group by **unique endpoint structure**, not per arm. Three arms with
the same endpoint shape but different medians get one section
explaining the structure plus a per-arm parameter table. This makes
"the only differences are the medians I asked for" trivially
verifiable.

For each endpoint structure:
- Show the `endpoint(...)` call (one arm's parameters; cite the table
  for others).
- One short paragraph: what the endpoint represents clinically,
  what distribution / generator was chosen and why, readout time if
  non-TTE, any helper used to derive parameters.
- Caveats inline (e.g., "`CorrelatedPfsAndOs3` is incompatible with
  Cox PH; final analysis uses log-rank instead.")

### 4. Arms

Brief — the heavy lifting was in §3. Per arm:
- Show `arm(...)` and `$add_endpoints(...)`.
- One sentence on filter conditions (if any) and sample ratio.

### 5. Trial setup

Show the `trial(...)` call. Explain:
- Sample size and duration (and whether `set_duration`/`resize` will
  modify them adaptively).
- Accrual schedule and the rationale (e.g., "30/mo for the first 6
  months reflects ramp-up; 50/mo thereafter").
- Dropout: which distribution and the helper that produced its
  parameters (`weibullDropout(...)` if used).
- Stratification factors (if any) and which baseline endpoints
  implement them.

### 6. Milestones

Per milestone:
- Show the `milestone(...)` call with its `when` condition.
- One paragraph: what triggers it (in clinical terms), what happens
  at the trigger, when in the trial it is expected to fire (cite
  expected milestone time from the calibration run if available).

### 7. Action functions

Per action function (more detail than §6):
- Show the action body.
- Substructure:
  - **Trigger** — restate from §6.
  - **Data lock** — what `get_locked_data` returns at this point;
    which arms / endpoints are populated.
  - **Analysis** — which test, which wrapper, why this choice. **If
    a stub for a combination/group-sequential test, flag it
    prominently.**
  - **Adaptation** — which `trial$*()` methods are called, with the
    rule. **If a dummy rule, flag it: "DUMMY: replace with actual
    rule."**
  - **What gets saved** — each `trial$save()` mapped to which
    operating characteristic it supports.

### 8. Operating characteristics

For each operating characteristic the user asked about:
- Restate the research question in the user's words.
- Show the answer (number, with the post-processing call that
  produced it: e.g., `mean(out$reject_h0)`).
- A small table or plot if the OC has structure (per-arm power,
  per-stage decision rates, allocation distribution).
- Cite which `trial$save()` call from §7 supplies the underlying
  value.

Include `summarizeMilestoneTime(out)` output for milestone-time
distributions — it answers "when does the trial finish?" almost for
free.

If applicable, include Monte Carlo standard error estimates next to
each OC so the reader can judge precision (e.g., for a power estimate
`p` from `n` replicates, MCSE ≈ √(p(1−p)/n)).

### 9. Caveats and limitations

A short list of things the user should know:
- Dummy decision rules that need replacement before the design is
  finalized
- Stubs for combination/group-sequential/graphical tests
- Helper-derived literals that depend on assumed inputs (e.g.,
  Pearson correlation from `solveThreeStateModel`)
- Sample-size / runtime trade-offs in the production run
- Any deviations from the original user brief

Caveats that apply to a single section can also appear inline within
that section — duplicate placement is fine if it improves
auditability.

## Output format

Default: write the report as Markdown, render it to HTML alongside,
and open the HTML in the user's default browser when ready.

```r
Rscript -e 'markdown::mark_html("report.md", output = "report.html"); browseURL("report.html")'
```

`markdown::mark_html()` is what RStudio's Markdown Preview button
uses, so the rendered HTML matches the style the user is already
familiar with. The HTML is the user's primary view; the `.md` is
the source of truth for any edits.

Place the report in the per-trial output folder (see SKILL.md
"Output organization") with consistent filenames — `report.md` /
`report.html` is the suggested default.

If the user explicitly wants a different format (Quarto,
`rmarkdown::render` with a custom template, an internal corporate
template), ask early and use that instead. The default above is for
when the user has not specified.

## Editing this file

This file is intentionally policy-light. If your organization has
specific reporting requirements — required disclosures, naming
conventions, regulatory boilerplate, audit-trail formats — edit this
file to encode them. The agent will follow whatever this file says.

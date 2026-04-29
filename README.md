# Clinical Trial Simulation Skill

An agent skill for designing and simulating clinical trials using the
[TrialSimulator](https://github.com/zhangh12/TrialSimulator) R package.
The skill walks a biostatistician through the design in plain language,
assembles a TrialSimulator script from building blocks, runs it, and
produces a QC-ready report that pairs each block of code with rationale,
parameters, and operating characteristics.

## What it does

- Listens to the user's brief (exploration mode) or maps a structured
  spec (implementation mode) to TrialSimulator's building blocks
  (`endpoint`, `arm`, `trial`, `milestone`, `listener`, `controller`,
  `regimen`).
- Asks plain-language questions to fill in argument values, in the
  package's standard build order, and confirms a parameter table and
  a save plan before writing any code.
- Generates a runnable R script split by purpose (`main.R`,
  `actions.R`, `generators.R`, `helpers.R`, `boundaries.R`) inside a
  per-trial output folder.
- Validates iteratively (sanity → calibration → production) and runs
  the simulation single-process by default; uses parallelism only
  when runtime warrants it.
- Writes a build-order-spine report — Markdown plus rendered HTML —
  with one bundled section per arm, full action-function bodies
  shown verbatim, operating characteristics mapped back to the
  user's research questions, and caveats inline.

## Scope

In scope:

- Fixed designs (any number of arms, any TTE / non-TTE endpoint mix)
- Group-sequential designs with `rpact` or `gsDesign` for boundaries
- Dose-selection / seamless designs via `trial$dunnettTest` +
  `trial$closedTest`
- Multi-endpoint multiplicity: Bonferroni, hierarchical / fixed-
  sequence, graphical testing (`GraphicalTesting`)
- Custom data models (NORTA, mixture exponentials, Gumbel copula,
  three-state illness-death, four-state Markov)
- Parameter solvers (`solveThreeStateModel`,
  `solveMixtureExponentialDistribution`,
  `solvePiecewiseConstantExponentialDistribution`, `weibullDropout`)
- Dynamic treatment switching via `regimen()`
- Adaptive arm addition / removal / sample-size reassessment / etc.

Out of scope (planned for future iterations):

- The package's built-in `GroupSequentialTest` class (use rpact /
  gsDesign in the meantime)
- Some advanced adaptive designs (e.g., promising-zone SSR with
  combination test from scratch)

## Requirements

- **R** ≥ 4.1
- **R packages** (CRAN unless noted):
  - [TrialSimulator](https://github.com/zhangh12/TrialSimulator)
    (the simulation engine; install from GitHub for the latest)
  - `survival`
  - `rpact` *or* `gsDesign` (for group-sequential boundary
    computation; either is fine)
  - `markdown` (for rendering the report to HTML)
  - `mirai` (only if `n_workers > 1`; not needed by default)
  - `simdata` (only if NORTA correlated endpoints are used)
  - `DoseFinding` (only if MCPMod-style dose ranging is used)
- **Agent** capable of executing the
  [Agent Skills Specification](https://github.com/anthropics/skills)
  (Claude Code, or any compatible agent).

## How to use

### Claude Code

A slash command is bundled at `.claude/commands/simulate.md`. From a
session inside this repo:

```
/simulate
```

The agent loads `SKILL.md` and the cached references in
`knowledge/api/` and starts the conversation.

### Other agents

Point your agent at `SKILL.md` as the entry document. It declares
the skill's `name` and `description` in YAML frontmatter and sources
the rest of the skill (`knowledge/api/building_blocks.md`,
`knowledge/api/helpers.md`, `knowledge/api/report.md`).

## Output layout per simulation run

```
runs/<trial_name>/
  scripts/
    main.R          building blocks + listener + controller + run
    actions.R       action functions (if any)
    generators.R    custom generators (if any)
    helpers.R       helpers used by generators / actions (if any)
    boundaries.R    external boundary computation via rpact / gsDesign (if any)
  output.rds        saved per-replicate output
  report.md         Markdown report
  report.html       rendered with markdown::mark_html
  milestone_times.png
```

## Status

Pre-release; under active development. The skill is being iterated
against test simulations and feedback from the package author. See
the commit history for changes.

## License

MIT — see [LICENSE](LICENSE).

## Author

Han Zhang — author of the
[TrialSimulator](https://github.com/zhangh12/TrialSimulator) R package.

## Contributing

Issues and pull requests welcome. The skill aims to be a thinking
framework, not a prescriptive script — contributions that simplify
the agent's path or correct package-specific behavior are especially
valued.

## Pharma Skills

This skill is intended to be merged upstream into the
[R Consortium pharma-skills](https://github.com/RConsortium/pharma-skills)
collection. The directory layout follows that repo's conventions
(SKILL.md with frontmatter, README.md, LICENSE).

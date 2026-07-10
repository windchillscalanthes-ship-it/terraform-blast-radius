# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] — 2026-07-10

### Added

- Initial release of the **terraform-blast-radius** Claude Agent Skill.
- `SKILL.md` with a 12-item, provider-aware risk catalog (forces-replacement on
  stateful vs. stateless resources, resource removal/rename, the count index-shift
  bomb, `state rm` / `-replace` / `-target`, provider-upgrade replacements, shared-
  resource blast radius, missing `prevent_destroy`, unreviewed plans), a review
  workflow, and an output template that leads with data loss.
- Reference guides for AWS (forces-replacement + data-loss catalog), Google Cloud
  and Azure equivalents, the Terraform/OpenTofu lifecycle meta-arguments and
  dangerous CLI/state operations, and provider-agnostic patterns (reading a plan,
  `count` vs `for_each`, blast-radius analysis, replacing a stateful resource with
  zero downtime, state safety).
- Five worked before/after examples that double as a test corpus.
- Professional README: hero demo, problem→solution→result narrative, worked
  scenarios, a "why a skill vs. a plain prompt" positioning section, and a
  comparison to policy-as-code and plan linters.
- Hand-built SVG hero (`assets/hero.svg`) that renders on GitHub with no external
  assets, plus a demo-recording plan in `assets/README.md`.
- Community scaffolding: contribution guide, code of conduct, GitHub Issue Forms
  (bug / pattern / feature) + PR template, `ROADMAP.md`, `SECURITY.md`, and a CI
  workflow that validates the skill structure.

[Unreleased]: https://github.com/windchillscalanthes-ship-it/terraform-blast-radius/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/windchillscalanthes-ship-it/terraform-blast-radius/releases/tag/v0.1.0

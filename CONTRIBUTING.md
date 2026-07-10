# Contributing to terraform-blast-radius

Thank you for helping people apply infrastructure changes without taking prod
down. Providers are deep and their replacement rules are specific, so
**corrections and additions are the most valuable thing you can contribute** — a
single accurate rule about which attribute forces replacement can save someone a
destroyed database.

## Ways to contribute

- **Fix a rule.** If we name the wrong forcing attribute, mislabel a resource's
  statefulness, or call a destructive change "safe," correct it. Cite the
  provider registry docs in your PR.
- **Add a pattern.** A destructive change or operation we don't cover yet.
- **Add provider coverage.** DigitalOcean, Kubernetes, Cloudflare, Oracle Cloud,
  etc.
- **Add a worked example.** A new `unsafe.tf` / `safe.tf` pair under `examples/`.
- **Improve the docs.** Clarity, typos, better explanations.

## Project layout

```
SKILL.md              # entry point: trigger description, workflow, risk catalog, output template
reference/            # on-demand deep knowledge (loaded only when relevant)
  aws.md              # AWS forces-replacement + data-loss catalog (the most detailed)
  gcp-azure.md        # Google Cloud & Azure equivalents
  lifecycle.md        # lifecycle meta-args, moved/removed blocks, dangerous CLI/state ops
  patterns.md         # provider-agnostic: reading a plan, count-vs-for_each, blast radius, state safety
examples/             # unsafe/safe pairs that also serve as a test corpus
```

Keep `SKILL.md` lean — it's loaded often, so only the high-frequency catalog and
the workflow live there. Push provider depth into `reference/`. This "progressive
disclosure" split is deliberate; please preserve it.

## Standards for a rule change

A good rule PR states, for each resource/change:

1. **What forces replacement** (the attribute) or **what destroys** (the operation).
2. Whether the resource is **stateful (data loss)** or **stateless (downtime)**.
3. The **blast radius** — what depends on it.
4. A **safe approach** — copy-pasteable HCL (`lifecycle`, `moved`, `for_each`) or
   the ordered out-of-band migration steps.
5. **A source** — link the provider's registry documentation.

Accuracy over completeness. A precise rule for one resource beats a vague rule for
a whole provider. When in doubt about whether an attribute forces replacement,
say so rather than guessing — a wrong "safe" is worse than an omission.

## Adding an example

1. Create `examples/NN-short-name/` with an `unsafe.tf` and a `safe.tf`.
2. Comment both files: the `unsafe` one should show the plan action
   (`-/+`, `# forces replacement`) and the consequence; the `safe` one should
   show the rewrite and the resulting plan (e.g. "0 to destroy").
3. Add a row to the table in `examples/README.md`.

The CI check requires that any folder with an `unsafe.*` also has a matching
`safe.*`. The example `.tf` files are illustrative and are never applied.

## Testing your change by hand

There's no build step. To sanity-check, install the skill locally (see the
README), then ask Claude to review the relevant `unsafe.tf` and confirm it
produces guidance equivalent to your `safe.tf`.

## Pull request process

1. Fork and create a branch: `git checkout -b add-kubernetes-provider`.
2. Make the change; keep it focused (one logical change per PR).
3. Update `CHANGELOG.md` under `## [Unreleased]`.
4. Open the PR using the template; describe the danger and cite your source.

By contributing you agree your work is licensed under the project's
[MIT License](LICENSE).

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By
participating you're expected to uphold it.

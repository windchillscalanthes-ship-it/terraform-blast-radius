# Design notes

Why the skill is built the way it is. Useful if you want to contribute or adapt
the approach to another domain.

## Goal

Encode the specific, provider-dependent, easy-to-forget knowledge about **which
Terraform changes destroy and recreate a resource** so that Claude applies it
consistently — during authoring and during review — and produces a *safe rewrite
or migration path*, not just a warning.

## Why a Skill (and not a prompt or a plan linter)

- **vs. a one-off prompt:** a skill is discovered automatically from its
  `description` and reused across every session and project. The knowledge lives
  in version control, improves over time, and travels with the team.
- **vs. policy-as-code (OPA/Sentinel) or plan linters:** those are excellent for
  *enforcing* rules in CI, but they gate a plan you've already written and rarely
  explain the mechanism or write the fix. This skill reasons across providers at
  authoring/review time, explains *which attribute forces replacement and why*,
  and *writes the corrected HCL or the migration steps*. The two are
  complementary — enforce policy in CI, use the skill while you author and review.

## Progressive disclosure

Agent Skills reward keeping the always-loaded surface small:

- `SKILL.md` holds the **trigger description**, the **workflow**, the
  **high-frequency risk catalog** (the ~12 changes that cause most destructive
  applies), and the **output template**. It's designed to be enough for the common
  case on its own, and it is deliberately provider-agnostic.
- `reference/*.md` holds the **long tail** — per-provider forces-replacement
  tables, the lifecycle/state toolbox, and the deeper patterns. These are pulled
  in **only when relevant** to the change under review.

This keeps the common path cheap while making deep knowledge available on demand.
Contributors should preserve the split: lean `SKILL.md`, deep `reference/`.

## Severity model

Three levels, because "destructive" isn't binary:

- 🔴 **Destructive** — will destroy & recreate a resource that serves traffic or
  holds data, orphan a resource, or cascade to dependents.
- 🟡 **Caution** — a replacement that's safe only under a stated condition
  (stateless, `create_before_destroy` present, dev/sandbox, low traffic), or a
  change with a wide blast radius that needs a human to review the dependents.
- 🟢 **Safe** — an in-place update, an additive create, or a no-op.

The 🟡 tier is where the value concentrates: replacing a stateless instance with
`create_before_destroy` can be completely safe, while the *same plan verb* on a
database is a catastrophe. The differentiator is **statefulness**, so the skill is
told to classify that first, every time.

## Output as a safe path — not just a verdict

Every finding must include the safe rewrite: the corrected HCL, the `moved` block,
the `for_each` refactor, or the ordered snapshot→restore / blue-green steps when
data has to move. A review that says "this will destroy the database" without the
path to changing it safely just moves the hard part back onto the user — which is
exactly the expertise the skill is supposed to supply.

## Right-sizing

The skill is instructed to recognize throwaway/dev resources and *not* prescribe a
zero-downtime migration for a sandbox instance nobody depends on. The question is
always what gets destroyed and whether it holds data or serves traffic.
Over-triggering erodes trust as much as under-triggering.

## Non-goals

- It is **not** a substitute for a real staging environment and a tested
  backup/restore.
- It does **not** connect to your cloud accounts or read your state; it reasons
  from the plan/HCL and the context you provide.
- It does **not** replace policy-as-code in CI — run that too.

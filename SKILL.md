---
name: terraform-blast-radius
description: >-
  Review a Terraform or OpenTofu plan for destructive changes before you apply —
  the resources that will be destroyed and recreated (downtime), the stateful ones
  whose replacement means data loss, renames and count shifts that trigger mass
  recreation, and changes to shared resources with a wide blast radius. Explains
  which attribute forces replacement and rewrites the change to be safe with
  lifecycle rules, moved/removed blocks, for_each, or an out-of-band migration.
  Use whenever writing, reviewing, or about to apply Terraform/OpenTofu — reading a
  `terraform plan`, changing a resource attribute, renaming or removing a resource,
  upgrading a provider, or touching a database, disk, bucket, or other resource
  that holds data.
license: MIT
---

# Terraform Blast-Radius Review

Catch the infrastructure change that quietly destroys and recreates a resource —
and turn it into a safe apply before it takes production down or deletes your data.

A single innocent-looking edit (a renamed resource, a changed `name`, a new
`engine_version`, removing one element from a `count` list) can make Terraform
plan a **destroy-and-recreate** instead of an in-place update. On a stateless
resource that's a downtime window while it's gone; on a **stateful** one — a
database, a disk, a bucket — it's irreversible **data loss**. It passes review
because the diff looks small, and then `apply` prints `Destroy: 1` and it's too
late. This skill reads the plan, explains exactly *what* will be replaced and
*why*, and produces a safe rewrite.

## When to use this

- You are **writing** Terraform/OpenTofu and want a change checked before commit.
- You are **reviewing** a `.tf` diff or a `terraform plan` in a PR.
- You are about to **apply** — especially if the plan shows any replace or destroy.
- Someone asks "will this destroy the database?", "why is it recreating this?",
  or "how do I change this without downtime?".

If the resource is stateless, throwaway, or in a dev sandbox, a recreate may be
completely fine — say so and don't over-engineer. The question is always **what
gets destroyed, and does it hold data or serve traffic.**

## Workflow

1. **Establish context.** Identify the **provider(s) and versions** (`aws`,
   `google`, `azurerm`, …), whether you have an actual **plan output** or just the
   HCL diff, and — most important — which resources are **stateful** (hold data:
   databases, disks, volumes, buckets, caches) versus **stateless** (can be
   recreated freely). Statefulness decides whether a replacement is downtime or
   data loss.

2. **Read the plan's verbs.** Categorize every resource action:
   - `+` **create** · `~` **update in-place** (safe) ·
   - `-/+` (or `+/-`) **replace** — *destroy and recreate* ·
   - `-` **destroy** · `<=` read (data source).
   Flag **every `# forces replacement`** annotation — that attribute is the alarm.

3. **Classify each replace/destroy** against the catalog below and the resource's
   statefulness. Assign a severity:
   - 🔴 **Destructive** — will destroy & recreate a resource that serves traffic or
     holds data, orphan a resource, or cascade. Must be addressed.
   - 🟡 **Caution** — a replacement that's safe only under a condition (stateless,
     has `create_before_destroy`, low traffic, dev), or a change with a wide blast
     radius to review. Name the condition.
   - 🟢 **Safe** — in-place update, additive create, or no-op.

4. **Assess blast radius.** For each destructive change, identify what **depends
   on** the resource (a changed subnet/SG/IAM role/launch template can ripple to
   many dependents). One replacement is rarely one resource.

5. **Rewrite the 🔴/🟡s.** For each, give:
   - which **attribute forces replacement** and whether the change is avoidable,
   - the **safe approach** — `create_before_destroy`, `prevent_destroy`, a `moved`
     block, `for_each` instead of `count`, `ignore_changes`, a provider pin, or an
     **out-of-band migration** (snapshot/restore, blue-green) when data must move —
     as concrete HCL and steps, and
   - the **result** (e.g. "0 destroy, 1 in-place" or "downtime → zero-downtime
     cutover").

6. **Report** using the output template at the end. Lead with data loss, then
   downtime.

For provider- and operation-specific depth, load the reference file relevant to
the change in front of you:

- `reference/aws.md` — AWS: which attributes force replacement on the
  high-blast-radius resources (RDS/Aurora, EC2, EBS, S3, ASG/launch templates,
  security groups, IAM), and which replacements mean data loss.
- `reference/gcp-azure.md` — Google Cloud and Azure equivalents (Cloud SQL,
  Compute, persistent disks; `azurerm` databases, VMs, disks).
- `reference/lifecycle.md` — the `lifecycle` meta-arguments (`create_before_destroy`,
  `prevent_destroy`, `ignore_changes`, `replace_triggered_by`), `moved`/`removed`
  blocks, and the dangerous CLI/state operations (`-replace`/`taint`, `state rm`,
  `-target`, `import`, `destroy`).
- `reference/patterns.md` — provider-agnostic: reading a plan, the `count`-vs-
  `for_each` index-shift bomb, blast-radius analysis, replacing a stateful resource
  with zero downtime, and state safety.

Read the reference for the provider/operation in front of you rather than guessing
which attributes force replacement — they are specific and easy to get wrong.

## Risk catalog (the high-frequency offenders)

"Replace" = Terraform destroys the existing resource and creates a new one.
"Stateful" = the resource holds data that a recreate would delete.

| # | Change | Why it's dangerous | Safe approach |
|---|--------|--------------------|---------------|
| 1 | Change a **forces-replacement attribute on a stateful resource** (RDS `identifier`/`engine`/`storage_encrypted`, a disk's `name`/`zone`) | Terraform destroys and recreates it → **data loss** *and* downtime | Confirm `# forces replacement`; avoid the attribute, or migrate out-of-band (snapshot → restore, or blue-green) and add `prevent_destroy`. |
| 2 | Change a forces-replacement attribute on a **stateless** resource, no `create_before_destroy` | Default order is **destroy-then-create** → a downtime gap while it doesn't exist | `lifecycle { create_before_destroy = true }` (ensure the new one can coexist — unique names, capacity). |
| 3 | **Remove a resource from config** (delete or comment out the block) | Terraform destroys the real resource on the next apply | If intentional, fine. If refactoring, use a `moved`/`removed` block; guard critical ones with `prevent_destroy`. |
| 4 | **Rename a resource's address** or move it into/out of a module | Terraform sees the old address destroyed and a new one created → destroy + recreate | Add a `moved { from = … to = … }` block — a state move with **no real change**. |
| 5 | **`count`-based list, remove/insert a non-last element** | Every index after it **shifts** → all subsequent resources are destroyed and recreated (mass replacement) | Switch to `for_each` with **stable string keys**; index identity no longer depends on position. |
| 6 | **`terraform state rm`** | Removes the resource from state but not from the cloud → **orphaned**, unmanaged; a later create can collide | Use `moved` for refactors and a `removed` block to forget safely; don't hand-edit state casually. |
| 7 | **`terraform apply -replace=…`** / `taint` | Forces destroy + recreate on demand → **data loss** if the target is stateful | Only on stateless resources; snapshot first if it holds data. |
| 8 | **`-target`** to apply a subset | Bypasses full dependency ordering → partial apply, drift, and surprising destroys | Reserve for recovery; otherwise apply the whole reviewed plan. |
| 9 | **Provider or module version upgrade** | A changed **default** on a forces-replacement attribute can silently plan to replace many resources | Pin versions; read the upgrade guide; scrutinize the plan's replace count; `ignore_changes` where appropriate. |
| 10 | **Change a shared/foundational resource** (VPC, subnet, security group, IAM role, launch template) | Wide **blast radius** — dependents may be replaced or disrupted in a cascade | Map dependents (`terraform graph` / `state list`); stage the change or create a new versioned resource and migrate onto it. |
| 11 | **No `prevent_destroy` on critical stateful resources** | One stray attribute change or a `destroy` wipes the database with no guardrail | `lifecycle { prevent_destroy = true }` on databases, data buckets, and volumes. |
| 12 | **Apply without reviewing the plan / no saved plan** | `apply` with no `-out` re-plans at apply time; CI auto-apply can execute an unreviewed destroy | Always `plan -out=tfplan`, review the actions (especially `-/+` and the destroy count), then `apply tfplan`. |

The 🟡 tier matters: replacing a stateless resource with `create_before_destroy`
can be perfectly safe, while the *same* plan on a database is a catastrophe.
Naming which case you're in is the whole value.

## Guiding principles

- **Read the verbs.** `-/+` and `# forces replacement` are the alarms. A plan
  that only shows `~` in-place changes and `+` creates is usually safe; a plan
  with any `-` destroy or `-/+` replace demands a line-by-line look.
- **Statefulness first.** Destroying a stateless resource is *downtime*;
  destroying a stateful one is *data loss*. Classify every destroyed resource
  before anything else.
- **The default order leaves a gap.** Terraform destroys before it creates unless
  you set `create_before_destroy`. For anything that serves traffic, close the gap.
- **Guard the crown jewels.** `prevent_destroy` on every database, data bucket,
  and volume. It turns a catastrophic apply into a safe error.
- **Refactor with `moved`, remove with `removed`.** Never let a rename or a module
  move silently become a destroy.
- **`for_each` over `count`** for anything you will add to or remove from — it
  makes identity depend on a stable key, not a position.
- **Pin versions.** Provider and module upgrades are a top cause of surprise
  replacements; read the upgrade guide and re-plan.
- **Right-size the advice.** A throwaway resource in a dev sandbox can be recreated
  freely. The full dance is for stateful production infrastructure.

## Output template

```
## Terraform Blast-Radius Review

**Providers:** <e.g. aws ~> 5.60>  ·  **Scope:** <plan output / N resources>  ·  **Reviewed:** <n>

**Plan summary:** <+n> to add, <~n> to change in place, <-/+ n> to replace, <-n> to destroy.

### 🔴 <resource.address> — DESTROY / DATA LOSS
**Action:** <replace / destroy>  ·  **Forces replacement:** <attribute>
**Impact:** <downtime? data loss? what depends on it — the blast radius>
**Fix:**
<concrete HCL / steps — avoid the attribute, create_before_destroy, prevent_destroy, moved block, for_each, or an out-of-band snapshot→restore / blue-green migration>
**Result:** <e.g. "0 destroy, 1 in-place update" or "downtime → zero-downtime cutover">

### 🟡 <resource.address> — CAUTION
**Action / Why it forces replacement / Condition it's safe under / Recommendation**

### 🟢 <resource.address> — SAFE
<one line: in-place update or additive create — no disruption>

---
**Summary:** <n destroy, n replace, n caution.> <blast-radius one-liner.> <bottom line: safe to apply, or do X first.>
```

Always show the fix as something the user can apply — the corrected HCL, the
`moved` block, or the ordered migration steps — not just "this will replace the
resource." A review that names the danger without the safe path just hands the
hard part back to the user, which is exactly the expertise the skill supplies.

## Prefer JSON plans

When available, ask for `terraform plan -out=tfplan && terraform show -json tfplan` and reason from `resource_changes[].change.actions` (see `reference/patterns.md`).


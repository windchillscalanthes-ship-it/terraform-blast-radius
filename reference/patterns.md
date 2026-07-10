# Provider-agnostic patterns

The concepts behind every blast-radius review, independent of cloud. Read this for
the *why*; read the per-provider reference for which specific attribute forces
replacement. Applies equally to Terraform and OpenTofu.

## Reading a plan

Terraform's plan tells you exactly what will happen if you apply. Every resource
gets a verb — learn to read them at a glance:

| Symbol | Action | Risk |
|--------|--------|------|
| `+` | create | safe (additive) |
| `~` | update **in place** | usually safe |
| `-/+` (or `+/-`) | **replace** — destroy then create (or create then destroy) | **the alarm** |
| `-` | destroy | dangerous if it holds data or serves traffic |
| `<=` | read (data source) | safe |

Two things to scan for on every plan:

1. **The summary line.** `Plan: 2 to add, 1 to change, 3 to destroy.` A non-zero
   destroy count on a change you thought was an in-place edit is a red flag —
   stop and find out which resources.
2. **`# forces replacement`.** Terraform annotates the exact attribute whose change
   is causing a `-/+`. That attribute is the whole story: it's why the resource is
   being destroyed. Find it, and you know what to avoid or how to migrate.

```hcl
  # aws_db_instance.main must be replaced
-/+ resource "aws_db_instance" "main" {
      ~ storage_encrypted = false -> true  # forces replacement
      ...
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

That `-/+` on a database means **the database is deleted and a new empty one is
created**. The plan is telling you it will destroy your data. Read it.

> Tip: review the machine-readable plan when you can. `terraform plan -out=tfplan`
> then `terraform show -json tfplan` gives an exact list of `actions` per resource
> (`["delete","create"]` = replace) — no guessing from HCL.

## Statefulness first — downtime vs. data loss

The single most important classification. When a resource is destroyed:

- **Stateless** (compute instances, load balancers, launch templates, most network
  resources) → **downtime** while it's gone. Recoverable; often avoidable with
  `create_before_destroy`.
- **Stateful** (databases, disks/volumes, object storage, caches with persistence,
  message queues with retained data) → **data loss**. Irreversible. No lifecycle
  flag makes deleting the data safe — the data has to be *migrated*, not recreated.

Before you reason about anything else, ask of every destroyed resource: **does it
hold data?** That answer sets the severity.

## The `count` index-shift bomb

The most common self-inflicted mass replacement, and it's provider-agnostic.

`count` gives each instance an address by **position**: `aws_instance.web[0]`,
`[1]`, `[2]`. Terraform tracks them by that index. Remove or insert an element
anywhere but the end and **every subsequent index shifts by one** — so Terraform
sees each shifted position as "the resource here changed" and plans to destroy and
recreate all of them.

```hcl
# count over a list — remove "beta" from the middle...
variable "tenants" { default = ["alpha", "beta", "gamma", "delta"] }
resource "aws_instance" "web" {
  count = length(var.tenants)   # web[0..3]
  tags  = { tenant = var.tenants[count.index] }
}
# Delete "beta": gamma shifts 2->1, delta 3->2. Plan: destroy & recreate web[1], web[2], web[3].
```

**Fix: `for_each` with a stable key.** Identity becomes the key, not the position,
so removing one element touches only that one resource:

```hcl
resource "aws_instance" "web" {
  for_each = toset(var.tenants)      # web["alpha"], web["beta"], ...
  tags     = { tenant = each.key }
}
# Delete "beta": Plan: 1 to destroy (web["beta"]). alpha/gamma/delta untouched.
```

Rule: **use `count` only for genuinely interchangeable, fixed-size sets** (or a
simple on/off `count = var.enabled ? 1 : 0`). For anything you'll add to or remove
from, use `for_each`. Migrating an existing `count` resource to `for_each` can
itself trigger churn — use `moved` blocks to map each index to its new key.

## Blast-radius analysis

A destructive change is rarely one resource. When a foundational resource is
replaced, its dependents can be forced to change or replace too:

- A **security group** replacement (a `name` change forces it) can detach/reattach
  every resource that references it.
- A **subnet** or **VPC** change ripples to everything deployed into it.
- An **IAM role** replacement (a `name` change forces it) can break every service
  assuming it.
- A **launch template** change rolls through an autoscaling group's instances.

Map the dependents before applying:

- `terraform state list` and `terraform graph` show what exists and what depends
  on what.
- In the plan, a single edit that produces a *large* destroy/replace count is the
  signature of a high-blast-radius change — investigate before applying.

For big changes, prefer **making the new thing alongside the old and migrating
onto it** (a new versioned resource) over mutating the shared resource in place.

## Replacing a stateful resource with zero downtime

Sometimes a stateful resource genuinely must change in a way that forces
replacement. You can't let Terraform "just recreate" it — the data won't survive.
Do an **expand/contract (blue-green) migration** out of band, the same shape as a
zero-downtime database change:

1. **Expand.** Create the *new* resource alongside the old (new address / name),
   with `create_before_destroy` or simply as a separate resource. Don't touch the
   old one yet.
2. **Migrate the data.** Snapshot → restore, replicate, or dual-write — whatever
   the service supports (RDS snapshot restore, disk snapshot, bucket sync, DB
   replication).
3. **Cut over.** Point the application / DNS / connection string at the new
   resource. Verify.
4. **Contract.** Once you're confident and backups are taken, remove the old
   resource from config (guarded until the last moment with `prevent_destroy`).

Guard the crown jewels throughout: `prevent_destroy` and the provider's native
deletion protection stay on until the very last, deliberate step.

## State safety

The state file is the source of truth Terraform diffs against. Protect it:

- **Always apply a saved plan.** `terraform plan -out=tfplan`, review it, then
  `terraform apply tfplan`. A bare `apply` re-plans at apply time — what you
  reviewed and what runs can differ. This matters most in CI with
  `-auto-approve`, which can execute an unreviewed destroy.
- **Lock state.** Use a backend with locking (S3+DynamoDB, GCS, Terraform Cloud)
  so two applies can't corrupt state.
- **Refactor state declaratively.** `moved` to rename, `removed` to forget — not
  hand-run `state mv` / `state rm`, which are easy to get wrong and skip review.
- **Treat `-target`, `-replace`, and `taint` as break-glass**, not routine. Each
  bypasses part of the normal, reviewable flow.

## When a recreate is fine

Not every replacement is a problem. Right-size the advice:

- **Stateless and behind a load balancer / autoscaling group** — a rolling
  replacement with `create_before_destroy` is a normal, safe deploy.
- **Dev / sandbox / throwaway** — recreating a resource nobody depends on is free.
- **Empty or brand-new** — a resource with no data and no dependents can be
  replaced without ceremony.

The question is always the same: **what gets destroyed, does it hold data, and who
depends on it?** If the answer is "nothing important," don't prescribe a migration.
Over-flagging trains people to ignore the tool.

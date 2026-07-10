# Lifecycle, `moved`/`removed`, and dangerous state operations

These are the levers that decide whether a change **destroys** real
infrastructure — and the tools that let you refactor Terraform state
without touching a single running resource. Master them and most
"destroy + recreate" surprises become deliberate choices instead of
accidents.

Everything below is written for Terraform 1.x. OpenTofu maintains
parity for every feature here (it forked from Terraform 1.5.x and has
since shipped its own `moved`/`removed`/`import` support); version notes
call out the minimum release for each.

---

## 1. The `lifecycle` meta-arguments

`lifecycle` is a nested block available on **every** resource. It does
not take variables or other dynamic values — the arguments must be
literal, because Terraform evaluates them before it can safely build the
dependency graph.

```hcl
resource "aws_instance" "app" {
  ami           = "ami-0abcd1234"
  instance_type = "t3.micro"

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
    ignore_changes        = [tags["LastScanned"]]
    replace_triggered_by  = [aws_launch_template.app.latest_version]
  }
}
```

### 1a. `create_before_destroy = true`

**Default order:** when a change forces replacement, Terraform destroys
the **old** object first, then creates the new one. That is a downtime
(and, for stateful resources, data-loss) window.

Setting `create_before_destroy = true` **flips the order**: Terraform
creates the replacement first, switches references to it, and only then
destroys the old object. This is the single most important tool for
closing the replacement downtime gap
(see: developer.hashicorp.com/terraform/language/meta-arguments/lifecycle).

**The new object must be able to coexist with the old one.** During the
overlap window both exist simultaneously, so:

| Constraint      | Why it bites                                         |
| --------------- | ---------------------------------------------------- |
| Unique names    | Two resources can't share one name/identifier (e.g. an IAM role name, an S3 bucket name, an EIP allocation). Use `name_prefix` instead of `name`, or omit the name and let the provider generate one. |
| Capacity/quota  | You transiently hold **2×** the resource — watch account limits and cost. |
| Ports/addresses | Only one process can bind a fixed port or static IP at a time. |

`create_before_destroy` **propagates**: if resource B depends on
resource A and A is `create_before_destroy`, Terraform must also apply
create-before-destroy semantics to B during that replacement, or the
graph would be inconsistent. HashiCorp documents this propagation
explicitly — you cannot mix a create-before-destroy resource under a
destroy-before-create dependent. Set it deliberately and expect it to
ripple downstream.

### 1b. `prevent_destroy = true`

When set, Terraform **rejects with an error any plan that would destroy**
the object, aborting the whole plan/apply. Use it as a guardrail on
irreplaceable, stateful resources — production databases, stateful
disks, the S3 bucket holding your state.

```hcl
resource "aws_db_instance" "prod" {
  # ...
  lifecycle {
    prevent_destroy = true
  }
}
```

Precise semantics — get these right:

- It errors on **any** destroy of that object, including a
  force-replacement (destroy+create counts as a destroy) and an explicit
  `terraform destroy`. It is a plan-time check, not a runtime lock.
- **It cannot save you if you delete the resource block.** The flag
  lives *inside* the resource's `lifecycle` block. Remove the resource
  from configuration and the `lifecycle` block goes with it, so
  Terraform no longer knows the guard existed and will happily plan the
  destroy. HashiCorp calls this out directly: "this cannot prevent the
  destruction of the resource due to removing the resource block"
  (developer.hashicorp.com/terraform/language/meta-arguments/lifecycle#prevent_destroy).
  The guard protects against *replacement* and *targeted destroy*, not
  against *forgetting*. Pair it with a `removed` block (§4) or code
  review to cover that gap.
- Because it is literal-only, you can't toggle it with a variable. Teams
  that need a "break glass" switch typically comment it out in a
  reviewed PR rather than trying to parameterize it.

### 1c. `ignore_changes = [...]`

Tells Terraform to **ignore drift** in the listed attributes when
comparing configuration to prior state — so an out-of-band change (an
autoscaler bumping `desired_capacity`, a platform stamping a tag, a
provider mutating a default) does not show up as a perpetual diff or
force an update.

```hcl
lifecycle {
  ignore_changes = [
    desired_capacity,        # managed by an autoscaling policy
    tags["kubernetes.io/cluster/prod"],
  ]
}

# Ignore ALL attributes after create — the resource is created from
# config once, then never updated in place.
lifecycle {
  ignore_changes = all
}
```

`ignore_changes` takes a list of attribute references (not strings, and
not arbitrary expressions), or the bare keyword `all`. It only affects
**updates** to an existing object; it has no effect on create or
destroy.

**Right fix vs. hiding a problem.** It is the correct tool when an
attribute is *legitimately owned by something other than Terraform*
(autoscaling, an operator process, a mutating admission controller). It
is a **smell** when you reach for it to silence a diff you don't
understand — you are then blinding Terraform to real drift, and the next
person to touch the resource inherits an invisible landmine. Prefer
fixing the configuration to match reality; use `ignore_changes` only for
attributes with a genuine external owner, and scope it to the specific
attribute rather than `all`.

### 1d. `replace_triggered_by = [...]`

The **inverse** of the guards above: it *forces* replacement on purpose.
Terraform replaces this resource whenever any referenced resource,
resource attribute, or `each`/`count` instance changes. Added in
Terraform 1.2 (developer.hashicorp.com/terraform/language/meta-arguments/lifecycle#replace_triggered_by).

```hcl
resource "aws_instance" "app" {
  # ...
  lifecycle {
    # Roll the instance whenever a new launch-template version ships.
    replace_triggered_by = [aws_launch_template.app.latest_version]
  }
}
```

References must point to **managed resources in the same module**
(whole resources, single attributes, or indexed instances) — you cannot
reference input variables, data sources, or local values. A common,
correct use is chaining a stateless compute resource to a version number
or a `terraform_data`/`null_resource` trigger so it redeploys when an
input you care about changes.

---

## 2. `moved` blocks — rename/refactor with zero real change

Renaming a resource's **address** (its `type.name`, or moving it into or
out of a module, or into a `count`/`for_each`) is, by default, read by
Terraform as "the old address is gone" + "a new address appeared." The
plan is a **destroy of the old object and a create of a new one** — real
downtime and data loss for something you only meant to rename in code.

A `moved` block tells Terraform that a resource previously tracked at one
address is now the same resource at a new address. Terraform updates
**state only**; the plan shows no infrastructure change. Available since
Terraform 1.1 (developer.hashicorp.com/terraform/language/moved).

```hcl
# The resource now lives at its new address:
resource "aws_instance" "app" {
  ami           = "ami-0abcd1234"
  instance_type = "t3.micro"
}

# ...and this block records where it used to live.
moved {
  from = aws_instance.web
  to   = aws_instance.app
}
```

`moved` handles renames, moves into/out of modules
(`module.foo.aws_instance.x`), and moves to/from a `count`/`for_each`
index (`aws_instance.app[0]`). Blocks can be chained (A→B, B→C) and
Terraform resolves the final destination.

**Why prefer it over `terraform state mv`.** The legacy imperative
command mutates state on one operator's machine, out of band, with no
review and no record in the code:

| `moved` block                          | `terraform state mv`                    |
| -------------------------------------- | --------------------------------------- |
| Declarative, lives in version control  | Imperative, run once from a shell       |
| Reviewed in the PR, visible in `plan`  | Invisible to reviewers; easy to forget  |
| Reproducible on every workspace/CI     | Must be re-run manually everywhere       |
| Safe to leave in place, then remove later | No artifact; drift if someone forgets |

Keep the `moved` block for at least one apply cycle across every
workspace, then delete it once all state is migrated. This is the fix
for the "renamed resource ⇒ destroy+recreate" catalog item.

---

## 3. `removed` blocks — stop managing without destroying

To take a resource **out of Terraform's management while leaving the real
object running**, delete the `resource` block and add a `removed` block.
Introduced in Terraform 1.7 (developer.hashicorp.com/terraform/language/resources/syntax#removing-resources);
OpenTofu supports it from 1.7 as well.

```hcl
# The resource block is GONE from configuration. In its place:
removed {
  from = aws_instance.legacy

  lifecycle {
    destroy = false   # forget it, do NOT destroy the real object
  }
}
```

The `lifecycle.destroy` flag is the whole point:

| `destroy` value | Effect                                                          |
| --------------- | --------------------------------------------------------------- |
| `false`         | **Forget:** remove from state, real object keeps running. The declarative equivalent of `terraform state rm`. |
| `true`          | **Destroy:** Terraform destroys the real object (same as just deleting the resource block). |

**Forgetting vs. destroying is the distinction that matters.**
"Destroying" tears down the real infrastructure. "Forgetting" only drops
Terraform's *record* of it — the EC2 instance, database, or bucket lives
on, now unmanaged (you might be handing it to another module, another
team, or importing it elsewhere). A plain deletion of a resource block
means **destroy**; a `removed { lifecycle { destroy = false } }` means
**forget**. Making that choice explicit and reviewable is exactly why the
block exists, and it is the declarative successor to the error-prone
imperative `terraform state rm` (§5).

Like `moved`, a `removed` block is safe to leave in place for a cycle and
then delete once every workspace has applied it.

---

## 4. Dangerous CLI / state operations

These bypass or override the normal plan safety model. Each has a
failure mode and a safer, reviewable alternative.

| Command | What it does | Failure mode | Safer alternative |
| ------- | ------------ | ------------ | ----------------- |
| `terraform apply -replace=ADDR` | Forces destroy+recreate of one object on the next apply (Terraform 0.15.2+; the modern replacement for taint). | Unplanned downtime / data loss on a stateful resource; run in CI it destroys prod. | Let normal config drive it, or add `create_before_destroy` first so the replace has no downtime. Always `plan` it first. |
| `terraform taint ADDR` / `untaint ADDR` | **Deprecated** predecessor of `-replace`. Marks state as tainted so the next apply replaces it. | Mutates state out of band with no plan preview; "spooky action at a distance." | Use `-replace=ADDR` on a reviewed `plan`; taint is retained only for backward compat. |
| `terraform state rm ADDR` | Deletes an object from **state** only; real infra untouched. | **Orphans** the real resource — it keeps running and billing, now unmanaged, and a later re-`apply` may try to recreate a duplicate. Imperative and unreviewed. | A `removed { lifecycle { destroy = false } }` block (§3) — same effect, but declarative and in the PR. |
| `terraform import ADDR ID` (or `import` blocks, 1.5+) | The **inverse** of `state rm`: brings a pre-existing real object under management at `ADDR`. | Import writes state but writes **no configuration**; if your HCL doesn't match the real object, the *very next plan* shows changes — potentially a destroy/replace. Importing to the wrong address can clobber another resource. | Prefer declarative `import {}` blocks (reviewed, plannable, and can generate config with `-generate-config-out`); always run a `plan` and reconcile to `0 to change` before trusting it. |
| `terraform apply -target=ADDR` | Applies only the named object(s) and their dependencies, **skipping the rest of the graph**. | Partial apply leaves state internally inconsistent; it bypasses normal ordering and can produce drift or a surprise destroy on the next full run. HashiCorp documents it as a break-glass tool for recovering from errors, "not for routine use." | Fix the root cause and run a full `plan`/`apply`. Reserve `-target` for genuine recovery, then immediately run an untargeted apply to reconcile. |
| `terraform destroy` | Destroys **everything** in the configuration/workspace. | Wipes the whole environment; `-target` narrows it but the un-targeted form is total. | `plan -destroy` first to review; protect crown-jewel resources with `prevent_destroy`; scope by workspace. |

---

## 5. Plan hygiene: save the plan, apply the plan

Always split review from execution:

```bash
terraform plan -out=tfplan     # review this diff
terraform apply tfplan         # applies EXACTLY what you reviewed
```

When you run a bare `terraform apply` (no saved plan file), Terraform
**re-plans from scratch** at apply time and then prompts for approval on
*that* fresh plan — which may differ from anything a human reviewed if
state, a data source, or upstream infrastructure changed in between. In
CI with `-auto-approve`, there is no human at all: a bare
`apply -auto-approve` will execute whatever the fresh plan contains,
including a destroy nobody signed off on.

A saved plan file is a frozen, reviewed artifact: `terraform apply
tfplan` executes those exact actions and **refuses** to run if state has
drifted such that the saved plan is no longer applicable. That is the
control that makes "the diff I approved is the diff that ran" true. Make
`plan -out` → reviewed gate → `apply <file>` the only path to
production, and never wire `apply -auto-approve` to a bare plan.
(developer.hashicorp.com/terraform/cli/commands/plan#out-filename,
developer.hashicorp.com/terraform/cli/commands/apply.)

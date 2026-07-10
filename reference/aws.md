# AWS provider — replacement & blast-radius reference

How replacement shows up in an AWS `terraform plan`, and which changes
turn an `apply` into downtime or irreversible data loss.

Terraform reports a resource that must be destroyed and recreated with the
action symbol `-/+` ("destroy and then create replacement"). Every
attribute responsible is annotated inline with `# forces replacement`.
The provider decides this: an attribute is either updatable in place
(the AWS API exposes a `Modify*` call for it) or it is `ForceNew`
(the value can only be set at creation, so a change means delete + create).

Two very different outcomes hide behind the same `-/+` symbol:

- **Downtime** — a stateless resource (an EC2 instance, a load balancer)
  is torn down and rebuilt. Recoverable, but traffic drops in the gap.
- **Data loss** — a stateful resource (a database, a volume, a table) is
  *deleted*. The bytes are gone. A snapshot may exist; often it does not.

The core rule: **statefulness decides whether a replacement is an outage
or a catastrophe.** Read every `# forces replacement` line and ask "does
this resource hold state?" before you type `yes`.

Everything below applies identically to Terraform and OpenTofu — the
`ForceNew` behavior is a property of the `hashicorp/aws` provider
(examples verified against the v5.x provider), not of the CLI.

---

## 1. Data-loss resources (highest severity 🔴)

Replacing any of these **deletes the underlying data.** A change to a
forcing attribute is not a config tweak — it is a delete-and-recreate of
a datastore. Treat every `# forces replacement` on these as a stop-line.

| Resource | Attributes that force replacement | What is destroyed |
|---|---|---|
| [`aws_db_instance`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance) | `identifier`, `db_name`, `username`, `engine`, `storage_encrypted`, `kms_key_id`, `availability_zone`, `db_subnet_group_name`, `character_set_name`, `snapshot_identifier` | The entire database instance and all data not in a snapshot |
| [`aws_rds_cluster`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | `cluster_identifier`, `database_name`, `master_username`, `engine`, `engine_mode`, `storage_encrypted`, `kms_key_id`, `db_subnet_group_name`, `snapshot_identifier` | The Aurora cluster and every row it stores |
| [`aws_ebs_volume`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ebs_volume) | `availability_zone`, `snapshot_id`, `encrypted`, `kms_key_id` | The block volume and its filesystem |
| [`aws_dynamodb_table`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | `name`, `hash_key`, `range_key` | The table and every item in it |
| [`aws_efs_file_system`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | `creation_token`, `encrypted`, `kms_key_id`, `availability_zone_name`, `performance_mode` | The file system and all files |
| [`aws_elasticache_cluster`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_cluster) | `subnet_group_name`, `snapshot_name`, `snapshot_arns`, `network_type` | In-memory cache / session store contents |
| [`aws_elasticache_replication_group`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_replication_group) | `subnet_group_name`, `at_rest_encryption_enabled`, `kms_key_id`, `network_type` | Redis dataset (durable only if you rely on backups) |

### Notes per resource

**`aws_db_instance` / `aws_rds_cluster`.** The identity and placement
attributes are all set-at-create. The two that surprise people most:

- `storage_encrypted` — you **cannot** encrypt an existing RDS instance
  in place. Flipping `false → true` forces replacement. The supported
  path is snapshot → copy-with-encryption → restore. See the
  [argument reference](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance#storage_encrypted).
- `kms_key_id` — re-keying is likewise create-time only.

  For contrast, these are **in-place** (safe 🟢) on `aws_db_instance`:
  `allocated_storage` (increase only), `instance_class`, `engine_version`
  (an upgrade, not a replace), `multi_az`, `backup_retention_period`,
  `parameter_group_name`. Distinguishing "resize the DB" (in-place) from
  "re-identify the DB" (replacement) is the whole game here.

**`aws_ebs_volume`.** Placement (`availability_zone`), lineage
(`snapshot_id`), and encryption (`encrypted`, `kms_key_id`) are
create-time. Note the contrast: `size` (increase only), `type`
(e.g. `gp2 → gp3`), `iops`, and `throughput` are **modified in place**
via `ModifyVolume` — they do *not* force replacement. So "grow the disk"
is safe; "move the disk to another AZ" destroys it.

**`aws_dynamodb_table`.** The primary key (`hash_key`, `range_key`) and
`name` are immutable. Changing `billing_mode`, adding a GSI, or toggling
`stream_enabled` are in-place. Renaming the key = a brand-new empty table.

**`aws_efs_file_system`.** `encrypted`, `kms_key_id`, `performance_mode`,
and (for One Zone) `availability_zone_name` are all create-time. There is
no in-place re-encryption; migration is via
[AWS DataSync or a backup restore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system).

**ElastiCache.** Redis/Memcached data is *in memory*. A replacement flushes
it. If the cluster is a pure cache this is a cold-start (a caution, not a
catastrophe); if it is a session store or a Redis-as-primary-datastore it
is data loss. Note `node_type`, `num_cache_nodes`, and `engine_version`
are in-place scaling operations — those are safe.

### Related guards on these resources

- `deletion_protection = true` (RDS instance & cluster) — the AWS API
  refuses to delete, so a planned `-/+` **fails at apply** on the destroy
  step. That aborts the accident, but it also means you cannot roll the
  change forward until you consciously disable it.
- `skip_final_snapshot` (RDS) — if `false`, destroy first takes a final
  snapshot named by `final_snapshot_identifier` (a recovery path). If
  `true`, the data is gone with no snapshot. On stateful DBs keep it
  `false`.
- `prevent_destroy = true` (lifecycle) — Terraform errors at *plan* time
  if the resource would be destroyed. The strongest static guard; see §5.

---

## 2. Downtime resources (stateless but disruptive 🟡/🔴)

These hold no durable data, so replacement is recoverable — but the resource
serves traffic, and a destroy-then-create leaves a gap. Severity depends on
whether `create_before_destroy` is in play and whether the resource is
behind redundancy.

| Resource | Forces replacement on | Mitigation |
|---|---|---|
| [`aws_instance`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | `ami`, `availability_zone`, `subnet_id`, `instance_type` (only when converting to/from certain generations), `user_data` **when `user_data_replace_on_change = true`**, `ephemeral_block_device` | `create_before_destroy`; roll behind an ASG/ELB |
| [`aws_launch_template`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | *(edits create a new version — in-place `~`, not `-/+`)* | rollout controlled by the ASG, not the template |
| [`aws_autoscaling_group`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | `name`, `launch_configuration`→see note | `name_prefix` + `create_before_destroy`; `instance_refresh` |
| [`aws_lb`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | `name`, `internal`, `load_balancer_type`, `subnets` (NLB) | `name_prefix`; DNS/alias points at a new LB |
| [`aws_lb_target_group`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | `name`, `port`, `protocol`, `target_type`, `vpc_id` | `name_prefix` + `create_before_destroy` |
| [`aws_eip`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | `address`, `domain`, `public_ipv4_pool`, `customer_owned_ipv4_pool`, `network_border_group` | replacement **releases the public IP** — anything hard-coding it breaks |

### Notes

**`aws_instance` and `user_data`.** This one is widely misremembered, so be
precise. The argument
[`user_data_replace_on_change`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance#user_data_replace_on_change)
**defaults to `false`.**

- With the default (`false`): editing `user_data` is an **in-place update**
  — no replacement. The catch is that user-data scripts run once at first
  boot, so the edit is recorded but *does not re-execute* on the existing
  instance.
- With `user_data_replace_on_change = true`: editing `user_data` shows
  `-/+ ... # forces replacement`. People set this on purpose — it is the
  only way to make the new script actually run — which is exactly why the
  destroy-then-create downtime catches teams off guard. See example
  `03-ec2-user-data`.

**`aws_launch_template` + `aws_autoscaling_group`.** Editing a launch
template does **not** replace it — the provider publishes a new *version*
(an in-place `~`). Whether running instances get rebuilt depends on the
ASG's `instance_refresh` block or an external rollout. The disruptive step
is the ASG rollout, not the template edit. On the ASG itself, `name` is
`ForceNew`; the standard pattern is `name_prefix` with
`lifecycle { create_before_destroy = true }`.

**`aws_eip`.** An EIP is not "data," but the public IP address *is* a
dependency other systems hard-code (DNS, firewall allowlists, partner
integrations). Replacement releases the old address and allocates a new
one — treat as 🔴 if anything external pins the IP.

---

## 3. Wide blast-radius resources (cascades 🔴)

Replacing these does not just recreate one thing — it changes an ID that
other resources depend on, and the destruction (or the new ID) ripples
outward to everything downstream.

| Resource | Forces replacement on | Cascade |
|---|---|---|
| [`aws_security_group`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | `name`, `name_prefix`, `description`, `vpc_id` | new `sg-id`; every instance/ENI/rule referencing the old ID must be re-associated |
| [`aws_subnet`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | `availability_zone`, `cidr_block`, `vpc_id`, `outpost_arn` | instances, ENIs, NAT gateways, RDS subnet groups pinned to the subnet |
| [`aws_vpc`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | `cidr_block` (primary IPv4), `ipv4_ipam_pool_id`, `instance_tenancy` (`default → dedicated`) | **everything** in the VPC — the widest blast radius in AWS |
| [`aws_iam_role`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | `name`, `name_prefix`, `path` | instance profiles, policy attachments, and every principal/service trusting the role by ARN |

### Why these cascade

**`aws_security_group`.** The gotcha is `description` — a purely cosmetic
field that is nonetheless `ForceNew` (the AWS API has no
`ModifySecurityGroupDescription`). A one-word edit to a description forces a
new `sg-id`; instances keep the old group until re-associated, and any
*other* security group whose rules reference this one by ID loses that
reference during the swap. Inline `ingress`/`egress` rule edits, by
contrast, are in-place authorize/revoke calls (safe).

**`aws_subnet` / `aws_vpc`.** Networking primitives are referenced by ID
throughout the graph. Terraform can order the dependent replacements, but a
VPC or subnet replacement typically forces destruction of instances, NAT
gateways, and endpoints inside it — and a VPC replacement can take down the
entire environment. Changing a VPC or subnet CIDR in place is impossible in
AWS; plan a parallel network and migrate.

**`aws_iam_role`.** Renaming a role recreates it with a new ARN. Anything
that trusts the role by ARN (cross-account policies, EKS IRSA, service
integrations) or attaches to it out-of-band silently stops working. Use
`name_prefix` if the name is not externally referenced.

---

## 4. AWS-specific guards

| Guard | Where | Effect |
|---|---|---|
| `lifecycle { prevent_destroy = true }` | any resource | Terraform **errors at plan time** if the resource would be destroyed (including a `-/+`). Static, always-on. |
| `deletion_protection = true` | `aws_db_instance`, `aws_rds_cluster`, `aws_lb` | AWS API refuses the delete; a replacement **fails at apply** on the destroy step. |
| `skip_final_snapshot = false` | `aws_db_instance`, `aws_rds_cluster` | destroy takes a final snapshot first — a recovery path. Pair with `final_snapshot_identifier`. |
| `force_destroy` | `aws_s3_bucket` | if `false` (default), destroying a **non-empty bucket errors** instead of deleting. If `true`, all objects are deleted first — **data loss on purpose**. |

Notes:

- `prevent_destroy` and `deletion_protection` are complementary.
  `prevent_destroy` catches the mistake early (plan) and costs nothing;
  `deletion_protection` is enforced by AWS itself even if someone bypasses
  Terraform. Put both on production databases.
- A `-/+` plan against a resource with `prevent_destroy = true` will not
  apply at all — Terraform stops with
  `Instance cannot be destroyed`. That is the guard working; the fix is an
  out-of-band migration, not deleting the guard.
- S3 `force_destroy = false` is a feature: it means a `terraform destroy`
  of a bucket that still holds objects fails loudly rather than silently
  wiping data. Only set `true` when you genuinely intend to discard
  contents (e.g. ephemeral test buckets).

---

## 5. Reading an AWS plan

A replacement on a stateful resource looks like this. Read it top to bottom.

```hcl
  # aws_db_instance.main must be replaced
-/+ resource "aws_db_instance" "main" {
      ~ address                     = "main.abc123.us-east-1.rds.amazonaws.com" -> (known after apply)
      ~ arn                         = "arn:aws:rds:...:db:app-prod" -> (known after apply)
      ~ id                          = "app-prod" -> (known after apply)
      ~ storage_encrypted           = false -> true # forces replacement
        # (35 unchanged attributes hidden)
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

Signals, in order:

1. **`must be replaced`** and the **`-/+`** symbol — this is a
   destroy-then-create, not an update.
2. **`# forces replacement`** on `storage_encrypted` — the exact attribute
   to blame. Here it is the "you cannot encrypt in place" case from §1.
3. **`1 to destroy`** in the summary — and the resource is an
   `aws_db_instance`. Destroy of a database = **data loss** unless a
   snapshot exists.

What to do:

- **Stop.** Do not apply. This will delete the production database.
- If the attribute change is not actually required, revert it.
- If it *is* required (real re-encryption, engine change, re-identify),
  do it out of band: take a snapshot, restore into a new instance with the
  new setting, cut traffic over, then import/replace in state. See example
  `01-rds-replacement/safe.tf`.
- Add `lifecycle { prevent_destroy = true }`, `deletion_protection = true`,
  and `skip_final_snapshot = false` so the next accidental `-/+` cannot
  reach apply.

The same three signals (`must be replaced`, `# forces replacement`,
`N to destroy`) apply to every resource — only the consequence changes with
statefulness.

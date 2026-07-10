# GCP & Azure: destructive `terraform plan` reference

Scope: `hashicorp/google` (and `google-beta`) and `hashicorp/azurerm`.
Semantics described here are identical under Terraform and OpenTofu — both
read the same provider schemas, so `# forces replacement` and the `-/+`
action mean the same thing in either tool.

The one idea to keep in front of you: **statefulness decides whether a
replacement is downtime or permanent data loss.** A replaced stateless
compute node is an outage until the new one boots. A replaced database,
disk, or bucket is *gone* — the destroy runs before (or without) any backup
you did not take yourself. The plan signal is always the same:

```text
-/+ resource "..." "..." {
      ~ <attribute> = "old" -> "new" # forces replacement
    }
Plan: 1 to add, 0 to change, 1 to destroy.
```

When you see `-/+` (destroy-and-recreate) and `# forces replacement` on a
stateful resource, stop and read the rest of this file before you `apply`.

---

## The cross-cloud rule of thumb

Before the per-resource tables, memorize this. It is true across GCP, Azure,
and AWS, for the overwhelming majority of resources:

> **Changing an identity or placement attribute forces replacement.**
> Specifically: `name`, the region/zone/`location`, and the
> project/`resource_group` an object lives in are almost always
> `ForceNew`. These are not editable in the cloud API, so the provider can
> only realize the change by destroying the old object and creating a new
> one.

| Concept          | GCP attribute(s)              | Azure attribute(s)                    |
| ---------------- | ----------------------------- | ------------------------------------- |
| Identity         | `name`                        | `name`                                |
| Placement (geo)  | `region`, `zone`, `location`  | `location`                            |
| Placement (org)  | `project`                     | `resource_group_name`                 |

If your diff touches any of these on a stateful resource, assume 🔴 until the
plan proves otherwise. The rest of this file is mostly the exceptions and the
subtler forcing attributes.

---

# Part 1 — Google Cloud (`google`)

## 1.1 Data-loss resources and their forcing attributes

### `google_sql_database_instance` — 🔴 the highest-stakes resource on GCP

Holds your production database. A replacement destroys the instance, every
database and table in it, and all automated backups tied to it.

| Attribute                          | Effect on change            | Sev |
| ---------------------------------- | --------------------------- | --- |
| `name`                             | **forces replacement**      | 🔴  |
| `region`                           | **forces replacement**      | 🔴  |
| `master_instance_name`             | **forces replacement**      | 🔴  |
| `encryption_key_name` (CMEK)       | **forces replacement**      | 🔴  |
| `database_version`                 | in-place upgrade\*          | 🟡  |
| `settings.tier` (machine size)     | in-place                    | 🟢  |
| `settings.disk_size`               | in-place (grow only)        | 🟢  |
| `settings.availability_type`       | in-place                    | 🟢  |
| `root_password`                    | in-place                    | 🟢  |

\* `database_version` is **not** `ForceNew`. The provider applies supported
major-version *upgrades* in place via the Cloud SQL API (e.g.
`POSTGRES_14 → POSTGRES_15`). Downgrades are rejected by the API, not
silently destructive. Still read the plan: confirm it shows `~ ... ->` and
not `-/+`. See
[`google_sql_database_instance`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/sql_database_instance).

**Name-reuse cooldown (GCP-specific footgun):** after a Cloud SQL instance
is deleted, Google reserves its name and you **cannot create a new instance
with the same name for a cooldown period** (historically up to ~a week).
So a "rename" that forces replacement is not just data loss — the recreate
step in the *same* apply can fail because the old name is still reserved,
leaving you with nothing.

### `google_compute_disk` — 🔴 persistent data

| Attribute                   | Effect on change        | Sev |
| --------------------------- | ----------------------- | --- |
| `name`                      | **forces replacement**  | 🔴  |
| `zone`                      | **forces replacement**  | 🔴  |
| `type` (`pd-ssd`/`pd-std`)  | **forces replacement**  | 🔴  |
| `image` / `snapshot`        | **forces replacement**  | 🔴  |
| `physical_block_size_bytes` | **forces replacement**  | 🔴  |
| `size`                      | in-place (grow only)    | 🟢  |

`size` is resizable in place and can only grow; shrinking is rejected. To
change `type` (e.g. HDD→SSD) without loss you snapshot → create a new disk
from the snapshot. See
[`google_compute_disk`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_disk).

### `google_compute_instance` — 🟡 usually stateless, but watch the boot disk

The VM itself is often stateless (rebuildable from image + startup script).
The danger is the **boot disk and any disk defined inline** in `boot_disk` /
`scratch_disk`, which are destroyed with the instance.

| Attribute                          | Effect on change            | Sev |
| ---------------------------------- | --------------------------- | --- |
| `zone`                             | **forces replacement**      | 🔴  |
| `boot_disk.initialize_params.*`    | **forces replacement**      | 🔴  |
| `network_interface.*` (most)       | **forces replacement**      | 🟡  |
| `machine_type`                     | in-place (stop→resize→start)| 🟡  |
| `attached_disk` (add/remove)       | in-place                    | 🟢  |
| `metadata`, `tags`, `labels`       | in-place                    | 🟢  |

`machine_type` is **not** `ForceNew` — the provider stops the instance,
resizes, and restarts it. That is a brief outage, not data loss (assuming a
persistent, non-inline boot disk). Prefer attaching data on a separate
`google_compute_disk` so instance replacement never touches it. See
[`google_compute_instance`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/compute_instance).

### `google_storage_bucket` — 🔴 with a sharp edge

| Attribute        | Effect on change        | Sev |
| ---------------- | ----------------------- | --- |
| `name`           | **forces replacement**  | 🔴  |
| `location`       | **forces replacement**  | 🔴  |
| `storage_class`  | in-place                | 🟢  |

Two things make buckets special:

- **`force_destroy`.** By default Terraform cannot delete a non-empty
  bucket, so a `name`/`location` change will *fail* the destroy step (loud,
  but safe). If `force_destroy = true`, Terraform will **delete every object
  in the bucket** to complete the replacement. Setting `force_destroy = true`
  on a data bucket is itself a 🔴 change worth flagging.
- Bucket names are **globally unique**; a deleted name may not be
  immediately reusable and could be taken by anyone.

See
[`google_storage_bucket`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/storage_bucket).

### `google_bigtable_instance` — 🔴

| Attribute            | Effect on change        | Sev |
| -------------------- | ----------------------- | --- |
| `name`               | **forces replacement**  | 🔴  |
| `cluster.cluster_id` | **forces replacement**  | 🔴  |
| `cluster.zone`       | **forces replacement**  | 🔴  |
| `cluster.storage_type`| **forces replacement** | 🔴  |
| `cluster.num_nodes`  | in-place                | 🟢  |

Also note: **removing a `cluster` block deletes that cluster** (and its
data) even though the instance is only "updated" — an in-place update can
still destroy a replica. See
[`google_bigtable_instance`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/bigtable_instance).

### `google_redis_instance` — 🔴 for `STANDARD_HA`, 🟡 for `BASIC`

| Attribute            | Effect on change        | Sev |
| -------------------- | ----------------------- | --- |
| `name`               | **forces replacement**  | 🔴  |
| `region`             | **forces replacement**  | 🔴  |
| `tier` (BASIC/HA)    | **forces replacement**  | 🔴  |
| `authorized_network` | **forces replacement**  | 🔴  |
| `connect_mode`       | **forces replacement**  | 🔴  |
| `memory_size_gb`     | in-place (scale)         | 🟢  |

Redis is a cache, but a `STANDARD_HA` instance backing a session store or
rate limiter is effectively stateful for your users. `memory_size_gb`
scales in place. See
[`google_redis_instance`](https://registry.terraform.io/providers/hashicorp/google/latest/docs/resources/redis_instance).

## 1.2 GCP guards

GCP has real, server-side deletion protection on the two resources that
matter most — use it in addition to Terraform's lifecycle block.

- **`deletion_protection` (Terraform attribute).** On
  `google_sql_database_instance` it **defaults to `true`** and on
  `google_compute_instance` it exists (default `false`). While `true`,
  Terraform will refuse to destroy — including the destroy half of a
  replacement — and the plan errors out before touching anything. To
  intentionally replace, you must first `apply` a change setting it to
  `false`. That two-step is the point: it makes destruction deliberate.
- **`settings.deletion_protection_enabled` (Cloud SQL API flag).** Distinct
  from the above — this is the server-side guard enforced by GCP itself, not
  Terraform. Belt and suspenders; enable both.
- **`lifecycle { prevent_destroy = true }`.** Provider-agnostic. Terraform
  hard-errors at plan time on any plan that would destroy the resource.
  Unlike `deletion_protection`, changing it is a code edit (not an
  `apply`), so it is a strong guard for "this should never be replaced."

```hcl
resource "google_sql_database_instance" "main" {
  # ... server-side guards ...
  deletion_protection = true
  settings {
    deletion_protection_enabled = true
  }
  # ... Terraform-level guard ...
  lifecycle {
    prevent_destroy = true
  }
}
```

---

# Part 2 — Azure (`azurerm`)

Azure differs from GCP in one important way: **most resources have no
per-resource `deletion_protection` attribute.** Your guards are
`prevent_destroy` in code and **resource locks** out of band (below). Plan
carefully — there is usually no server-side "are you sure" for Terraform to
trip over.

## 2.1 Data-loss resources and their forcing attributes

### `azurerm_mssql_server` + `azurerm_mssql_database` — 🔴

Model these as two resources. The database references the server via
`server_id`; it does **not** carry its own `location`/`resource_group_name`.

`azurerm_mssql_server`:

| Attribute               | Effect on change        | Sev |
| ----------------------- | ----------------------- | --- |
| `name`                  | **forces replacement**  | 🔴  |
| `resource_group_name`   | **forces replacement**  | 🔴  |
| `location`              | **forces replacement**  | 🔴  |

`azurerm_mssql_database`:

| Attribute               | Effect on change        | Sev |
| ----------------------- | ----------------------- | --- |
| `name`                  | **forces replacement**  | 🔴  |
| `server_id`             | **forces replacement**  | 🔴  |
| `collation`             | **forces replacement**  | 🔴  |
| `create_mode`           | **forces replacement**  | 🔴  |
| `sku_name` (scale tier) | in-place                | 🟢  |
| `max_size_gb`           | in-place                | 🟢  |

See
[`azurerm_mssql_database`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/mssql_database).

### `azurerm_postgresql_flexible_server` — 🔴

| Attribute                     | Effect on change        | Sev |
| ----------------------------- | ----------------------- | --- |
| `name`                        | **forces replacement**  | 🔴  |
| `resource_group_name`         | **forces replacement**  | 🔴  |
| `location`                    | **forces replacement**  | 🔴  |
| `create_mode`                 | **forces replacement**  | 🔴  |
| `administrator_login`         | **forces replacement**  | 🔴  |
| `sku_name`                    | in-place (scale)         | 🟢  |
| `storage_mb`                  | in-place (grow only)     | 🟢  |
| `zone`                        | in-place                | 🟢  |

See
[`azurerm_postgresql_flexible_server`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/postgresql_flexible_server).

### `azurerm_managed_disk` — 🔴 persistent data

The Azure counterpart to `google_compute_disk`. Note which attributes are
**in-place** — they are a common source of relief in a scary-looking plan.

| Attribute                   | Effect on change        | Sev |
| --------------------------- | ----------------------- | --- |
| `name`                      | **forces replacement**  | 🔴  |
| `resource_group_name`       | **forces replacement**  | 🔴  |
| `location`                  | **forces replacement**  | 🔴  |
| `zone`                      | **forces replacement**  | 🔴  |
| `create_option`             | **forces replacement**  | 🔴  |
| `storage_account_type`      | in-place                | 🟢  |
| `disk_size_gb`              | in-place (grow only)     | 🟢  |

`storage_account_type` (e.g. `Standard_LRS → Premium_LRS`) is **not**
`ForceNew` — Azure changes the disk performance tier in place. `disk_size_gb`
grows in place. See
[`azurerm_managed_disk`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/managed_disk).

### `azurerm_linux_virtual_machine` / `azurerm_windows_virtual_machine` — 🟡/🔴

Prefer these over the deprecated `azurerm_virtual_machine`. The VM is
usually stateless; the risk is the **OS disk** (destroyed with the VM) and
anything on ephemeral/inline storage.

| Attribute                       | Effect on change            | Sev |
| ------------------------------- | --------------------------- | --- |
| `name`                          | **forces replacement**      | 🔴  |
| `resource_group_name`           | **forces replacement**      | 🔴  |
| `location`                      | **forces replacement**      | 🔴  |
| `os_disk.storage_account_type`  | **forces replacement**      | 🔴  |
| `os_disk.caching`               | **forces replacement**      | 🔴  |
| `source_image_id` / `_reference`| **forces replacement**      | 🔴  |
| `admin_username`                | **forces replacement**      | 🔴  |
| `zone`                          | **forces replacement**      | 🔴  |
| `size` (VM SKU)                 | in-place (resize/restart)   | 🟡  |
| `network_interface_ids`         | in-place                    | 🟢  |

`size` is an in-place resize (brief reboot), **not** `ForceNew`. Keep data
on a separately-managed `azurerm_managed_disk` so VM replacement never
touches it. See
[`azurerm_linux_virtual_machine`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/linux_virtual_machine).

### `azurerm_storage_account` — 🔴 with a `ForceNew` tier

| Attribute                   | Effect on change        | Sev |
| --------------------------- | ----------------------- | --- |
| `name`                      | **forces replacement**  | 🔴  |
| `resource_group_name`       | **forces replacement**  | 🔴  |
| `location`                  | **forces replacement**  | 🔴  |
| `account_tier`              | **forces replacement**  | 🔴  |
| `account_kind`              | **forces replacement**  | 🔴  |
| `account_replication_type`  | in-place                | 🟢  |

The trap here is **`account_tier`** (`Standard`/`Premium`): it is
`ForceNew`. "Just bumping the tier" destroys the account and every blob,
file, queue, and table in it. `account_replication_type` (e.g.
`LRS → GRS`) is in-place. Storage account names are **globally unique**;
deleted names may not be immediately reusable. See
[`azurerm_storage_account`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account).

### `azurerm_kubernetes_cluster` node pools — 🔴 (drains running workloads)

Two shapes to know:

**`default_node_pool` (inline).** Several sub-attributes force replacement
of the **entire cluster** — control plane and all pools:

| `default_node_pool` attribute | Effect on change              | Sev |
| ----------------------------- | ----------------------------- | --- |
| `name`                        | **forces cluster replacement**| 🔴  |
| `vnet_subnet_id`              | **forces cluster replacement**| 🔴  |
| `os_disk_size_gb`             | **forces cluster replacement**| 🔴  |
| `os_disk_type`                | **forces cluster replacement**| 🔴  |
| `max_pods`                    | **forces cluster replacement**| 🔴  |
| `zones`                       | **forces cluster replacement**| 🔴  |
| `vm_size`                     | replacement unless rotated\*  | 🔴  |
| `node_count`                  | in-place (scale)               | 🟢  |

\* `vm_size` historically forced replacement. Recent `azurerm` supports
resizing the default node pool in place by setting
`temporary_name_for_rotation`, which cycles nodes onto a temp pool instead
of recreating the cluster. Without it, changing `vm_size` still recreates.

Also cluster-level `ForceNew`: `name`, `location`, `resource_group_name`,
`dns_prefix`, and most of `network_profile`.

**`azurerm_kubernetes_cluster_node_pool` (separate resource).** Changing a
forcing attribute recreates **that pool only** — still a 🔴 event because
its nodes are cordoned/drained and the workloads on them are rescheduled:

| Attribute        | Effect on change      | Sev |
| ---------------- | --------------------- | --- |
| `name`           | **forces replacement**| 🔴  |
| `vm_size`        | **forces replacement**| 🔴  |
| `os_disk_size_gb`| **forces replacement**| 🔴  |
| `vnet_subnet_id` | **forces replacement**| 🔴  |
| `zones`          | **forces replacement**| 🔴  |
| `max_pods`       | **forces replacement**| 🔴  |
| `node_count`     | in-place (scale)       | 🟢  |

See
[`azurerm_kubernetes_cluster`](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster).

## 2.2 Azure guards

- **`lifecycle { prevent_destroy = true }`.** Your primary in-code guard,
  same semantics as on GCP: plan-time hard error on any destroy. Because
  most `azurerm` resources lack a `deletion_protection` attribute, this is
  often the *only* thing in the Terraform config standing between a
  forcing-attribute edit and data loss. Put it on every stateful resource.
- **Resource locks (out of band).** Azure Management Locks
  (`CanNotDelete` or `ReadOnly`) are enforced by Azure itself, independent
  of Terraform. A `CanNotDelete` lock on a database or storage account
  makes the destroy half of a replacement **fail at the API**, converting
  silent data loss into a loud, safe error. Manage them with
  `azurerm_management_lock`, or apply them by policy at the
  resource-group/subscription scope so they survive regardless of what any
  single Terraform run tries to do.
- A few newer resources do expose deletion-protection-style flags (e.g.
  storage account / key-vault soft-delete, purge protection). These are
  worth enabling but are not universal — do not assume a resource has one.

---

## Reading a plan (worked example)

A `terraform plan` for a routine-looking "rename the prod database" change:

```text
Terraform will perform the following actions:

  # google_sql_database_instance.main must be replaced
-/+ resource "google_sql_database_instance" "main" {
      ~ name                = "prod-pg" -> "prod-pg-v2" # forces replacement
      ~ connection_name     = "acme:us-central1:prod-pg" -> (known after apply)
      ~ first_ip_address    = "34.72.10.4" -> (known after apply)
      ~ self_link           = "https://.../prod-pg" -> (known after apply)
        region              = "us-central1"
        # (18 unchanged attributes hidden)
    }

Plan: 1 to add, 0 to change, 1 to destroy.
```

How to read it, top to bottom:

1. **`must be replaced`** and the **`-/+`** prefix — this is a
   destroy-then-create, not an update. The first character `-` is the
   destroy.
2. **`# forces replacement`** points at the exact culprit: `name`. Nothing
   else here required replacement; the rename dragged the whole instance
   with it.
3. **`Plan: ... 1 to destroy`** — the summary line confirms a real
   destruction. On a stateful resource, treat any non-zero "to destroy" as
   🔴 until you have accounted for every destroyed object.
4. The `(known after apply)` churn on `connection_name`, IPs, and
   `self_link` is a tell that downstream resources (apps, DNS, firewall
   rules) referencing this instance will also change — the blast radius is
   bigger than one resource.

**What to do:**

- If the rename is *not* actually needed, revert the attribute. Most
  "forces replacement" plans are an accident (a variable default changed, a
  module input drifted).
- If it *is* needed, do it out of band and never let one `apply` both
  destroy and recreate a database: snapshot/export → create the new instance
  → migrate/cutover → retire the old one. See
  `examples/05-gcp-cloudsql/safe.tf`.
- Confirm the guard held: with `deletion_protection = true` and
  `prevent_destroy = true` in place, this plan would have **errored before
  the summary**, which is the outcome you want.

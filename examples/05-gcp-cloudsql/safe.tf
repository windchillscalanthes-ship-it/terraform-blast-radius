# ============================================================================
# 05-gcp-cloudsql / safe.tf
# ----------------------------------------------------------------------------
# The same production Cloud SQL instance, hardened so that an accidental
# forcing-attribute edit CANNOT destroy it, plus the correct out-of-band
# procedure for when a forcing attribute (name / region) genuinely must
# change.
#
# Terraform and OpenTofu behave identically here.
# ============================================================================

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = "acme-prod"
  region  = "us-central1"
}

resource "google_sql_database_instance" "main" {
  name             = "prod-pg"
  region           = "us-central1"
  database_version = "POSTGRES_15"

  # ----------------------------------------------------------------------
  # 🟢 GUARD 1 — Terraform-level deletion protection (server-aware).
  #
  # `deletion_protection = true` makes Terraform REFUSE to run any destroy of
  # this resource, including the destroy half of a replacement. If someone
  # edits `name`, the plan ERRORS before touching anything:
  #
  #   Error: Instance ... has deletion protection enabled. Set
  #   deletion_protection = false and apply before attempting deletion.
  #
  # To ever replace it you must first apply a change flipping this to false —
  # a deliberate, reviewable, separate step. That friction is the feature.
  # ----------------------------------------------------------------------
  deletion_protection = true

  settings {
    tier      = "db-custom-2-7680"
    disk_size = 100

    # ------------------------------------------------------------------
    # 🟢 GUARD 2 — server-side deletion protection, enforced by GCP itself
    # (not Terraform). Distinct flag from the resource-level attribute
    # above; enable both. This one also blocks deletion via the console,
    # gcloud, or API — anything outside Terraform.
    # ------------------------------------------------------------------
    deletion_protection_enabled = true
  }

  # ----------------------------------------------------------------------
  # 🟢 GUARD 3 — the hard stop. `prevent_destroy = true` makes Terraform
  # hard-error at PLAN time on any plan that would destroy this instance,
  # regardless of provider state. Unlike deletion_protection, disabling it
  # requires a code edit (not just an apply), so it is the strongest signal
  # that this resource must never be replaced in place by a config change.
  # ----------------------------------------------------------------------
  lifecycle {
    prevent_destroy = true
  }
}

# ============================================================================
# WHEN A FORCING ATTRIBUTE MUST GENUINELY CHANGE (e.g. new region, new name)
# ----------------------------------------------------------------------------
# Do NOT let a single `apply` both destroy and recreate a database. Run an
# out-of-band migration where the old instance stays alive until the new one
# is verified:
#
#   1. Take an on-demand backup / export:
#        gcloud sql export sql prod-pg gs://acme-backups/prod-pg-$(date +%s).sql \
#          --database=app
#      (or create an on-demand backup and, for cross-region, a cross-region
#      replica you can promote).
#
#   2. Create the NEW instance as a SEPARATE resource (new name/region) —
#      add a `google_sql_database_instance.main_v2` block; do not mutate the
#      existing one. Import the data (`gcloud sql import sql ...`) or promote
#      the replica.
#
#   3. Cut over: point apps at the new `connection_name` / IP, verify
#      traffic and data, keep the old instance running as rollback.
#
#   4. Only after verification, retire the old instance — and remember the
#      name-reuse cooldown: the old name is reserved for a period
#      (historically up to ~a week) before it can be used again, which is
#      exactly why step 2 uses a NEW name rather than reusing the old one.
#
# RESULT: zero-downtime, zero-data-loss migration. The database serving
# traffic is never destroyed by Terraform as a side effect of an attribute
# edit; every destroy is explicit and happens only after the replacement is
# proven healthy.
# ============================================================================

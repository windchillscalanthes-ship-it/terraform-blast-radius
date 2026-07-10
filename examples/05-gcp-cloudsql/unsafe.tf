# ============================================================================
# 05-gcp-cloudsql / unsafe.tf
# ----------------------------------------------------------------------------
# A production Cloud SQL (PostgreSQL) instance. This file demonstrates a
# change that LOOKS like a rename but DESTROYS the database and every byte in
# it. Compare with safe.tf in the same directory.
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
  # ----------------------------------------------------------------------
  # 🔴 THE FORCING ATTRIBUTE.
  #
  # `name` is ForceNew. Cloud SQL cannot rename an instance in place, so the
  # only way Terraform can realize a new name is:
  #     destroy the old instance  ->  create a new one
  #
  # There is NO snapshot in that sequence. When the destroy runs, the
  # instance, all of its databases and tables, AND its automated backups are
  # deleted. `region` has exactly the same effect and the same consequence.
  #
  # Suppose someone edits this from "prod-pg" to "prod-pg-v2":
  #
  #   # google_sql_database_instance.main must be replaced
  #   -/+ resource "google_sql_database_instance" "main" {
  #         ~ name             = "prod-pg" -> "prod-pg-v2" # forces replacement
  #         ~ connection_name  = "..." -> (known after apply)
  #         ~ first_ip_address = "34.72.10.4" -> (known after apply)
  #       }
  #   Plan: 1 to add, 0 to change, 1 to destroy.
  #
  # `-/+` + `# forces replacement` + `1 to destroy` on a database = DATA LOSS.
  #
  # WORSE, GCP-specific footgun: after a Cloud SQL instance is deleted, its
  # name is RESERVED for a cooldown period (historically up to ~a week). So
  # the "create" half of this replacement can FAIL because "prod-pg" (or a
  # recycled name) is still reserved — leaving you with a destroyed database
  # and no replacement. You do not even get the broken-but-running outcome.
  # ----------------------------------------------------------------------
  name             = "prod-pg"
  region           = "us-central1"
  database_version = "POSTGRES_15"

  # ----------------------------------------------------------------------
  # 🔴 GUARD DISABLED. `deletion_protection` defaults to `true`; this config
  # explicitly turns it OFF, so Terraform will happily execute the destroy
  # half of the replacement with no server-side objection. Never do this on
  # a stateful instance. (There is also no `prevent_destroy` here — nothing
  # at all stops the plan above from applying.)
  # ----------------------------------------------------------------------
  deletion_protection = false

  settings {
    # These ARE safe to change: tier (machine size) and disk size are applied
    # in place. They are NOT what makes this file dangerous.
    tier      = "db-custom-2-7680"
    disk_size = 100
  }
}

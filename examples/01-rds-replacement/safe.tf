###############################################################################
# SAFE — same intent (an encrypted production database), no data loss.
#
# Two independent ideas:
#   1. Guard the existing instance so an accidental `-/+` can never apply.
#   2. Achieve encryption the ONLY way RDS supports it: out of band, via a
#      snapshot -> encrypted-copy -> restore migration, then cut over.
#
# `storage_encrypted` is ForceNew, so you cannot toggle it in place. Do NOT
# just edit the attribute — do the migration below and let Terraform manage
# the already-encrypted result.
###############################################################################

resource "aws_db_instance" "main" {
  identifier     = "app-prod"
  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.t3.medium"

  allocated_storage = 100
  db_name           = "app"
  username          = "appuser"
  password          = var.db_password

  db_subnet_group_name = aws_db_subnet_group.main.name

  # After the migration below, the instance Terraform manages is already
  # encrypted, so this line matches reality and plans clean (no -/+).
  storage_encrypted = true

  # -- Guards -----------------------------------------------------------------
  deletion_protection = true  # AWS itself refuses to delete this instance
  skip_final_snapshot = false # a destroy would take a final snapshot first
  final_snapshot_identifier = "app-prod-final"

  lifecycle {
    prevent_destroy = true # Terraform errors at PLAN time on any -/+ or destroy
  }
}

###############################################################################
# The out-of-band migration path (run once, when encryption must change):
#
#   1. Snapshot the source:
#        aws rds create-db-snapshot \
#          --db-instance-identifier app-prod \
#          --db-snapshot-identifier app-prod-preenc
#
#   2. Copy the snapshot WITH encryption (this is where encryption is applied):
#        aws rds copy-db-snapshot \
#          --source-db-snapshot-identifier app-prod-preenc \
#          --target-db-snapshot-identifier app-prod-enc \
#          --kms-key-id <kms-key-arn>
#
#   3. Restore the encrypted snapshot into a new instance:
#        aws rds restore-db-instance-from-db-snapshot \
#          --db-instance-identifier app-prod-new \
#          --db-snapshot-identifier app-prod-enc
#
#   4. Cut application traffic over to app-prod-new (verify, then update the
#      connection string / route). Keep the old instance until confident.
#
#   5. Reconcile Terraform state to the new, encrypted instance
#      (terraform state rm + import, or a rename) so `terraform plan` reports:
#
#        No changes. Your infrastructure matches the configuration.
#        Plan: 0 to add, 0 to change, 0 to destroy.
#
# Net result: encryption satisfied, prevent_destroy blocks the dangerous
# path, and 0 resources destroyed.
###############################################################################

variable "db_password" {
  type      = string
  sensitive = true
}

resource "aws_db_subnet_group" "main" {
  name       = "app-prod"
  subnet_ids = var.private_subnet_ids
}

variable "private_subnet_ids" {
  type = list(string)
}

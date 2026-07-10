###############################################################################
# UNSAFE — this plan DESTROYS a production database and loses all data.
#
# Scenario: someone flips `storage_encrypted` from false to true to satisfy a
# compliance ticket, assuming it is an in-place change. It is not. On
# aws_db_instance, `storage_encrypted` is create-time only (ForceNew) — RDS
# cannot encrypt an existing volume in place.
#
# Docs: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_instance#storage_encrypted
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

  # >>> The one-line "fix" that detonates the database. <<<
  # Was: storage_encrypted = false
  storage_encrypted = true

  # These make the blast fatal instead of merely dangerous:
  skip_final_snapshot = true # no final snapshot -> nothing to restore from
  # deletion_protection defaults to false -> AWS will happily delete it
  # no lifecycle { prevent_destroy } -> Terraform will happily plan it
}

###############################################################################
# terraform plan output (abridged):
#
#   # aws_db_instance.main must be replaced
#   -/+ resource "aws_db_instance" "main" {
#         ~ id                = "app-prod" -> (known after apply)
#         ~ storage_encrypted = false -> true # forces replacement
#           # (34 unchanged attributes hidden)
#       }
#
#   Plan: 1 to add, 0 to change, 1 to destroy.
#
# Consequence:
#   -/+  = destroy "app-prod" then create a new empty encrypted instance.
#   skip_final_snapshot = true -> NO snapshot is taken on the way out.
#   Result: every row in the database is permanently gone. Unrecoverable.
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

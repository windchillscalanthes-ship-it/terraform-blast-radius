# ============================================================================
# SAFE: the SAME rename, but recorded with a `moved` block.
# ----------------------------------------------------------------------------
# The resource is declared at its new address `aws_instance.app`, exactly as
# in unsafe.tf. The difference is the `moved` block below, which tells
# Terraform: "the object previously tracked at `aws_instance.web` is the same
# object now declared at `aws_instance.app`."
#
# Terraform responds by updating STATE ONLY — it rewrites the address in the
# state file and makes NO change to real infrastructure. `terraform plan` now
# reports the move and a clean summary:
#
#     # aws_instance.web has moved to aws_instance.app
#
#     Plan: 0 to add, 0 to change, 0 to destroy.
#
# No destroy, no recreate, same instance ID, same IP, zero downtime. ✅
#
# `moved` blocks are available in Terraform 1.1+ (and OpenTofu). Keep this
# block for at least one apply across every workspace/CI environment so each
# one migrates its state; once all state is moved you may delete it.
#
# Prefer this over the imperative `terraform state mv aws_instance.web \
# aws_instance.app`: the block is declarative, reviewed in the PR, visible in
# `plan`, and reproducible everywhere — the `state mv` command runs once on
# one machine, out of band, with no review trail.
# ============================================================================

resource "aws_instance" "app" {
  ami           = "ami-0abcd1234abcd1234"
  instance_type = "t3.micro"

  tags = {
    Name = "app-server"
  }
}

moved {
  from = aws_instance.web
  to   = aws_instance.app
}

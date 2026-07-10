# =============================================================================
# UNSAFE — a `count`-based fleet keyed by list POSITION.
#
# `count` addresses each instance by its index: aws_instance.web[0], [1], [2]...
# Terraform tracks state by that index, so the index IS the identity. Remove or
# insert an element anywhere but the END of the list and every later index
# SHIFTS — Terraform then plans to destroy and recreate every shifted resource.
#
# This is the classic "I deleted one tenant and Terraform recreated half the
# fleet" incident (catalog pattern #5). Applies to Terraform and OpenTofu alike.
# These files are illustrative and are never meant to be applied.
# =============================================================================

variable "tenants" {
  # Today: 4 tenants. web[0]=alpha, web[1]=beta, web[2]=gamma, web[3]=delta
  default = ["alpha", "beta", "gamma", "delta"]
}

resource "aws_instance" "web" {
  count         = length(var.tenants)
  ami           = "ami-0abc123"
  instance_type = "t3.small"

  tags = {
    Name   = "web-${var.tenants[count.index]}"
    Tenant = var.tenants[count.index]
  }
}

# -----------------------------------------------------------------------------
# THE BOMB: remove "beta" from the middle of the list —
#   default = ["alpha", "gamma", "delta"]
#
# The indices shift:
#   web[1]  beta  -> gamma   # forces replacement (tenant changed)
#   web[2]  gamma -> delta   # forces replacement
#   web[3]  delta -> (gone)  # destroyed
#
# Plan: 0 to add, 0 to change, 3 to destroy... actually:
#   -/+ aws_instance.web[1]   # was beta, now gamma
#   -/+ aws_instance.web[2]   # was gamma, now delta
#   -   aws_instance.web[3]   # delta removed
#
# You wanted to remove ONE tenant. Terraform destroys and recreates THREE
# instances — every one whose position moved. On a real fleet that's a
# rolling outage caused by a one-line list edit.
# -----------------------------------------------------------------------------

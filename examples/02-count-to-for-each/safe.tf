# =============================================================================
# SAFE — the same fleet keyed by a STABLE identity with `for_each`.
#
# `for_each` addresses each instance by a map/set KEY, not a position:
#   aws_instance.web["alpha"], aws_instance.web["beta"], ...
# The key is the identity, so removing one element touches only that one
# resource. Order no longer matters.
# =============================================================================

variable "tenants" {
  default = ["alpha", "beta", "gamma", "delta"]
}

resource "aws_instance" "web" {
  for_each      = toset(var.tenants)   # web["alpha"], web["beta"], web["gamma"], web["delta"]
  ami           = "ami-0abc123"
  instance_type = "t3.small"

  tags = {
    Name   = "web-${each.key}"
    Tenant = each.key
  }
}

# -----------------------------------------------------------------------------
# THE SAME EDIT, now safe: remove "beta" —
#   default = ["alpha", "gamma", "delta"]
#
# Only the "beta" key disappears; the others keep their identity:
#   -  aws_instance.web["beta"]        # destroyed (the one you removed)
#      aws_instance.web["alpha"]       # untouched
#      aws_instance.web["gamma"]       # untouched
#      aws_instance.web["delta"]       # untouched
#
# Plan: 0 to add, 0 to change, 1 to destroy.
# You removed one tenant; Terraform removed exactly one instance. No rolling
# outage, no surprise recreation.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# MIGRATING an existing `count` fleet to `for_each` without churn:
# the addresses change (web[0] -> web["alpha"]), which by itself would look like
# destroy+recreate. Map each index to its key with `moved` blocks so it's a pure
# state move (0 to destroy):
#
#   moved {
#     from = aws_instance.web[0]
#     to   = aws_instance.web["alpha"]
#   }
#   moved {
#     from = aws_instance.web[1]
#     to   = aws_instance.web["beta"]
#   }
#   # ...one per existing element. Apply this move first, THEN edit the list.
# -----------------------------------------------------------------------------

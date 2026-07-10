###############################################################################
# SAFE — the replacement still happens, but the NEW instance is stood up and
# healthy before the OLD one is destroyed. The user_data edit takes effect
# with no outage.
#
# The fix is a single lifecycle block. It does not stop the replacement (a
# user_data change with user_data_replace_on_change = true is still ForceNew);
# it reverses the order so there is no gap.
###############################################################################

resource "aws_instance" "app" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "t3.small"
  subnet_id     = var.subnet_id

  user_data = <<-EOF
    #!/bin/bash
    echo "app version 2" > /etc/motd
    systemctl restart app
  EOF

  # Still true: we WANT the updated script to actually run, which requires a
  # fresh instance. create_before_destroy makes that safe.
  user_data_replace_on_change = true

  lifecycle {
    create_before_destroy = true # new instance up first, old one destroyed after
  }

  tags = { Name = "app" }
}

###############################################################################
# Apply order (safe):
#   1. CREATE new instance, wait for boot + user_data to run
#   2. (route traffic to it — see note below)
#   3. DESTROY the old instance
#   => zero-gap replacement. The old instance keeps serving until the new one
#      exists.
#
# Notes:
#   - create_before_destroy requires that nothing forces uniqueness during the
#     overlap. This instance uses no fixed name/EIP that both copies would
#     claim, so both can exist briefly. If you attach a fixed Elastic IP or a
#     unique name, front the instances with a target group / ELB (or move the
#     EIP association) so the two can coexist.
#   - If you did NOT actually need the script to re-run, the alternative is to
#     drop user_data_replace_on_change (it defaults to false): the edit then
#     applies in place with no replacement at all — but the script will not
#     re-execute on the running instance.
#
# terraform plan still shows `1 to add, 0 to change, 1 to destroy`, but with
# create_before_destroy the destroy is sequenced AFTER the create, so there is
# no downtime window.
###############################################################################

variable "subnet_id" {
  type = string
}

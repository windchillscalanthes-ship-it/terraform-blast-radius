###############################################################################
# UNSAFE — editing user_data destroys the instance BEFORE the new one exists,
# so the app is down for the whole launch + boot window.
#
# `user_data_replace_on_change = true` makes any user_data edit ForceNew. This
# is deliberately set here (it is the only way to make an updated bootstrap
# script actually run), but WITHOUT create_before_destroy the default order is
# destroy-old THEN create-new -> a hard outage.
#
# Docs: https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance#user_data_replace_on_change
###############################################################################

resource "aws_instance" "app" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "t3.small"
  subnet_id     = var.subnet_id

  # Any change to this script now forces a full replacement.
  user_data = <<-EOF
    #!/bin/bash
    echo "app version 1" > /etc/motd
    systemctl restart app
  EOF

  user_data_replace_on_change = true # edit user_data -> -/+ (forces replacement)

  # No lifecycle block -> Terraform uses the default destroy-before-create order.

  tags = { Name = "app" }
}

###############################################################################
# terraform plan output after editing the script (abridged):
#
#   # aws_instance.app must be replaced
#   -/+ resource "aws_instance" "app" {
#         ~ id        = "i-0123456789abcdef0" -> (known after apply)
#         ~ user_data = "6f1b..." -> "a83c..." # forces replacement
#           # (30 unchanged attributes hidden)
#       }
#
#   Plan: 1 to add, 0 to change, 1 to destroy.
#
# Apply order (default, unsafe):
#   1. DESTROY i-0123... (app is now OFFLINE)
#   2. CREATE new instance
#   3. wait for boot + user_data to run
#   => downtime = teardown + launch + full boot. No data loss (stateless),
#      but a user-visible outage on every script change.
###############################################################################

variable "subnet_id" {
  type = string
}

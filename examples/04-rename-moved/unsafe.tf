# ============================================================================
# UNSAFE: a resource was RENAMED with no `moved` block.
# ----------------------------------------------------------------------------
# History: this resource used to be declared as `aws_instance.web`. Someone
# renamed the address to `aws_instance.app` (a pure code refactor — the AMI,
# type, and everything else are identical to before).
#
# Terraform does NOT track resources by variable name intent; it tracks them
# by ADDRESS (`type.name`). Prior state still holds the object under the old
# address `aws_instance.web`. The new config declares `aws_instance.app`.
# Terraform therefore reads this as:
#
#     - one resource disappeared  (aws_instance.web)
#     + one new resource appeared (aws_instance.app)
#
# So `terraform plan` will report something like:
#
#     # aws_instance.web  will be DESTROYED
#     - resource "aws_instance" "web"  { ... }
#     # aws_instance.app  will be CREATED
#     + resource "aws_instance" "app"  { ... }
#
#     Plan: 1 to add, 0 to change, 1 to destroy.
#
# That is a full DESTROY + RECREATE of a running instance for what was only
# meant to be a rename: downtime, a new instance ID, a new private IP, and
# loss of any instance-local state / ephemeral disk. 🔴
# ============================================================================

resource "aws_instance" "app" {
  ami           = "ami-0abcd1234abcd1234"
  instance_type = "t3.micro"

  tags = {
    Name = "app-server"
  }
}

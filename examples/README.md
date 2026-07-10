# Examples

Each folder is a realistic Terraform change expressed two ways:

- `unsafe.tf` — the naive version that plans a destroy-and-recreate (or an
  orphan), with inline comments showing the plan action (`-/+`,
  `# forces replacement`) and the consequence.
- `safe.tf` — the rewrite that avoids the destruction, with comments explaining
  the lifecycle rule, `moved` block, `for_each`, or migration path and the
  resulting plan (e.g. "0 to destroy").

These double as a test corpus: point the skill at an `unsafe.tf` and it should
produce something equivalent to the matching `safe.tf`. **The `.tf` files are
illustrative and are never meant to be applied.**

| Example | Resource | Core risk |
|---------|----------|-----------|
| [`01-rds-replacement`](01-rds-replacement/) | `aws_db_instance` | A forced replacement destroys the database — **data loss** |
| [`02-count-to-for-each`](02-count-to-for-each/) | any counted resource | Removing a middle element shifts indices → mass recreation |
| [`03-ec2-user-data`](03-ec2-user-data/) | `aws_instance` | `user_data` change forces replacement → downtime |
| [`04-rename-moved`](04-rename-moved/) | any resource | Renaming the address destroys + recreates without a `moved` block |
| [`05-gcp-cloudsql`](05-gcp-cloudsql/) | `google_sql_database_instance` | A forced replacement destroys the Cloud SQL instance |

Coverage for more providers (Kubernetes, DigitalOcean, Cloudflare) is welcome —
see [CONTRIBUTING.md](../CONTRIBUTING.md).

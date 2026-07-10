# Roadmap

Where `terraform-blast-radius` is headed. This is a direction, not a contract —
timing depends on contributions and feedback. Have an idea? Open a
[feature request](.github/ISSUE_TEMPLATE/feature_request.yml) or a
[discussion](https://github.com/windchillscalanthes-ship-it/terraform-blast-radius/discussions).

## ✅ v0.1 — Foundation (shipped)

- Review workflow + a 12-item, provider-aware risk catalog in `SKILL.md`
- Reference guides: AWS, Google Cloud + Azure, lifecycle/state operations, and
  provider-agnostic patterns
- Five worked before/after examples (RDS data loss, count→for_each, EC2 user_data,
  rename→moved, GCP Cloud SQL)
- Community scaffolding: contributing guide, code of conduct, issue forms, CI validation

## 🔜 v0.2 — Broader coverage

- [ ] **Kubernetes** provider (`kubernetes_*`) and **Helm** release replacement
- [ ] **DigitalOcean** and **Cloudflare** provider notes
- [ ] More AWS depth: `aws_msk_cluster`, `aws_elasticsearch_domain`,
      `aws_eks_node_group`, `aws_ecs_service` deployment vs replacement
- [ ] More worked examples: security-group blast radius, launch-template + ASG
      rollout, provider-upgrade spurious replacement

## 🧭 v0.3 — Fits into your workflow

- [ ] A **CI recipe**: run the skill against `terraform show -json tfplan` and post
      a blast-radius review as a PR comment
- [ ] A companion **GitHub Action** wrapping that recipe
- [ ] Guidance for reading machine-readable plans (`terraform show -json`) so the
      review is exact rather than inferred from HCL
- [ ] A "guard your crown jewels" starter snippet (prevent_destroy + deletion
      protection for common data stores)

## 🔮 Later / ideas

- [ ] Pulumi and CloudFormation blast-radius notes (same concepts, different tools)
- [ ] A curated set of "war story" case studies (a real destroyed resource → the
      rule that prevents it)
- [ ] Notes on complementary tools (`terraform plan` policy checks, OPA/Sentinel,
      `driftctl`, `infracost` for the cost side)

## Non-goals

- Connecting to your cloud accounts or reading your state — the skill reasons from
  the plan/HCL and the context you give it.
- Replacing policy-as-code (OPA/Sentinel) — run those in CI *too*.
- Being a substitute for a real staging environment and a tested backup/restore.

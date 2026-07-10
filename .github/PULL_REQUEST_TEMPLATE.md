## What does this change?

<!-- A short description. One logical change per PR, please. -->

## Type

- [ ] Fix incorrect/unsafe advice
- [ ] Add a new destructive-change pattern
- [ ] Add provider coverage (DigitalOcean, Kubernetes, …)
- [ ] Add/improve provider reference notes
- [ ] Add a worked example
- [ ] Docs / typo

## For pattern changes, confirm:

- [ ] Names the **attribute that forces replacement** (or the operation that destroys)
- [ ] States whether the resource is **stateful (data loss)** or **stateless (downtime)**
- [ ] Includes a **safe rewrite** (lifecycle rule / moved block / for_each / migration steps)
- [ ] **Cites a source** (link to provider registry docs): <!-- link -->

## Checklist

- [ ] Kept `SKILL.md` lean; pushed provider depth into `reference/`
- [ ] Updated `CHANGELOG.md` under `## [Unreleased]`
- [ ] Verified locally by asking Claude to review the relevant `unsafe.tf` example

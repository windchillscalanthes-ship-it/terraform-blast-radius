# Security Policy

`terraform-blast-radius` is a set of Markdown instructions and reference material
for a Claude Agent Skill. It ships **no executable code** (the `.tf` files under
`examples/` are illustrative and are never meant to be applied), has no
dependencies, and does not connect to your cloud accounts, state, or network. The
realistic risk surface is therefore small — but two things are worth reporting.

## Reporting incorrect or unsafe advice

The most important issue for this project is **advice that could cause an outage
or data loss** if followed — for example, calling a replacement "safe" when the
resource actually holds data, or naming the wrong attribute as the one that forces
replacement. If the skill recommends something unsafe, please report it:

- Open a [bug report](.github/ISSUE_TEMPLATE/bug_report.yml) (preferred — it
  helps everyone), or
- If you'd rather report privately, use GitHub's **Report a vulnerability**
  button under this repository's **Security** tab.

Please include the resource and change, the provider and version, what the skill
said, and the correct behavior with a link to the provider docs. We treat
incorrect destroy/replacement guidance as a high-priority fix.

## Reporting a genuine vulnerability

If you find an actual security issue (for example, content crafted to trigger
unintended tool use in a host application), please report it privately via the
**Security → Report a vulnerability** flow rather than a public issue. We'll
acknowledge within a reasonable time and coordinate a fix and disclosure.

## Supported versions

This project is pre-1.0; fixes land on the `main` branch and the latest release.
Please verify against the newest version before reporting.

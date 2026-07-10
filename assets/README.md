# Assets & demo strategy

## What ships today

- **`hero.svg`** — the README hero. A hand-built terminal mockup that renders
  instantly on GitHub (no recording, no external hosting) and tells the whole
  problem→fix story in one glance: a `terraform plan` showing a database being
  destroyed and recreated, and the guarded rewrite. This is deliberately the
  *first* thing a visitor sees, because the value has to land in under 10 seconds.
- **`social-preview.svg`** — the editable source for the social card. See the note
  below on exporting the PNG that GitHub wants.

That means the repo looks complete right now. Everything below is an **upgrade
path**, not a blocker.

## The upgrade: a real demo GIF

A short screen capture of the skill working is the single biggest driver of stars
once the repo starts getting traffic. When you're ready, record it and either swap
the hero `<img src="assets/hero.svg">` for `assets/demo.gif`, or add it just below
the hero.

### Demo script (aim for 15–25 seconds)

The demo must show a **real, scary problem getting caught fast**. Keep it tight:

1. **(2s)** A `terraform plan` output on screen, calm. A `-/+` block is visible.
2. **(3s)** Type: *"Is this plan safe to apply?"*
3. **(6s)** The review renders: 🔴 **DATA LOSS** — `aws_db_instance.main` will be
   **destroyed and recreated**; `# forces replacement: storage_encrypted`.
4. **(8s)** The **fix** appears — `prevent_destroy`, `deletion_protection`, and the
   snapshot→restore migration path. **End on this frame.** The payoff is the save.

Rules that make demos convert:
- Show a *real* plan and a *real* fix — the honesty is the selling point.
- End on the safe path, not the scare.
- No dead air; cut typing pauses.
- Redact real account ids, ARNs, and hostnames.

### Tooling

- **Windows:** [ScreenToGif](https://www.screentogif.com/) (free, excellent)
- **macOS:** [Kap](https://getkap.co/)
- **Linux:** [Peek](https://github.com/phw/peek)
- **Terminal-only:** [asciinema](https://asciinema.org/) → export to GIF/SVG with
  [`agg`](https://github.com/asciinema/agg)

Keep it under ~3–5 MB so it loads fast. Use a theme with good contrast in both
GitHub light and dark mode.

## Social preview image

GitHub lets you set a **social preview** (Settings → General → Social preview) —
the card shown when the repo is linked on X, Slack, LinkedIn, etc. It wants a
**1280×640 PNG**.

The editable source is included here as `social-preview.svg`. Export it to
`social-preview.png` at 1280×640 before uploading — for example:

```bash
# any one of these:
rsvg-convert -w 1280 -h 640 social-preview.svg -o social-preview.png
inkscape social-preview.svg --export-width=1280 --export-filename=social-preview.png
# or open it in the browser and screenshot at 1280×640
```

Then upload the PNG at **Settings → General → Social preview**.

# sreeram-repo-crew

A small AI crew that keeps a GitHub project fresh, with every decision made from a phone.
Built on GitHub Actions and [claude-code-action](https://github.com/anthropics/claude-code-action).
Portable: onboarding another project takes a config file, five thin workflow files and one command.

```
 Monday 07:00 ─► SCOUT ─► weekly issue "Proposals 2026-W40"  ── push to your phone (GitHub mobile)
                                   │
        you reply in plain English: "do 1 and 3, skip 2, keep 3 minimal"      ◄── gate 1
                                   │
                              APPROVER (no tools) ─► labels ─► CODER ─► branch + PR
                                                                  │
                                    ┌───────────── REVIEWER ◄─────┘   screenshots, a11y, build,
                                    │  changes requested                 standards, fact-check
                                    ▼                                    (max 3 rounds, then asks you)
                                  CODER fixes ──► REVIEWER passes ─► "@you ready, preview + screenshots"
                                                                       │
                                        you check the preview and merge on your phone   ◄── gate 2
                                                                       │
                                            Vercel deploys ─► VERIFIER smoke-tests the live site ─► "🚀 live"
```

## Roles

| Agent | Trigger | Tools it holds | Output |
|---|---|---|---|
| **Scout** | Weekly cron, or `/scout` | Web search and fetch in one step (no repo), read-only repo in the next | Proposal issues in three tracks: quality, feature, learn |
| **Approver** | Your reply on the proposals issue | None. Reads text, returns JSON | Approve, skip or hold per proposal |
| **Coder** | Approved proposal, or review feedback, or `/fix …` | Edit files, run the package manager, commit locally. No network, no push | A PR from a `crew/…` branch |
| **Reviewer** | After the Coder pushes, or `/review` | Read-only plus web fetch for fact-checking | A review, the `crew/review` status, labels |
| **Verifier** | Every push to the default branch | None (plain scripts) | "Live and verified" or an alarm issue |

The model never pushes, opens PRs, applies labels or sets statuses. Scripts do that from the model's structured
output, after guard rails (protected paths, no new dependencies, size and count caps) have run.

## From your phone

- **Notifications:** GitHub mobile pushes for the weekly issue, "ready to merge", "stuck", "live" and alarms.
- **Approve:** comment on the weekly issue in plain English.
- **Ask for changes:** comment `/fix make the cards smaller on mobile` on a PR.
- **Re-run:** `/review` on a PR, `/scout` on any issue.
- **Merge:** the normal Merge button in the GitHub app. You are the only merger.

## Layout

```
.github/workflows/   reusable workflows: scout, comment, coder, reviewer, verifier
agents/              role prompts, shared ground rules
schemas/             JSON schemas for every structured agent output
scripts/             all deterministic logic, testable without GitHub
templates/project/   what a project gets: .crew/ config plus five thin caller workflows
tests/               local test suite (fixtures and a fake gh)
docs/                SETUP.md, ARCHITECTURE.md
```

## Use it

See [docs/SETUP.md](docs/SETUP.md). In short:

```bash
brew install gh && gh auth login
./scripts/onboard.sh ../your-project
```

## Test it

```bash
bash tests/run.sh
```

This checks YAML and JSON validity, cross-references, and the real logic of the scripts. It cannot run GitHub
Actions itself. See the "Not yet verified" list in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

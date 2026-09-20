# Architecture

## Principle: the model decides, scripts act

Every LLM step returns structured JSON (`schemas/`). Deterministic scripts validate it and perform every
GitHub side effect: create issues, apply labels, push, open PRs, post reviews, set statuses. The model never
holds the permission to do those things, so a confused or manipulated model can produce a bad *suggestion* but
not a bad *action*.

## State machine

```
proposal issue   crew:proposal ──approve──► crew:approved ──Coder starts──► crew:in-progress ──PR merged──► closed
                       └──skip──► crew:skipped (closed)                         └──PR closed unmerged──► crew:skipped

pull request     crew:pr ──Reviewer──► crew:changes-requested ──Coder fix──► (review again, max N rounds)
                       └──────────────► crew:review-approved ──you merge──► Verifier
                                        crew:needs-human   (stuck, blocked, or crashed: the crew stops and asks you)
```

- One crew PR is open at a time. When it is closed or merged, `crew-coder` runs `next` and starts the next
  approved proposal. This avoids merge conflicts in shared content files.
- The weekly run is idempotent per ISO week, keyed on the issue title `Proposals <week>`.

## How the agents hand off

`GITHUB_TOKEN` events do not trigger other workflows, except `workflow_dispatch`. The crew therefore chains
itself with `gh workflow run crew-*.yml`, which needs no GitHub App or personal token. The caller file names
(`crew-coder.yml`, `crew-review.yml`, `crew-scout.yml`) are part of the contract.

## Verdicts

A bot cannot approve or request changes on its own PR. The Reviewer's verdict is therefore published as:
1. the commit status `crew/review` (this is what branch protection requires),
2. the labels `crew:review-approved` or `crew:changes-requested`,
3. a `COMMENT` review carrying the findings, inline where GitHub accepts the anchors and in the body otherwise.

Hard failures come from real exit codes of lint, type-check and build. The model cannot override them, and any
`blocker` or `major` finding forces `changes_requested` even if the model said approve.

## Security model

| Threat | Mitigation |
|---|---|
| Someone else comments to steer the crew | Every comment workflow requires `comment.user.login == repository_owner`, checked twice |
| Prompt injection through web content | Web tools live only in the research step, which has no repo access. Its output is fenced as untrusted data in the next prompt. Coder has no network tools |
| Prompt injection through issue or PR text | Only the owner's comments reach the Coder. Guard rails apply regardless of what the spec says |
| Coder edits workflows, config, secrets, lockfiles | `guard-diff.sh` fails the run on protected paths and on dependency changes |
| PR code steals credentials | The Reviewer runs PR code in a job with a read-only token, no secrets and no stored git credentials. The job that holds write permission and the API key never executes PR code |
| A PR rewrites the rules it is judged by | Reviewer and Coder read `.crew/config.yml` from the default branch, and workflows always come from the default branch |
| Runaway cost | `max-turns` per agent, proposal caps, a review-round cap, one PR at a time |
| Fabricated facts | Ground rules forbid invented claims about the owner and require a cited primary source for every fact. The Reviewer opens each cited source. Unverifiable is a `major` finding, personal claims are a `blocker` |

## Notifications

The bot (`github-actions[bot]`) posts the events that need you and `@`-mentions the owner. GitHub mobile turns
those into pushes. Your own account never posts them, because GitHub does not notify you of your own actions.
Notification channels are deliberately just GitHub comments so the mechanism is one thing to understand.

## Verification status

The scripts, schemas, config and cross-references are covered by `tests/run.sh`. GitHub-side behaviour can only
be verified on real runs.

**Verified on real runs (2026-09-19, portfolio repo):**
- Cross-repo reusable workflows with explicit `secrets:` pass-through from a personal-account caller.
- Config loading from the default branch, sparse checkouts, labels, Node and pnpm setup, dependency audit and
  Lighthouse against production.
- claude-code-action in agent mode with only `github_token` (no Claude GitHub App): the web-only research step
  and the read-only proposal step both returned `structured_output` matching their `--json-schema`.
- Proposal and tracking issue creation, including the `crew-map` that ties reply numbers to issues.
- Verifier: Vercel reports a "Production" GitHub deployment for the merge commit, the smoke test passes, and the
  "live and verified" comment posts.

**Still unverified (first things to watch):**
1. **Comment router and Approver:** that an owner comment triggers `crew-comment`, the tool-less Approver step
   returns structured output, and dispatching `crew-coder` works.
2. **Coder:** that `allowed_bots: github-actions` admits dispatched runs, the `settings` deny rules are honoured,
   and `bot_id`/`bot_name` control the commit identity.
3. **Reviewer:** the Playwright evidence step on the runner (`npx playwright install --with-deps chromium`, axe,
   scroll-reveal handling), inline review anchoring (with its body-only fallback), screenshots from the
   `crew-screenshots` branch rendering inside GitHub mobile comments, and the Vercel "Preview" deployment signal.

Each is a small local fix if it misbehaves; none affects the design.

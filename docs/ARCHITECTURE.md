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

## Not yet verified (needs the first real run)

The scripts, schemas, config and cross-references are covered by `tests/run.sh`. These parts cannot be tested
locally and are the first things to watch on a first run:

1. **claude-code-action behaviour:** that `structured_output` is populated for the `--json-schema` steps in
   agent mode, that `github_token` alone (no Claude GitHub App) is sufficient, that `allowed_bots: github-actions`
   admits dispatched runs, and that the `settings` deny rules are honoured.
2. **Playwright evidence step** on the runner (`npx playwright install --with-deps chromium`, axe, the scroll
   reveal handling for this site).
3. **Vercel signals:** that Vercel reports GitHub deployments named "Preview" and "Production" for these commits.
   If not, the Verifier falls back to smoke-testing `production.url` after its wait, and the Reviewer simply has
   no preview link.
4. **Inline review anchoring**, with the automatic fallback to body-only findings if GitHub rejects a line.
5. **Screenshot rendering** from the `crew-screenshots` branch inside comments on GitHub mobile.
6. **`secrets:` pass-through** from a personal-account caller to a reusable workflow in another repo.

Each is a small local fix if it misbehaves; none affects the design.

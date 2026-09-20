# Setup

## 0. Prerequisites (once)

```bash
brew install gh
gh auth login          # log in as the repo owner (sreeramg-hub); choose SSH to match the repo remotes
```

No `brew`? Install Homebrew first from <https://brew.sh> (it asks for your Mac password). On Apple Silicon, put
it on your PATH afterwards:

```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile && eval "$(/opt/homebrew/bin/brew shellenv)"
```

You also need an Anthropic API key. It is stored as a GitHub Actions secret and never leaves GitHub.

## 1. Publish this repo

The project workflows call the ones in this repo, so it must be reachable from them. Public is simplest.
(A private shared repo also works if you enable Settings > Actions > General > Access > "Accessible from
repositories owned by the user".)

```bash
cd sreeram-repo-crew
git add -A && git commit -m "feat: initial crew"
gh repo create sreeramg-hub/sreeram-repo-crew --public --source=. --push
```

Optional but recommended once it works: tag `v1` and change `@main` to `@v1` in each project's caller files so a
later change here cannot surprise a project.

## 2. Onboard a project

```bash
./scripts/onboard.sh ../sreeram-ganesan
```

It copies the templates without overwriting anything, creates the labels, prompts for `ANTHROPIC_API_KEY`
(hidden input straight to GitHub), lets Actions open PRs, and optionally makes `crew/review` a required status on
the default branch. Admins (you) can still merge in an emergency; agents cannot push to the default branch.

## 3. Land the crew files with a PR

Workflows run from the default branch, so the `.crew/` folder and `.github/workflows/crew-*.yml` files must be
merged first. For the portfolio they are already in your working tree:

```bash
cd ../sreeram-ganesan
git checkout -b chore/crew-setup
git add .crew .github/workflows CLAUDE.md
git commit -m "chore: add the agent crew"
git push -u origin chore/crew-setup      # then open the PR and merge it
```

## 4. First run

Actions tab > **crew-scout** > Run workflow (tick *force*). Or comment `/scout` on any issue.
Within a few minutes a "Proposals 2026-Wxx" issue appears and your phone gets a push. Reply to it.

## 5. Phone notifications

GitHub mobile > Settings > Notifications: turn on push. The crew mentions `@you` on the events that need you,
so the default "Participating and @mentions" setting is enough.

## 6. Vercel specifics

- **Commit author.** Vercel Hobby only deploys commits from accounts it can match. `coder.commit_as_owner: true`
  (the default) commits as you, with a `Co-Authored-By: Claude` trailer, so previews are not blocked.
- **Protected previews.** If Deployment Protection is on, set `preview.mode: deployment` and add a repository
  secret `CREW_PREVIEW_HEADERS` such as `{"x-vercel-protection-bypass":"<secret>"}`. With the default
  `preview.mode: local` the Reviewer builds and browses the PR itself and needs no Vercel access.
- **Production check.** The Verifier waits for a GitHub deployment named "Production" for the merge commit, then
  smoke-tests `production.url`.

## 7. Cost and safety knobs (`.crew/config.yml`)

`limits.*_turns` caps the model per run, `scout.max_proposals` and `scout.tracks` cap the weekly volume,
`coder.max_fix_rounds` caps the review loop, `coder.protected_paths` lists files the Coder can never touch.

## Onboarding another project (Splanner, meal planner, ...)

1. `./scripts/onboard.sh ../sprint-hub`
2. Edit its `.crew/config.yml` (commands, pages, production URL), `.crew/goals.md` and `.crew/sources.yml`.
3. Land the files with a PR, then run **crew-scout** once.

Non-Node projects work if `commands.*` are set to their own tooling and `node_version` is irrelevant to them;
the Node setup steps are the only Node-specific part today.

## Troubleshooting

- **Nothing happens on Monday.** GitHub disables scheduled workflows in public repos after 60 days without
  repository activity. Re-enable in the Actions tab (GitHub also emails a warning). Merging a PR counts as activity.
- **A run failed.** GitHub emails failed runs by default; the crew also comments on the issue or PR with a run link.
- **The Reviewer crashed and the PR cannot merge.** The crew sets `crew/review` to error and asks you to comment
  `/review`. As the admin you can also merge without it.
- **Reply not understood.** The Approver asks you to rephrase. Numbers refer to the list in the weekly issue.

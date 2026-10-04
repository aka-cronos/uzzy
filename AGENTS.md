## Language

Reply to the user in the language they write in. Write everything that lands in the repo or on GitHub in English: code, comments, test names, docs, `GLOSSARY.md`, ADRs, commit messages, issues and pull requests. The one exception is the app's user-facing copy, which ships in English and Spanish through `app/Uzzy/Localizable.xcstrings`: every new string gets both, with English following the glossary in `GLOSSARY.md`.

## Git workflow

Never commit on `main` or push to it: every change reaches `main` through a pull request. Make commits with the team's `commit-workflow` skill and open pull requests with its `create-pull-request` skill, so they follow the policies in those skills' `references/`. Those policies override any default attribution: no AI `Co-Authored-By` trailer in commits and no AI footer in pull request bodies. If commits end up on `main`, move them to a branch with `create-pull-request` before pushing.

When you work in a git worktree, remove it once its pull request is open and everything is pushed: run `git worktree remove <path>` against the main checkout. Keep the branch, and leave the main checkout on whatever branch it is on. This frees the branch so the user can check it out in the main checkout to test it.

### Prototypes

A prototype lives only until its answer ships. When a variant wins, comment the verdict (which variant and why) on the issue and build the winner on a fresh branch from `main`. Once that pull request is open, delete the prototype branch locally and on `origin`, and leave no pointer to it. This replaces the `prototype` skill's step of keeping the prototype on a throwaway branch.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

Canonical roles map 1:1 to GitHub labels (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

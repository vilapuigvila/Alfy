# Git Instructions (Agents)

## Branching (Feature Branches)

- Never work directly on `main`.
- Create a feature branch per task:
  - `git switch -c feat/<short-description>`
  - Examples: `feat/cached-urlsession-tests`, `fix/build-macos`

## Daily Workflow

- Sync with remote before starting:
  - `git fetch origin`
  - `git switch main && git pull --ff-only`
  - `git switch <your-branch> && git rebase main`
- Keep commits small and focused; avoid mixing refactors with behavior changes.

## Staging & Diffs

- Prefer interactive staging:
  - `git add -p`
- Verify what will be committed:
  - `git status`
  - `git diff` (working tree)
  - `git diff --cached` (staged)

## Commit Messages

- Keep messages short and action-oriented (this repo’s history favors concise messages).
- Recommended patterns:
  - `fix: …`, `add: …`, `refactor: …`, `test: …`

## Before Opening a PR

- Build and test from a clean state:
  - `swift build`
  - `swift test`
- Ensure no accidental files are included (e.g. `.DS_Store`, `.build/`).

## Updating Your PR

- Prefer rebasing on `main` to keep history linear:
  - `git fetch origin && git rebase origin/main`
- If you must resolve conflicts, keep resolutions minimal and re-run `swift test`.

## Pull Requests

- PR description should include:
  - What changed + why
  - How to verify (commands/steps)
  - Any follow-ups/known limitations


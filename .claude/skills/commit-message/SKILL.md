---
name: commit-message
description: Examine the current git repository's staged and working-tree changes and emit ONLY a single short imperative-mood commit subject line on stdout. Used by `just done` to AI-author commit messages from whatever just changed.
---

# Commit Message

Look at the staged + working-tree changes in the current git repository, identify the dominant theme, and emit ONLY a commit message subject line to stdout. Nothing else.

## Output contract

The output of this skill is captured directly into a shell variable and passed to `git commit -m`. Output discipline is the entire job.

- Print exactly one subject line, ≤72 characters, imperative mood ("Add X", "Fix Y", "Update Z" — not "Added", "Fixes", "Updating").
- No body, no preamble, no quotes, no backticks, no Markdown formatting.
- No leading or trailing whitespace beyond a single trailing newline.
- If there are no staged changes (`git diff --cached --quiet` returns true), print nothing and exit. The caller fails on empty.

## Workflow

1. Run `git status --short` to see which files changed at a glance.
2. Run `git diff --cached` (and `git diff` for unstaged context if needed) to understand what changed.
3. Pick the dominant theme of the change set. If multiple unrelated themes exist, prefer the most user-visible one as the subject.
4. Emit the subject line and stop.

## Style

This repo's existing log uses terse imperative subjects without Conventional Commits prefixes:

- `Updates to recipes`
- `Add a recipe`

Match that voice. **Don't** add `feat:`, `fix:`, etc. unless the existing history adopts them.

Bias toward describing the *outcome* (what the repo now does or contains) rather than the mechanics (which files moved). A reader scanning `git log --oneline` should be able to tell what changed without opening the diff.

## Examples

These are illustrative — refine after first run if the style doesn't match what the user wants.

| Change set                                          | Subject line                              |
|-----------------------------------------------------|-------------------------------------------|
| New recipe directory + index update                 | Add Bowties and Broccoli recipe           |
| Existing recipe regenerated (README + YAML refresh) | Regenerate Slow Cooker Chicken Cacciatore |
| Skill changes only                                  | Refine recipe-archiver nutrition rules    |
| Multiple recipes refreshed in one go                | Refresh recipe corpus                     |
| Schema and skill changes together                   | Add recipe.yaml output with JSON schema   |
| Justfile workflow change                            | Switch recipe builds to parallel just     |

## Failure modes

- Nothing staged: print nothing, exit. The caller (`just done`) will catch the empty output and abort.
- Working tree only (nothing staged but unstaged changes exist): the caller stages everything before invoking this skill, so this case shouldn't arise. If it does, print nothing.

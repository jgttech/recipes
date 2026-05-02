---
name: recipe-index
description: Rebuild recipes/README.md from the current state of recipes/<Name>/ directories. Lists every directory containing a recipe.yaml (or README.md as fallback), sorts alphabetically by display title, and writes the index — pruning entries for removed recipes and adding any new ones. Invoked by `just index` for manual rebuild and automatically by `just recipe` after archiving.
---

# Recipe Index

Rebuild `recipes/README.md` to match what's actually on disk. Adds entries for new recipes, prunes entries for recipes that have been removed, and keeps everything alphabetically sorted.

This skill is non-interactive — it runs to completion without asking the user anything.

## Workflow

### Step 1: Read the existing index (for diffing)

Before overwriting, read `recipes/README.md` and capture the set of currently-listed slugs (the link targets) so the final report can mention what was added or pruned. If the file doesn't exist yet, treat the existing set as empty.

### Step 2: Survey recipe directories

List every immediate subdirectory of `recipes/` (skip files like `recipes/README.md` itself). For each directory:

1. **Prefer `recipe.yaml`.** Read it and extract the `title:` field as the canonical display title.
2. **Fall back to `README.md`** if no `recipe.yaml` exists. Parse the first H1 (the leading `# ...` line) as the title.
3. **Skip the directory** if neither file exists — it's not a recipe.

Capture both the display title and the directory name (slug) for each recipe.

### Step 3: Sort

Sort alphabetically by display title, **case-insensitive**, ignoring leading articles ("The", "A", "An") only for the comparison key — keep the article in the title that gets written.

Example sort keys:
- `Bowties and Broccoli` → key `bowties and broccoli`
- `The Ultimate Guide to Sourdough` → key `ultimate guide to sourdough`
- `Slow Cooker Chicken Cacciatore` → key `slow cooker chicken cacciatore`

### Step 4: Write recipes/README.md

Replace the file's content entirely — this skill is the source of truth for the index. Don't try to preserve manual edits. Format:

```markdown
# Recipes

- [<Display Title 1>](<slug 1>/README.md)
- [<Display Title 2>](<slug 2>/README.md)
- [<Display Title 3>](<slug 3>/README.md)
```

Use the exact display title (with original capitalization) as the link text. The link target is the slug followed by `/README.md` — a relative path within `recipes/`.

If there are zero recipe directories, write:

```markdown
# Recipes

_No recipes yet._
```

### Step 5: Report

Tell the user:
- Total number of recipes indexed
- **Added** entries (slugs that weren't in the old index but are now)
- **Pruned** entries (slugs that were in the old index but are no longer present on disk)
- **Skipped** directories (had no recipe.yaml or README.md) — call them out by name

If there are no changes (added + pruned both empty), say "No changes — index already accurate."

## Notes

- This skill operates from the project root. The directory `recipes/` is relative to the working directory.
- Don't fabricate titles. If a directory has no `recipe.yaml` and no parseable README H1, skip it and report.
- The skill never deletes recipe directories — it only updates the index file. Pruning means "removed from the index because the directory was already gone."

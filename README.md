# Recipes

Personal recipe archive. Each recipe lives in `recipes/<Name>/` as a README, a structured `recipe.yaml`, and a self-contained `index.html` snapshot of the source page.

See [recipes/README.md](recipes/README.md) for the current index of archived recipes.

## Setup

Install [just](https://just.systems) and Claude Code (the `claude` CLI).

## Add a recipe

```sh
# Mode 1 — URL only (AI derives the directory name)
just recipe https://www.budgetbytes.com/bowties-and-broccoli/

# Mode 2 — name and URL
just recipe Bowties-and-Broccoli https://www.budgetbytes.com/bowties-and-broccoli/
```

## Save your changes

```sh
just done
```

Stages everything, AI-generates a commit message from the diff, commits, and pushes.

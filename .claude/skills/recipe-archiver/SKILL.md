---
name: recipe-archiver
description: Fetch a recipe webpage and produce recipes/<Name>/README.md (markdown form) plus recipes/<Name>/recipe.yaml (structured form, validated against bin/schemas/recipe.schema.json), then upsert an alphabetical entry into recipes/README.md. Invoked as /recipe-archiver <Name> <URL> from the project root, typically by the just recipe task. Re-runs are idempotent.
---

# Recipe Archiver

Take a Title-Case-Kebab `<Name>` and a recipe URL. Produce three artifacts:

1. `recipes/<Name>/README.md` — human-readable markdown form
2. `recipes/<Name>/recipe.yaml` — structured form, validated against `bin/schemas/recipe.schema.json`
3. An alphabetical entry in `recipes/README.md` (the index), upserted

The same data appears in both the README and the YAML — the YAML is for downstream automation; the README is for reading.

## Inputs

Invoked as `/recipe-archiver <Name> <URL>` with the project root as the current working directory. The `<Name>` has already been resolved to follow the naming convention (see below) — do not modify it. The directory `recipes/<Name>/` already exists and has been emptied by the caller (`just recipe`), so you're writing into a clean directory.

## Workflow

### Step 1: Fetch the page

Use the web fetch capability to retrieve the recipe page contents.

### Step 2: Write `recipes/<Name>/README.md`

Extract the recipe details and write the file with this structure:

```markdown
# <Recipe Title>

**Source:** <Author or Site Name>
**Recipe URL:** [<full URL>](<full URL>)
**Prep:** <prep time> | **Cook:** <cook time> | **Servings:** <servings>

## Ingredients

- [ ] <ingredient 1 with measurement>
- [ ] <ingredient 2 with measurement>
- [ ] ...

### For Serving (only if applicable)

- [ ] <serving item 1>
- [ ] <serving item 2>

## Instructions

1. **<Lead phrase for step 1>** <Paraphrased instructions for step 1.>
2. **<Lead phrase for step 2>** <Paraphrased instructions for step 2.>
3. ...

## Nutrition (per serving)

| Calories | Protein | Carbs | Fat | Fiber | Sugar |
|----------|---------|-------|-----|-------|-------|
| <calories> | <protein> | <carbs> | <fat> | <fiber> | <sugar> |
```

### Step 3: Write `recipes/<Name>/recipe.yaml`

Mirror the same recipe data into a structured YAML file. The first line MUST be the schema-reference comment so editors validate it against the JSON Schema:

```yaml
# yaml-language-server: $schema=../../bin/schemas/recipe.schema.json
title: <Recipe Title>
source: <Author or Site Name>
url: <full URL>
times:
  prep: <prep time string, or null>
  cook: <cook time string, or null>
servings: <servings string, or null>
ingredients:
  - name: null            # null for the default/main group
    items:
      - "<ingredient 1 verbatim>"
      - "<ingredient 2 verbatim>"
  - name: For Serving     # only if the source has this subsection
    items:
      - "<serving item 1>"
instructions:
  - lead: "<lead phrase 1>"
    detail: "<paraphrased step 1 body>"
  - lead: "<lead phrase 2>"
    detail: "<paraphrased step 2 body>"
nutrition:
  calories: <string or null>
  protein: <string or null>
  carbs: <string or null>
  fat: <string or null>
  fiber: <string or null>
  sugar: <string or null>
notes: <string or null>
```

YAML rules:
- **Use YAML `null` for missing values**, not the em-dash that the README uses for visual rendering. The schema permits `string | null` everywhere a value can be absent.
- **Quote strings that contain special YAML characters** (`:`, `#`, leading `-`, leading `*`, etc.). When in doubt, quote.
- **Preserve units in nutrition values** as-is (e.g., `"295 cal"`, `"10.88g"`). Don't strip or normalize.
- **Ingredient groups** mirror the README's optional "For Serving" subsection. Recipes without subsections use a single group with `name: null`.
- **Instructions** split the bolded lead phrase from the paraphrased detail body — the same data the README presents as `**lead.** detail`.
- **`additionalProperties: false`** is set at every object level in the schema, so don't add fields the schema doesn't define.

The schema lives at `bin/schemas/recipe.schema.json` (relative path from each `recipe.yaml` is `../../bin/schemas/recipe.schema.json`). If a generated YAML doesn't match the schema, fix the YAML.

### Step 4: Upsert into `recipes/README.md`

Read the existing index at `recipes/README.md`. The bullet format is:

```markdown
- [<Recipe Title>](<Name>/README.md)
```

Behavior:
- If a bullet whose link target starts with `<Name>/` already exists, **replace that line** with the new bullet (the title may have shifted on a re-run).
- Otherwise, **insert** a new bullet in alphabetical order by display title (case-insensitive; ignore leading articles when sorting).
- If `recipes/README.md` doesn't exist, create it with a `# Recipes` heading before adding the entry.

This upsert behavior is what makes re-runs idempotent: archiving the same recipe twice doesn't create duplicate index entries.

Use the recipe's actual display title in the link text and the `<Name>` directly as the link target.

### Step 5: Confirm output

Report back to the user with:

- The paths to both artifacts (`recipes/<Name>/README.md` and `recipes/<Name>/recipe.yaml`)
- A one-sentence summary of the recipe
- Whether the index entry was inserted (new) or replaced (re-run)

## Content rules

- **Paraphrase the instructions.** Do not copy the recipe author's instruction text verbatim. Rewrite each step in your own words while preserving all technical details: temperatures, times, quantities, equipment, and the order of operations.
- **Keep ingredients verbatim.** Ingredient lists are factual measurements; reproduce them exactly as listed (units, descriptors, and prep notes like "chopped" or "divided" included).
- **Always include attribution.** The source name and clickable original URL must appear at the top of the markdown file.
- **Use markdown task list checkboxes (`- [ ]`)** for every ingredient line so the user can check items off while shopping or cooking.
- **Bold the lead phrase** of each numbered instruction step (e.g., `**Brown the chicken.**`) so steps are scannable.
- **Always include the Nutrition section with all six fields.** Use the table format above (Calories, Protein, Carbs, Fat, Fiber, Sugar — in that order). If the source provides a value, fill it in with the source's units. If the source doesn't provide a particular value, use `—` (em dash) as an empty indicator. Never fabricate values. The archived `index.html` is the source of truth for verification.

## Optional additions

If the user has previously asked for them in this conversation or provides a context note (e.g., "we have a toddler"), append a `## Notes` section after Nutrition with practical adjustments — toddler portioning, sodium reductions, substitutions, serving variations. Otherwise, leave this section out.

## Naming convention reference

The `<Name>` argument should already follow the convention. For your reference (and to validate it):

Title-Case-Kebab. Words joined by hyphens. Major words capitalized; minor words ("a", "an", "the", "of", "and", "with", "in", "on", "for", "to", "from", "by", "or", "but", "at", "as") stay lowercase — except when one is the first word.

The first row below is the canonical example from the existing repo; the rest are synthesized to teach the convention.

| Input title                                  | Directory name                       |
|----------------------------------------------|--------------------------------------|
| The BEST Slow Cooker Chicken Cacciatore!     | Slow-Cooker-Chicken-Cacciatore       |
| Macaroni and Cheese                          | Macaroni-and-Cheese                  |
| Pasta with Roasted Tomatoes                  | Pasta-with-Roasted-Tomatoes          |
| A Simple Roast Chicken Recipe                | Simple-Roast-Chicken                 |
| Grandma's 5-Ingredient Apple Pie (Easy!)     | Grandmas-5-Ingredient-Apple-Pie      |
| One-Pot Lemon Garlic Shrimp & Orzo           | One-Pot-Lemon-Garlic-Shrimp-and-Orzo |
| Sheet Pan Salmon with Broccoli — NYT Cooking | Sheet-Pan-Salmon-with-Broccoli       |
| The Ultimate Guide to Sourdough              | Ultimate-Guide-to-Sourdough          |

If `<Name>` doesn't match this convention, write the README anyway but flag the discrepancy in your final report.

## Error handling

- If the URL doesn't return a recognizable recipe (e.g., it's a blog homepage or a category page), tell the user and ask for the specific recipe URL. Do not write a stub README.
- If the page has no nutrition data at all, still emit the Nutrition section with the standard six-field table, filling every cell with `—`. The archived `index.html` will reflect what the source actually provided.

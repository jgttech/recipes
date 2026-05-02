---
name: recipe-namer
description: Given a recipe URL, fetch the page, derive a Title-Case-Kebab directory name from the recipe's actual title, and emit ONLY that name to stdout. Use exclusively when a caller (e.g., the just recipe task) needs to capture the directory name into a shell variable from a URL alone.
---

# Recipe Namer

Take a single recipe URL and emit a Title-Case-Kebab directory name on stdout. Nothing else.

## Output contract

This skill's output goes directly into a shell variable. Output discipline is the entire job.

- Print the name as a single token (e.g., `Slow-Cooker-Chicken-Cacciatore`).
- No quotes, no backticks, no prose, no preamble, no trailing explanation.
- No leading or trailing whitespace beyond a single trailing newline.
- If the URL doesn't resolve to a recognizable recipe, print nothing and exit — the caller fails the run on empty output.

## Workflow

1. **Fetch the page.** Use the web fetch capability to retrieve the URL.
2. **Identify the recipe title.** Prefer the page `<h1>` or `og:title`. Do not use the URL slug — slugs often contain site branding or SEO terms.
3. **Apply the naming convention** (below).
4. **Emit the name.** Print the result and stop.

## Naming convention

Title-Case-Kebab. Words joined by hyphens. Major words capitalized; minor words ("a", "an", "the", "of", "and", "with", "in", "on", "for", "to", "from", "by", "or", "but", "at", "as") stay lowercase — except when one is the first word.

Apply these passes:

1. **Strip leading articles.** "The", "A", "An" at the start are removed entirely.
2. **Strip site/SEO suffixes and parentheticals.** "— NYT Cooking", "| Bon Appétit", "(Easy!)", trailing "Recipe", "{V/GF}" — drop them.
3. **Strip punctuation.** Apostrophes, exclamation marks, commas, colons, parentheses, em dashes, and ampersands are removed (an ampersand becomes the word `and`).
4. **Capitalize major words; lowercase minor words.** Numerals stay as digits.
5. **Join with hyphens.**

## Examples

The first row is the canonical example from the existing repo. The rest are synthesized to teach the convention — flag any you'd handle differently.

| Input title                                  | Output name                          |
|----------------------------------------------|--------------------------------------|
| The BEST Slow Cooker Chicken Cacciatore!     | Slow-Cooker-Chicken-Cacciatore       |
| Macaroni and Cheese                          | Macaroni-and-Cheese                  |
| Pasta with Roasted Tomatoes                  | Pasta-with-Roasted-Tomatoes          |
| A Simple Roast Chicken Recipe                | Simple-Roast-Chicken                 |
| Grandma's 5-Ingredient Apple Pie (Easy!)     | Grandmas-5-Ingredient-Apple-Pie      |
| One-Pot Lemon Garlic Shrimp & Orzo           | One-Pot-Lemon-Garlic-Shrimp-and-Orzo |
| Sheet Pan Salmon with Broccoli — NYT Cooking | Sheet-Pan-Salmon-with-Broccoli       |
| The Ultimate Guide to Sourdough              | Ultimate-Guide-to-Sourdough          |

## Failure modes

- URL is unreachable or returns a non-2xx response: print nothing, exit.
- Page is a homepage, category, or list of recipes (no single recipe title): print nothing, exit.
- Title cannot be confidently identified: print nothing, exit.

The caller's `if [ -z "$name" ]` check surfaces a clean error in all of these.

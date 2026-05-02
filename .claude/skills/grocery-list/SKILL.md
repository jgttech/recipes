---
name: grocery-list
description: Interactive assistant that surveys archived recipes, asks the user which ones to shop for, and produces a single self-validating tar.gz bundle in ~/Documents/ containing markdown (.md), interactive HTML (.html), structured YAML (.yaml, validated against bin/schemas/grocery-list.schema.json), and a copy of the schema. All staging happens in a temp directory; ~/Documents/ ends up with only the .tar.gz. Invoked by `just list`.
---

# Grocery List

Help the user assemble a grocery list from one or more archived recipes. This is an **interactive** skill — converse with the user, don't try to one-shot it.

## Workflow

### Step 1: Survey available recipes

Read every `recipes/*/recipe.yaml` in the project (these are the source of truth — they contain the full structured ingredient list including "For Serving" subsections). Build a numbered list of recipe titles using the `title:` field from each YAML.

If a recipe directory has no `recipe.yaml` (e.g., a not-yet-retrofitted recipe), fall back to the entry in `recipes/README.md`. Note the limitation in your message — without the YAML, you can't pull structured ingredients.

### Step 2: Present and ask

Show the numbered list and ask which recipes the user wants on their grocery run. Accept a range of input forms — don't be picky:

- Numbers: `1, 3, 5` or `1 3 5`
- Ranges: `1-3`, `2,4-6`
- Titles: `Bowties and Broccoli, Slow Cooker Chicken Cacciatore`
- `all`

If the user's input is ambiguous, ask one clarifying question rather than guessing.

### Step 3: Aggregate ingredients and resolve URLs

For each selected recipe, read its `recipe.yaml` and capture:
- The `title` and the directory name (slug)
- The `url` field (original source URL)
- The full `ingredients` block — every group (`name: null` for the main group, plus any named subsections like "For Serving")

Combine the ingredients into a single flat list across all selected recipes.

**Ingredient rules:**
- Keep each ingredient line **verbatim** from the YAML (measurements, units, descriptors, prep notes all preserved).
- Don't try to do unit math across recipes. If two recipes call for "1 medium yellow onion" and "1 yellow onion, chopped", list both lines separately.
- Don't reorder or "categorize" by produce/pantry/dairy — keep the source's ordering, grouped by recipe of origin (it's easier to verify nothing was dropped that way).
- Use `- [ ]` task list checkboxes so the user can check items off while shopping.

**Compute `archive_url` for each selected recipe.** This is the GitHub blob URL for the recipe's archived `index.html` snapshot. Determine it by reading `git remote get-url origin` and transforming:

```bash
remote=$(git remote get-url origin 2>/dev/null || true)
# Transform: git@github.com:<user>/<repo>.git → https://github.com/<user>/<repo>
# Transform: https://github.com/<user>/<repo>.git → https://github.com/<user>/<repo>
base=$(printf '%s\n' "$remote" | sed -E -e 's|^git@github.com:|https://github.com/|' -e 's|\.git$||')
# Per-recipe: $base/blob/main/recipes/<slug>/index.html
```

If there's no `origin` remote, the URL doesn't match either GitHub pattern, or the host isn't `github.com`, set `archive_url` to `null` (the schema allows null). The skill must not crash on non-GitHub setups.

Branch is hardcoded to `main` (matches this project's convention). If the file is committed on `main` and pushed, the link works; if not, it 404s — the skill doesn't try to verify, that's a runtime concern.

### Step 4: Set up the staging directory

Compute the current Unix timestamp via `date +%s`. Then create a temp staging directory with `mktemp -d`, and inside it create a subdirectory named `grocery-list.<unix-timestamp>` — that's where all four files (md, html, yaml, schema) will go. Only the final tar.gz lands in `~/Documents/`; the temp directory is removed at the end.

```bash
TS=$(date +%s)
TMP=$(mktemp -d)
BUNDLE="$TMP/grocery-list.$TS"
mkdir -p "$BUNDLE"
```

In subsequent steps, `<BUNDLE>` refers to this staging subdirectory. All file writes go there.

### Step 5: Write the markdown file

Write to `<BUNDLE>/grocery-list.<unix-timestamp>.md` as a single aggregated shopping list. Recipe attribution lives next to each item so the user always knows which recipe an ingredient is for.

```markdown
# Grocery List

**Generated:** <ISO 8601 datetime, local time zone>

**For:**
- [<Recipe 1 title>](<source url 1>) · *[archive ↗](<archive_url 1>)*
- [<Recipe 2 title>](<source url 2>) · *[archive ↗](<archive_url 2>)*

## Shopping List

- [ ] <ingredient text> — *<Recipe title>*
- [ ] <ingredient text> — *<Recipe A>, <Recipe B>*
- [ ] ...

### For Serving

- [ ] <serving item text> — *<Recipe title>*
```

Rules:
- **One flat list, sorted alphabetically by ingredient text** (case-insensitive).
- **Recipe attribution after an em-dash, italic.** When the same exact text comes from multiple recipes, list all source recipes joined by `, ` (e.g., `*Bowties and Broccoli, Slow Cooker Chicken Cacciatore*`). Don't merge non-identical lines — different text = different list rows even if they refer to the same ingredient.
- **"For Serving" items** go in their own `### For Serving` sub-section at the bottom. Same alphabetical ordering and attribution rules.
- **Each "For:" entry pairs the source link with an inline archive link** separated by ` · `. **If `archive_url` is null** for a recipe, omit just the ` · *[archive ↗](...)*` portion — keep the source link.

This swap is deliberate: shoppers don't read by-recipe in the aisle. They want one list grouped the way they actually shop (alphabetically clusters similar items). Attribution stays for context.

### Step 6: Write the HTML file

Write a self-contained HTML companion alongside the markdown — same base name, `.html` extension. Path: `<BUNDLE>/grocery-list.<unix-timestamp>.html` (same `<unix-timestamp>` as the markdown file).

Requirements:

- **Fully self-contained.** No external CSS, no external JS, no external fonts, no images. The user shares the file directly (over Messages/email/AirDrop), so it must work offline with zero network access.
- **Mobile-friendly.** Includes the viewport meta tag and is comfortable on a phone screen.
- **Dark-mode aware** via `@media (prefers-color-scheme: dark)`.
- **Single aggregated shopping list.** All ingredients across all selected recipes appear in one alphabetical list (with a "For Serving" sub-section underneath). No per-recipe sections — shoppers don't shop by recipe.
- **Calm typographic layout, not cards.** Each row is a hairline-separated list item: checkbox · ingredient text · subtle muted attribution line · action buttons. No borders, no backgrounds, no pills. Recipe attribution lives as inline links in the muted attribution line below the ingredient — present and tappable, but visually subordinate so the ingredient text reads first. Multiple recipes are joined by ` · `. Aesthetic reference: GNOME Adwaita lists / Apple UITableView.
- **Tap anywhere on a row to toggle the checkbox.** Clicks on action buttons or attribution links are excluded so they do their own thing.
- **Sticky progress counter with progress bar.** A top-of-page header shows `<checked> / <total> picked up` plus a 2px progress bar that doubles as the visual divider between the sticky header and the list — filled portion is the accent color, unfilled portion is `var(--rule)`. No extra border-bottom.
- **"Show recipes" toggle** (upper right of the sticky header, alongside "Hide picked up"). Recipe attribution is **hidden by default** — the calm view is the primary mode. The toggle reveals attribution lines for power users; state persists in localStorage via `state.prefs.showAttribution`.
- **Hide picked up toggle.** Collapses checked items out of view; persists via `state.prefs.hideChecked`.
- **Smooth animations.** Items fade in on render/add and fade out + collapse on delete. Strikethrough transitions in via color animation. Progress bar fills smoothly. All animations honor `prefers-reduced-motion`.
- **Interactive checkboxes.** Each ingredient is a real `<input type="checkbox">` (not a disabled markdown checkbox). Tapping toggles checked state.
- **Per-device persistence via `localStorage`** for the full list state — checks, edits, deletions, and added items. Each device gets its own independent state.
- **Add custom items.** A form at the bottom lets the user type new items mid-shop; they appear under a "Custom" section and persist.
- **Advanced: bulk import via JSON.** A collapsed `<details>` block beneath the add form ("Advanced — bulk import JSON") accepts a JSON array of items pasted into a textarea. Useful for AI-generated lists from elsewhere. Accepts three shapes — `["milk","bread"]`, `[{"text":"milk"},{"text":"eggs","checked":true}]`, or `{"items": [...]}`. Imported items are merged into Custom alongside typed-in ones; invalid entries are skipped with a count reported back to the user. The accepted shapes are formally defined by `bin/schemas/grocery-list-import.schema.json` (the user can hand this schema to an external AI to generate compliant JSON).
- **Edit existing item text.** A small ✎ icon on each row enters inline edit mode (contenteditable). Enter saves, Escape cancels.
- **Delete items.** A small × icon hides the item. Baseline (recipe-derived) items are recoverable via a "Restore deleted" button at the bottom; custom items are removed permanently.
- **Strikethrough + dim** when checked, so the visual reflects what's been picked up.

Use this exact template, filling in the placeholders. Keep the structure and the inline CSS/JS verbatim — it's been tuned for this use case.

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Grocery List — <ISO 8601 datetime></title>
  <style>
    :root {
      color-scheme: light dark;
      --bg: #ffffff;
      --fg: #1a1a1a;
      --muted: #666;
      --accent: #0a7;
      --rule: #e5e5e5;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #111;
        --fg: #e8e8e8;
        --muted: #aaa;
        --accent: #4dd6a3;
        --rule: #2a2a2a;
      }
    }
    * { box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", sans-serif;
      max-width: 640px;
      margin: 0 auto;
      padding: 1.25rem;
      line-height: 1.5;
      color: var(--fg);
      background: var(--bg);
      -webkit-text-size-adjust: 100%;
    }
    h1 { font-size: 1.6rem; margin: 0 0 0.5rem; }
    h2 { font-size: 1.2rem; margin: 1.5rem 0 0.5rem; padding-bottom: 0.25rem; border-bottom: 1px solid var(--rule); }
    h3 { font-size: 1rem; margin: 1rem 0 0.25rem; color: var(--muted); }
    .recipes a { color: inherit; }
    .archive-inline {
      color: var(--muted);
      text-decoration: none;
      opacity: 0.75;
      font-size: 0.85em;
    }
    .archive-inline:hover { opacity: 1; color: var(--fg); }
    .meta { color: var(--muted); font-size: 0.9rem; margin-bottom: 1rem; }
    .meta strong { color: var(--fg); }
    ul.recipes { padding-left: 1.25rem; margin: 0.25rem 0 1rem; }
    .progress {
      position: sticky;
      top: 0;
      z-index: 10;
      background: var(--bg);
      padding: 0.7rem 0 0;
      margin: 0 0 0.6rem;
      display: flex;
      flex-direction: column;
      gap: 0.55rem;
      font-size: 0.9rem;
      color: var(--muted);
    }
    .progress-info {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 0.5rem;
      flex-wrap: wrap;
    }
    .progress strong { color: var(--fg); font-weight: 600; }
    .progress-bar {
      width: 100%;
      height: 2px;
      background: var(--rule);
      overflow: hidden;
    }
    .progress-bar-fill {
      height: 100%;
      width: 0%;
      background: var(--accent);
      transition: width 0.35s cubic-bezier(0.4, 0, 0.2, 1);
    }
    .controls { display: inline-flex; gap: 0.15rem; align-items: center; flex-wrap: wrap; justify-content: flex-end; }
    .toggle-hide,
    .toggle-attr {
      background: transparent;
      border: none;
      color: var(--muted);
      cursor: pointer;
      font: inherit;
      font-size: 0.85rem;
      padding: 0.25rem 0.5rem;
      border-radius: 5px;
      transition: color 0.15s, background 0.15s;
    }
    .toggle-hide:hover,
    .toggle-attr:hover { color: var(--fg); background: var(--rule); }
    .toggle-hide[aria-pressed="true"],
    .toggle-attr[aria-pressed="true"] { color: var(--accent); }
    body.hide-attribution .attribution { display: none; }
    ul.items { list-style: none; padding: 0; margin: 0; }
    ul.items li {
      display: flex;
      align-items: flex-start;
      gap: 0.75rem;
      padding: 0.7rem 0.25rem;
      border-bottom: 1px solid var(--rule);
      transition: background 0.18s ease;
      animation: item-fade-in 0.25s ease-out both;
    }
    ul.items li:hover { background: color-mix(in srgb, var(--fg) 4%, transparent); }
    ul.items li:active { background: color-mix(in srgb, var(--fg) 7%, transparent); }
    ul.items li:last-child { border-bottom: none; }
    ul.items li[hidden] { display: none; }
    ul.items li.exiting {
      animation: item-fade-out 0.2s ease-in forwards;
      pointer-events: none;
    }
    body.hide-checked ul.items li:has(input[type="checkbox"]:checked) { display: none; }
    ul.items input[type="checkbox"] {
      width: 1.25rem;
      height: 1.25rem;
      margin: 0.2rem 0 0;
      flex-shrink: 0;
      accent-color: var(--accent);
      cursor: pointer;
      transition: transform 0.12s ease;
    }
    ul.items input[type="checkbox"]:active { transform: scale(0.92); }
    .content {
      flex: 1;
      min-width: 0;
      display: flex;
      flex-direction: column;
      gap: 0.15rem;
      cursor: pointer;
    }
    .text {
      user-select: text;
      word-break: break-word;
      transition: color 0.25s ease;
    }
    .attribution {
      font-size: 0.8125rem;
      color: var(--muted);
      line-height: 1.35;
      transition: opacity 0.25s ease;
    }
    .attribution a {
      color: inherit;
      text-decoration: none;
      transition: color 0.15s;
    }
    .attribution a:hover {
      color: var(--fg);
      text-decoration: underline;
    }
    ul.items input[type="checkbox"]:checked ~ .content .text {
      text-decoration: line-through;
      color: var(--muted);
    }
    ul.items input[type="checkbox"]:checked ~ .content .attribution {
      opacity: 0.55;
    }
    .text[contenteditable="true"] {
      outline: 2px solid var(--accent);
      border-radius: 4px;
      padding: 0 0.25rem;
      margin: -0.1rem 0;
      background: var(--bg);
      cursor: text;
    }
    .actions {
      display: inline-flex;
      gap: 0.1rem;
      align-items: flex-start;
      flex-shrink: 0;
      opacity: 0.25;
      transition: opacity 0.18s ease;
    }
    ul.items li:hover .actions,
    ul.items li:focus-within .actions { opacity: 1; }
    @media (hover: none) { .actions { opacity: 0.55; } }
    .actions button {
      background: transparent;
      border: none;
      color: var(--muted);
      cursor: pointer;
      font-size: 0.95rem;
      padding: 0.2rem 0.4rem;
      line-height: 1;
      border-radius: 4px;
      transition: color 0.15s, background 0.15s;
    }
    .actions button:hover { color: var(--fg); background: var(--rule); }
    @keyframes item-fade-in {
      from { opacity: 0; transform: translateY(-3px); }
      to { opacity: 1; transform: translateY(0); }
    }
    @keyframes item-fade-out {
      from { opacity: 1; max-height: 200px; padding-top: 0.7rem; padding-bottom: 0.7rem; }
      to { opacity: 0; max-height: 0; padding-top: 0; padding-bottom: 0; transform: translateX(-6px); }
    }
    @media (prefers-reduced-motion: reduce) {
      *, *::before, *::after {
        animation-duration: 0.01ms !important;
        transition-duration: 0.01ms !important;
      }
    }
    .add-form { display: flex; gap: 0.5rem; margin-top: 0.75rem; }
    .add-form input {
      flex: 1;
      padding: 0.5rem 0.75rem;
      font: inherit;
      color: var(--fg);
      background: transparent;
      border: 1px solid var(--rule);
      border-radius: 6px;
    }
    .add-form input:focus { outline: none; border-color: var(--accent); }
    .add-form button {
      padding: 0.5rem 0.9rem;
      font: inherit;
      color: var(--bg);
      background: var(--accent);
      border: none;
      border-radius: 6px;
      cursor: pointer;
    }
    .import-block {
      margin-top: 0.75rem;
      font-size: 0.9rem;
      color: var(--muted);
    }
    .import-block summary {
      cursor: pointer;
      padding: 0.35rem 0;
      list-style: none;
      user-select: none;
      display: inline-flex;
      align-items: center;
      gap: 0.4rem;
      transition: color 0.15s;
    }
    .import-block summary::-webkit-details-marker { display: none; }
    .import-block summary::before {
      content: '▸';
      font-size: 0.75rem;
      transition: transform 0.15s ease;
      display: inline-block;
    }
    .import-block[open] summary::before { transform: rotate(90deg); }
    .import-block summary:hover { color: var(--fg); }
    .import-form {
      display: flex;
      flex-direction: column;
      gap: 0.5rem;
      margin-top: 0.4rem;
    }
    .import-form textarea {
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      font-size: 0.82rem;
      padding: 0.55rem 0.75rem;
      color: var(--fg);
      background: transparent;
      border: 1px solid var(--rule);
      border-radius: 6px;
      resize: vertical;
      min-height: 5rem;
      line-height: 1.4;
    }
    .import-form textarea:focus { outline: none; border-color: var(--accent); }
    .import-actions { display: flex; align-items: center; gap: 0.75rem; }
    .import-actions button {
      padding: 0.4rem 0.85rem;
      font: inherit;
      font-size: 0.9rem;
      color: var(--bg);
      background: var(--accent);
      border: none;
      border-radius: 6px;
      cursor: pointer;
    }
    .import-status { font-size: 0.85rem; color: var(--muted); }
    .import-status.error { color: #e07070; }
    .deleted-summary { margin-top: 1rem; font-size: 0.85rem; color: var(--muted); }
    .deleted-summary[hidden] { display: none; }
    .deleted-summary button {
      background: transparent;
      border: none;
      color: var(--muted);
      cursor: pointer;
      text-decoration: underline;
      padding: 0;
      font: inherit;
    }
    .deleted-summary button:hover { color: var(--fg); }
    .reset {
      margin-top: 2rem;
      padding: 0.5rem 0.75rem;
      background: transparent;
      color: var(--muted);
      border: 1px solid var(--rule);
      border-radius: 6px;
      cursor: pointer;
      font: inherit;
    }
    .reset:hover { color: var(--fg); border-color: var(--fg); }
  </style>
</head>
<body class="hide-attribution">
  <h1>Grocery List</h1>
  <div class="meta">
    <p><strong>Generated:</strong> <ISO 8601 datetime></p>
    <p><strong>For:</strong></p>
    <ul class="recipes">
      <li><a href="<source url 1>" target="_blank" rel="noopener"><Recipe 1 title></a> · <a class="archive-inline" href="<archive_url 1>" target="_blank" rel="noopener">archive ↗</a></li>
      <li><a href="<source url 2>" target="_blank" rel="noopener"><Recipe 2 title></a> · <a class="archive-inline" href="<archive_url 2>" target="_blank" rel="noopener">archive ↗</a></li>
    </ul>
  </div>

  <div class="progress" aria-live="polite">
    <div class="progress-info">
      <span><strong class="checked-count">0</strong> / <strong class="total-count">0</strong> picked up</span>
      <div class="controls">
        <button class="toggle-attr" type="button" aria-pressed="false">Show recipes</button>
        <button class="toggle-hide" type="button" aria-pressed="false">Hide picked up</button>
      </div>
    </div>
    <div class="progress-bar"><div class="progress-bar-fill"></div></div>
  </div>

  <h2>Shopping List</h2>
  <ul class="items">
    <li data-id="b-0">
      <input type="checkbox">
      <div class="content">
        <span class="text"><ingredient text></span>
        <div class="attribution"><a href="<source url for the contributing recipe>" target="_blank" rel="noopener"><Recipe title></a></div>
      </div>
      <span class="actions"><button class="edit" type="button" aria-label="Edit">✎</button><button class="delete" type="button" aria-label="Delete">×</button></span>
    </li>
    <li data-id="b-1">
      <input type="checkbox">
      <div class="content">
        <span class="text"><another ingredient — alphabetically next></span>
        <div class="attribution"><a href="<source url A>" target="_blank" rel="noopener"><Recipe A></a> · <a href="<source url B>" target="_blank" rel="noopener"><Recipe B></a></div>
      </div>
      <span class="actions"><button class="edit" type="button" aria-label="Edit">✎</button><button class="delete" type="button" aria-label="Delete">×</button></span>
    </li>
  </ul>

  <h3>For Serving</h3>
  <ul class="items">
    <li data-id="b-2">
      <input type="checkbox">
      <div class="content">
        <span class="text"><serving item text></span>
        <div class="attribution"><a href="<source url>" target="_blank" rel="noopener"><Recipe title></a></div>
      </div>
      <span class="actions"><button class="edit" type="button" aria-label="Edit">✎</button><button class="delete" type="button" aria-label="Delete">×</button></span>
    </li>
  </ul>

  <h2>Custom</h2>
  <ul class="items custom-items"></ul>
  <form class="add-form">
    <input type="text" placeholder="Add an item" autocomplete="off">
    <button type="submit">Add</button>
  </form>

  <details class="import-block">
    <summary>Advanced — bulk import JSON</summary>
    <form class="import-form">
      <textarea placeholder='Paste a JSON array of items, e.g. ["milk","bread","eggs"] or [{"text":"milk"},{"text":"eggs","checked":true}]' rows="4" autocomplete="off" spellcheck="false"></textarea>
      <div class="import-actions">
        <button type="submit">Import</button>
        <span class="import-status" aria-live="polite"></span>
      </div>
    </form>
  </details>

  <div class="deleted-summary" hidden>
    <button type="button" class="restore-deleted">Restore <span class="count">0</span> deleted item(s)</button>
  </div>

  <button class="reset" type="button">Reset all changes</button>

  <script>
    const KEY = 'grocery-list-<unix-timestamp>';
    const defaults = { checked: {}, edits: {}, deleted: [], added: [] };
    let state;
    try { state = Object.assign({}, defaults, JSON.parse(localStorage.getItem(KEY) || '{}')); }
    catch (e) { state = Object.assign({}, defaults); }
    state.checked = state.checked || {};
    state.edits = state.edits || {};
    state.deleted = state.deleted || [];
    state.added = state.added || [];
    state.prefs = state.prefs || {};
    if (typeof state.prefs.showAttribution !== 'boolean') state.prefs.showAttribution = false;
    if (typeof state.prefs.hideChecked !== 'boolean') state.prefs.hideChecked = false;

    const save = () => localStorage.setItem(KEY, JSON.stringify(state));
    const customList = document.querySelector('.custom-items');
    const deletedSummary = document.querySelector('.deleted-summary');
    const deletedCountEl = deletedSummary.querySelector('.count');
    const totalCountEl = document.querySelector('.total-count');
    const checkedCountEl = document.querySelector('.checked-count');
    const progressFill = document.querySelector('.progress-bar-fill');
    const toggleHideBtn = document.querySelector('.toggle-hide');
    const toggleAttrBtn = document.querySelector('.toggle-attr');

    function makeItem(item) {
      const li = document.createElement('li');
      li.dataset.id = item.id;
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      if (item.checked) cb.checked = true;
      const content = document.createElement('div');
      content.className = 'content';
      const text = document.createElement('span');
      text.className = 'text';
      text.textContent = item.text;
      content.appendChild(text);
      const actions = document.createElement('span');
      actions.className = 'actions';
      actions.innerHTML = '<button class="edit" type="button" aria-label="Edit">✎</button><button class="delete" type="button" aria-label="Delete">×</button>';
      li.append(cb, content, actions);
      return li;
    }

    function updateDeletedSummary() {
      const n = state.deleted.length;
      deletedSummary.hidden = (n === 0);
      deletedCountEl.textContent = n;
    }

    function updateCounter() {
      const visible = document.querySelectorAll('ul.items li:not([hidden]):not(.exiting)');
      let checked = 0;
      visible.forEach(li => {
        const cb = li.querySelector('input[type="checkbox"]');
        if (cb && cb.checked) checked++;
      });
      totalCountEl.textContent = visible.length;
      checkedCountEl.textContent = checked;
      const pct = visible.length > 0 ? (checked / visible.length) * 100 : 0;
      progressFill.style.width = pct + '%';
    }

    document.querySelectorAll('li[data-id^="b-"]').forEach(li => {
      const id = li.dataset.id;
      if (state.deleted.includes(id)) li.hidden = true;
      const cb = li.querySelector('input[type="checkbox"]');
      if (cb && state.checked[id]) cb.checked = true;
      const text = li.querySelector('.text');
      if (text && state.edits[id] !== undefined) text.textContent = state.edits[id];
    });
    state.added.forEach(item => customList.appendChild(makeItem(item)));
    updateDeletedSummary();
    updateCounter();

    // Apply persisted UI prefs
    if (state.prefs.showAttribution) {
      document.body.classList.remove('hide-attribution');
      toggleAttrBtn.setAttribute('aria-pressed', 'true');
      toggleAttrBtn.textContent = 'Hide recipes';
    }
    if (state.prefs.hideChecked) {
      document.body.classList.add('hide-checked');
      toggleHideBtn.setAttribute('aria-pressed', 'true');
      toggleHideBtn.textContent = 'Show all';
    }

    document.addEventListener('change', e => {
      if (!e.target.matches('input[type="checkbox"]')) return;
      const li = e.target.closest('li[data-id]');
      if (!li) return;
      const id = li.dataset.id;
      const found = state.added.find(a => a.id === id);
      if (found) found.checked = e.target.checked;
      else if (e.target.checked) state.checked[id] = true;
      else delete state.checked[id];
      save();
      updateCounter();
    });

    document.addEventListener('click', e => {
      if (e.target.closest('.edit')) {
        const li = e.target.closest('li[data-id]');
        const text = li && li.querySelector('.text');
        if (!text) return;
        text.contentEditable = 'true';
        text.dataset.original = text.textContent;
        text.focus();
        const r = document.createRange(); r.selectNodeContents(text);
        const s = window.getSelection(); s.removeAllRanges(); s.addRange(r);
        return;
      }
      if (e.target.closest('.delete')) {
        const li = e.target.closest('li[data-id]');
        if (!li) return;
        const id = li.dataset.id;
        const isCustom = !!state.added.find(a => a.id === id);
        if (isCustom) state.added = state.added.filter(a => a.id !== id);
        else if (!state.deleted.includes(id)) state.deleted.push(id);
        li.classList.add('exiting');
        save(); updateDeletedSummary(); updateCounter();
        setTimeout(() => {
          if (isCustom) li.remove();
          else { li.hidden = true; li.classList.remove('exiting'); }
        }, 200);
        return;
      }
      if (e.target.closest('.restore-deleted')) {
        document.querySelectorAll('li[data-id^="b-"]').forEach(li => {
          if (state.deleted.includes(li.dataset.id)) li.hidden = false;
        });
        state.deleted = [];
        save(); updateDeletedSummary(); updateCounter();
        return;
      }

      // Row click toggles checkbox — but skip clicks on actions, links, edit-mode text, or the checkbox itself
      const li = e.target.closest('ul.items li');
      if (!li) return;
      if (e.target.closest('.actions') ||
          e.target.closest('.attribution a') ||
          e.target.matches('.text[contenteditable="true"]') ||
          e.target.matches('input[type="checkbox"]')) {
        return;
      }
      const cb = li.querySelector('input[type="checkbox"]');
      if (cb) cb.click();
    });

    document.addEventListener('blur', e => {
      if (!e.target.matches('.text[contenteditable="true"]')) return;
      e.target.contentEditable = 'false';
      const li = e.target.closest('li[data-id]');
      if (!li) return;
      const id = li.dataset.id;
      const newText = e.target.textContent.trim();
      const original = e.target.dataset.original || '';
      const found = state.added.find(a => a.id === id);
      if (found) {
        if (!newText) { state.added = state.added.filter(a => a.id !== id); li.remove(); updateCounter(); }
        else { found.text = newText; e.target.textContent = newText; }
      } else {
        if (!newText) { e.target.textContent = original; delete state.edits[id]; }
        else if (newText !== original) state.edits[id] = newText;
        else delete state.edits[id];
      }
      save();
    }, true);

    document.addEventListener('keydown', e => {
      if (!e.target.matches('.text[contenteditable="true"]')) return;
      if (e.key === 'Enter') { e.preventDefault(); e.target.blur(); }
      else if (e.key === 'Escape') {
        e.preventDefault();
        e.target.textContent = e.target.dataset.original || e.target.textContent;
        e.target.blur();
      }
    });

    document.querySelector('.add-form').addEventListener('submit', e => {
      e.preventDefault();
      const input = e.target.querySelector('input');
      const text = input.value.trim();
      if (!text) return;
      const item = { id: 'c-' + Date.now() + '-' + Math.random().toString(36).slice(2, 6), text, checked: false };
      state.added.push(item);
      customList.appendChild(makeItem(item));
      save();
      updateCounter();
      input.value = '';
      input.focus();
    });

    document.querySelector('.import-form').addEventListener('submit', e => {
      e.preventDefault();
      const ta = e.target.querySelector('textarea');
      const status = e.target.querySelector('.import-status');
      const setStatus = (msg, isError) => {
        status.textContent = msg;
        status.classList.toggle('error', !!isError);
      };
      const raw = ta.value.trim();
      if (!raw) { setStatus('Paste JSON first', true); return; }
      let parsed;
      try { parsed = JSON.parse(raw); }
      catch (err) { setStatus('Invalid JSON: ' + err.message, true); return; }
      let arr;
      if (Array.isArray(parsed)) arr = parsed;
      else if (parsed && Array.isArray(parsed.items)) arr = parsed.items;
      else { setStatus('Expected an array or {"items": [...]}', true); return; }
      let count = 0, skipped = 0;
      arr.forEach((entry, i) => {
        let text, checked = false;
        if (typeof entry === 'string') text = entry.trim();
        else if (entry && typeof entry === 'object' && typeof entry.text === 'string') {
          text = entry.text.trim();
          checked = !!entry.checked;
        }
        if (!text) { skipped++; return; }
        const id = 'c-' + Date.now() + '-' + Math.random().toString(36).slice(2, 6) + '-' + i;
        const item = { id, text, checked };
        state.added.push(item);
        customList.appendChild(makeItem(item));
        count++;
      });
      if (count === 0) { setStatus('No valid items found', true); return; }
      save();
      updateCounter();
      ta.value = '';
      setStatus(`Imported ${count} item${count === 1 ? '' : 's'}` + (skipped ? ` (skipped ${skipped})` : ''), false);
    });

    toggleHideBtn.addEventListener('click', () => {
      const nowOn = !(toggleHideBtn.getAttribute('aria-pressed') === 'true');
      toggleHideBtn.setAttribute('aria-pressed', String(nowOn));
      document.body.classList.toggle('hide-checked', nowOn);
      toggleHideBtn.textContent = nowOn ? 'Show all' : 'Hide picked up';
      state.prefs.hideChecked = nowOn;
      save();
    });

    toggleAttrBtn.addEventListener('click', () => {
      const nowHidden = document.body.classList.toggle('hide-attribution');
      const showing = !nowHidden;
      toggleAttrBtn.setAttribute('aria-pressed', String(showing));
      toggleAttrBtn.textContent = showing ? 'Hide recipes' : 'Show recipes';
      state.prefs.showAttribution = showing;
      save();
    });

    document.querySelector('.reset').addEventListener('click', () => {
      if (confirm('Clear all local changes (checks, edits, additions, deletions)?')) {
        localStorage.removeItem(KEY);
        location.reload();
      }
    });
  </script>
</body>
</html>
```

**State shape stored at `localStorage.getItem(KEY)`:**

```json
{
  "checked": { "b-0": true, "c-1234": true },
  "edits":   { "b-2": "edited text" },
  "deleted": ["b-3", "b-7"],
  "added":   [{ "id": "c-1234", "text": "milk", "checked": true }],
  "prefs":   { "showAttribution": false, "hideChecked": false }
}
```

`prefs.showAttribution` defaults to `false` — recipe attribution is hidden by default; the wife's view. The "Show recipes" toggle in the sticky header flips it. `prefs.hideChecked` mirrors the "Hide picked up" toggle. Both persist per-device.

The `KEY` uses the unix timestamp so each generated list has its own localStorage namespace. Each device opens the same file with its own state — no cross-device sync, which is the right default.

**Stable `data-id` assignment is critical.**
- Baseline (recipe-derived) items use `b-<n>` where `<n>` is sequential **across all sections in the file** (every `<li>` in every `<ul class="items">` — Shopping List first, then For Serving), starting at `b-0` and counting upward in document order. Don't restart numbering per section — a single counter for the whole file. The localStorage state references these IDs, so the order of items must match exactly between renders.
- Custom items get IDs of the form `c-<timestamp>-<random>` generated by the JS at add-time. The skill never has to mint these.

**Aggregation and attribution rules:**
- Pool every YAML `items[]` entry whose `section: null` into the **Shopping List** section, sorted alphabetically by `text` (case-insensitive).
- Pool every YAML entry whose `section` is non-null (e.g., `"For Serving"`) into the **For Serving** section, same alphabetical ordering.
- **Exact-text aggregation across recipes:** if two YAML items have identical `text` from different recipes (e.g., both recipes literally write `"1 tablespoon olive oil"`), render ONE row with multiple links in its attribution line. Pick the lower-numbered `b-<n>` as the row's `data-id`; the other YAML entry's id doesn't get its own DOM node. Different `text` (even if it's effectively the same ingredient) = two separate rows.
- **Attribution is a typographic line, not a pill.** Each row's `<div class="attribution">` is rendered as muted secondary text below the ingredient — no badges, no chrome. Recipe names are inline links (`<a href="<source url>">`) joined by ` · ` when multiple. Tap a name to open the source in a new tab.
- **For Serving** items don't get an inline section label — the `<h3>For Serving</h3>` heading already tells the reader what they are. The attribution line is just the recipe link(s).
- **Custom items** (added at runtime via the add form) have NO attribution line — they live under the `<h2>Custom</h2>` heading and have no source recipe. The JS `makeItem()` produces an item with just `<input>` + `.content > .text` + `.actions`, no `.attribution`.

**UX behaviors baked into the template:**
- **Tap anywhere on a row** (except the action buttons or recipe-link in the attribution) toggles the checkbox. Implemented via a delegated click handler at the bottom of the main click listener — clicks on `.actions`, `.attribution a`, `.text[contenteditable="true"]`, or the checkbox itself are skipped.
- **Smooth animations.** Items fade in on initial render and on add (via `@keyframes item-fade-in`). Items fade out and collapse on delete (via `.exiting` class + `@keyframes item-fade-out`, with a 200 ms `setTimeout` to defer `hidden = true` / `remove()`). Strikethrough fades in via a `color` transition on `.text`. The progress bar fill animates smoothly via `transition: width`. All animations respect `prefers-reduced-motion` (a global `@media` rule clamps durations to 0.01ms).
- **Hairline list, not cards.** Items have no border / no background; just a 1px bottom separator and a subtle hover/active background tint. Visual hierarchy comes from spacing and contrast, not chrome.

If you regenerate the same list with the same timestamp later, the IDs stay aligned and prior state still applies.

**Reset all changes** discards the entire localStorage entry for this list. Custom items, edits, and the deleted set all go.

**Recipe titles are pressable links.** Each `<h2>` wraps the recipe title in an `<a>` to the original source URL. The "For:" list at the top also links each recipe to its source. Beside each `<h2>` title, a subtle GitHub-mark icon links to the archived `index.html` snapshot in the project's GitHub repo — `currentColor` plus reduced opacity keeps it minimal; hover brightens it.

**If `archive_url` is null for a recipe** (no GitHub remote, or the remote isn't on github.com), omit the entire `<a class="archive-link">...</a>` element for that recipe — don't render `href="null"` or `href=""`. The title and source link still render normally.

### Step 7: Write the YAML file and copy the schema

Write the structured form to `<BUNDLE>/grocery-list.<unix-timestamp>.yaml` with the same `<unix-timestamp>` as the other files.

**Also copy the schema** from the project (`bin/schemas/grocery-list.schema.json`) to `<BUNDLE>/grocery-list.schema.json`. The YAML's relative `$schema=./grocery-list.schema.json` reference resolves to this sibling file inside the staging directory and continues to resolve after extraction, since both files travel together in the tarball.

The YAML's first line MUST be the schema-reference comment using a relative path:

```yaml
# yaml-language-server: $schema=./grocery-list.schema.json
generated: <ISO 8601 datetime, local time zone, with offset>
unix_timestamp: <unix-timestamp as integer>
recipes:
  - title: <Recipe 1 title>
    slug: <Recipe 1 directory name, e.g. Bowties-and-Broccoli>
    url: <Recipe 1 source URL>
    archive_url: <Recipe 1 GitHub blob URL, or null if no GitHub remote>
  - title: <Recipe 2 title>
    slug: <Recipe 2 directory name>
    url: <Recipe 2 source URL>
    archive_url: <Recipe 2 GitHub blob URL, or null if no GitHub remote>
items:
  - recipe: <Recipe 1 title>
    section: null
    text: "<ingredient 1 verbatim>"
  - recipe: <Recipe 1 title>
    section: null
    text: "<ingredient 2 verbatim>"
  - recipe: <Recipe 1 title>
    section: For Serving
    text: "<serving item 1>"
  - recipe: <Recipe 2 title>
    section: null
    text: "<ingredient 1 verbatim>"
```

YAML rules:
- **Use YAML `null` for the default/main section**, the literal string `"For Serving"` (or whatever the source uses) for named subsections.
- **`text` is verbatim** — measurements, units, prep notes preserved from the recipe's `recipe.yaml`. Don't deduplicate across recipes; if two recipes both call for butter, both rows appear.
- **`unix_timestamp` is an integer** (no quotes), matches the value used in the filename.
- **`recipes[].slug`** is the Title-Case-Kebab directory name, useful for downstream tools to look up the source recipe's full data.
- **`recipes[].url`** is the source URL pulled from the recipe's `recipe.yaml`. **`recipes[].archive_url`** is the GitHub blob URL for the archived `index.html`, or YAML `null` when no GitHub remote is available. Both fields are required by the schema; null is the only valid sentinel for missing archive_url.
- **Quote strings that contain special YAML characters** (`:`, leading `-`, leading `*`, etc.). When in doubt, quote.

The schema (`bin/schemas/grocery-list.schema.json`) sets `additionalProperties: false` everywhere — don't add fields the schema doesn't define.

### Step 8: Bundle into ~/Documents/ tar.gz and clean up

Resolve `~` to the user's home directory. Tar the staging subdirectory into `<HOME>/Documents/grocery-list.<unix-timestamp>.tar.gz`, then remove the temp directory so nothing is left behind:

```bash
tar -czf "$HOME/Documents/grocery-list.$TS.tar.gz" -C "$TMP" "grocery-list.$TS"
rm -rf "$TMP"
```

The `-C "$TMP"` flag changes tar's working directory before reading files, so the archive contains a clean top-level `grocery-list.<ts>/` directory rather than the temp path.

Final tarball layout (single top-level directory so extraction is tidy and self-contained):

```
grocery-list.<unix-timestamp>/
  grocery-list.<unix-timestamp>.md
  grocery-list.<unix-timestamp>.html
  grocery-list.<unix-timestamp>.yaml
  grocery-list.schema.json
```

The bundle is self-validating: a recipient extracts it and the YAML's relative `$schema=./grocery-list.schema.json` reference resolves to the included schema with no dependency on this machine or this repo.

`~/Documents/` ends up with only the `grocery-list.<ts>.tar.gz` — no loose files, no leftover temp dirs.

### Step 9: Confirm

Tell the user the absolute path of the tar.gz file plus a one-line summary (e.g., "23 items across 2 recipes — extract the tarball to get the markdown, HTML, YAML, and schema").

## Notes

- This skill writes outside the project (`~/Documents/`). That's intentional — grocery lists are personal artifacts, not repo content.
- If the user picks a recipe whose YAML is missing or malformed, surface the issue and ask whether to skip it or proceed with the README's ingredient list (which is also verbatim, just less structured).

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

Write to `<BUNDLE>/grocery-list.<unix-timestamp>.md` with this structure:

```markdown
# Grocery List

**Generated:** <ISO 8601 datetime, local time zone>

**For:**
- [<Recipe 1 title>](<source url 1>)
- [<Recipe 2 title>](<source url 2>)

## [<Recipe 1 title>](<source url 1>)
*[offline archive ↗](<archive_url 1>)*

- [ ] <ingredient 1>
- [ ] <ingredient 2>

### For Serving

- [ ] <serving item 1>

## [<Recipe 2 title>](<source url 2>)
*[offline archive ↗](<archive_url 2>)*

- [ ] <ingredient 1>
- [ ] <ingredient 2>
```

Per-recipe section headings make it easy to see which item came from where while shopping. Keep "For Serving" subsections under their parent recipe.

The recipe title is a markdown link to the original source. Below it, a small italic line links to the archived snapshot on GitHub. **If `archive_url` is null** (no GitHub remote), omit the entire italic line for that recipe — don't render `[offline archive](null)`.

### Step 6: Write the HTML file

Write a self-contained HTML companion alongside the markdown — same base name, `.html` extension. Path: `<BUNDLE>/grocery-list.<unix-timestamp>.html` (same `<unix-timestamp>` as the markdown file).

Requirements:

- **Fully self-contained.** No external CSS, no external JS, no external fonts, no images. The user shares the file directly (over Messages/email/AirDrop), so it must work offline with zero network access.
- **Mobile-friendly.** Includes the viewport meta tag and is comfortable on a phone screen.
- **Dark-mode aware** via `@media (prefers-color-scheme: dark)`.
- **Interactive checkboxes.** Each ingredient is a real `<input type="checkbox">` (not a disabled markdown checkbox). Tapping toggles checked state.
- **Per-device persistence via `localStorage`** for the full list state — checks, edits, deletions, and added items. Each device gets its own independent state.
- **Add custom items.** A form at the bottom lets the user type new items mid-shop; they appear under a "Custom" section and persist.
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
    h2 a { color: inherit; text-decoration: none; }
    h2 a:hover { text-decoration: underline; }
    h3 { font-size: 1rem; margin: 1rem 0 0.25rem; color: var(--muted); }
    .recipes a { color: inherit; }
    .archive-link {
      display: inline-flex;
      align-items: center;
      margin-left: 0.4rem;
      color: var(--muted);
      opacity: 0.55;
      transition: opacity 0.15s;
      vertical-align: middle;
    }
    .archive-link:hover { opacity: 1; }
    .archive-link svg { display: block; }
    .meta { color: var(--muted); font-size: 0.9rem; margin-bottom: 1rem; }
    .meta strong { color: var(--fg); }
    ul.recipes { padding-left: 1.25rem; margin: 0.25rem 0 1rem; }
    ul.items { list-style: none; padding: 0; margin: 0; }
    ul.items li {
      display: flex;
      align-items: flex-start;
      gap: 0.6rem;
      padding: 0.5rem 0;
      border-bottom: 1px solid var(--rule);
    }
    ul.items li[hidden] { display: none; }
    ul.items input[type="checkbox"] {
      width: 1.25rem;
      height: 1.25rem;
      margin: 0.15rem 0 0;
      flex-shrink: 0;
      accent-color: var(--accent);
      cursor: pointer;
    }
    ul.items .text {
      flex: 1;
      user-select: text;
      word-break: break-word;
    }
    ul.items input[type="checkbox"]:checked ~ .text {
      text-decoration: line-through;
      color: var(--muted);
    }
    .text[contenteditable="true"] {
      outline: 2px solid var(--accent);
      border-radius: 4px;
      padding: 0 0.25rem;
      margin: -0.1rem 0;
      background: var(--bg);
    }
    .actions {
      display: inline-flex;
      gap: 0.1rem;
      align-items: flex-start;
      flex-shrink: 0;
      opacity: 0.35;
      transition: opacity 0.15s;
    }
    ul.items li:hover .actions,
    ul.items li:focus-within .actions { opacity: 1; }
    @media (hover: none) { .actions { opacity: 0.6; } }
    .actions button {
      background: transparent;
      border: none;
      color: var(--muted);
      cursor: pointer;
      font-size: 0.95rem;
      padding: 0.15rem 0.4rem;
      line-height: 1;
      border-radius: 4px;
    }
    .actions button:hover { color: var(--fg); background: var(--rule); }
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
<body>
  <h1>Grocery List</h1>
  <div class="meta">
    <p><strong>Generated:</strong> <ISO 8601 datetime></p>
    <p><strong>For:</strong></p>
    <ul class="recipes">
      <li><a href="<source url 1>" target="_blank" rel="noopener"><Recipe 1 title></a></li>
      <li><a href="<source url 2>" target="_blank" rel="noopener"><Recipe 2 title></a></li>
    </ul>
  </div>

  <h2>
    <a href="<source url 1>" target="_blank" rel="noopener"><Recipe 1 title></a>
    <a class="archive-link" href="<archive_url 1>" target="_blank" rel="noopener" title="Offline archive on GitHub" aria-label="Offline archive on GitHub">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z"/></svg>
    </a>
  </h2>
  <ul class="items">
    <li data-id="b-0"><input type="checkbox"><span class="text"><ingredient 1></span><span class="actions"><button class="edit" type="button" aria-label="Edit">✎</button><button class="delete" type="button" aria-label="Delete">×</button></span></li>
    <li data-id="b-1"><input type="checkbox"><span class="text"><ingredient 2></span><span class="actions"><button class="edit" type="button" aria-label="Edit">✎</button><button class="delete" type="button" aria-label="Delete">×</button></span></li>
  </ul>

  <h3>For Serving</h3>
  <ul class="items">
    <li data-id="b-2"><input type="checkbox"><span class="text"><serving item 1></span><span class="actions"><button class="edit" type="button" aria-label="Edit">✎</button><button class="delete" type="button" aria-label="Delete">×</button></span></li>
  </ul>

  <h2>
    <a href="<source url 2>" target="_blank" rel="noopener"><Recipe 2 title></a>
    <a class="archive-link" href="<archive_url 2>" target="_blank" rel="noopener" title="Offline archive on GitHub" aria-label="Offline archive on GitHub">
      <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0 0 16 8c0-4.42-3.58-8-8-8z"/></svg>
    </a>
  </h2>
  <ul class="items">
    <li data-id="b-3"><input type="checkbox"><span class="text"><ingredient 1></span><span class="actions"><button class="edit" type="button" aria-label="Edit">✎</button><button class="delete" type="button" aria-label="Delete">×</button></span></li>
  </ul>

  <h2>Custom</h2>
  <ul class="items custom-items"></ul>
  <form class="add-form">
    <input type="text" placeholder="Add an item" autocomplete="off">
    <button type="submit">Add</button>
  </form>

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

    const save = () => localStorage.setItem(KEY, JSON.stringify(state));
    const customList = document.querySelector('.custom-items');
    const deletedSummary = document.querySelector('.deleted-summary');
    const deletedCountEl = deletedSummary.querySelector('.count');

    function makeItem(item) {
      const li = document.createElement('li');
      li.dataset.id = item.id;
      const cb = document.createElement('input');
      cb.type = 'checkbox';
      if (item.checked) cb.checked = true;
      const text = document.createElement('span');
      text.className = 'text';
      text.textContent = item.text;
      const actions = document.createElement('span');
      actions.className = 'actions';
      actions.innerHTML = '<button class="edit" type="button" aria-label="Edit">✎</button><button class="delete" type="button" aria-label="Delete">×</button>';
      li.append(cb, text, actions);
      return li;
    }

    function updateDeletedSummary() {
      const n = state.deleted.length;
      deletedSummary.hidden = (n === 0);
      deletedCountEl.textContent = n;
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
        if (state.added.find(a => a.id === id)) {
          state.added = state.added.filter(a => a.id !== id);
          li.remove();
        } else {
          if (!state.deleted.includes(id)) state.deleted.push(id);
          li.hidden = true;
        }
        save(); updateDeletedSummary();
        return;
      }
      if (e.target.closest('.restore-deleted')) {
        document.querySelectorAll('li[data-id^="b-"]').forEach(li => {
          if (state.deleted.includes(li.dataset.id)) li.hidden = false;
        });
        state.deleted = [];
        save(); updateDeletedSummary();
        return;
      }
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
        if (!newText) { state.added = state.added.filter(a => a.id !== id); li.remove(); }
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
      input.value = '';
      input.focus();
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
  "added":   [{ "id": "c-1234", "text": "milk", "checked": true }]
}
```

The `KEY` uses the unix timestamp so each generated list has its own localStorage namespace. Each device opens the same file with its own state — no cross-device sync, which is the right default.

**Stable `data-id` assignment is critical.**
- Baseline (recipe-derived) items use `b-<n>` where `<n>` is sequential **across all sections in the file** (every `<li>` in every `<ul class="items">`, including "For Serving" subsections), starting at `b-0` and counting upward in document order. Don't restart numbering per section — a single counter for the whole file. The localStorage state references these IDs, so the order of items must match exactly between renders.
- Custom items get IDs of the form `c-<timestamp>-<random>` generated by the JS at add-time. The skill never has to mint these.

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

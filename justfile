set quiet

list:
  claude --dangerously-skip-permissions "/grocery-list"

index:
  claude -p --dangerously-skip-permissions "/recipe-index"

done:
  #!/usr/bin/env bash
  set -euo pipefail

  git add .

  if git diff --cached --quiet; then
    echo "No changes to commit." >&2
    exit 0
  fi

  message="$(claude -p --dangerously-skip-permissions --output-format text "/commit-message" | tr -d '\n' | xargs)"
  if [ -z "$message" ]; then
    echo "commit-message returned empty" >&2
    exit 1
  fi

  git commit -m "$message"
  git push

recipe arg1 arg2='':
  #!/usr/bin/env bash
  set -euo pipefail

  if [ -z "{{arg2}}" ]; then
    url="{{arg1}}"
    name="$(claude -p --dangerously-skip-permissions --output-format text "/recipe-namer $url" | tr -d '\n' | xargs)"
    if [ -z "$name" ]; then
      echo "recipe-namer returned empty name" >&2
      exit 1
    fi
  else
    name="{{arg1}}"
    url="{{arg2}}"
  fi

  rm -rf "recipes/$name"
  mkdir -p "recipes/$name"

  just build "$name" "$url"
  just index

[parallel]
build name url: (monolith name url) (archive name url)

[private]
monolith name url:
  monolith --no-js --no-fonts --isolate {{url}} --output recipes/{{name}}/index.html

[private]
archive name url:
  claude -p --dangerously-skip-permissions "/recipe-archiver {{name}} {{url}}"

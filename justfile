set quiet

done:
  #!/usr/bin/env bash
  git add .
  git commit -m "Updates to recipes"
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

[parallel]
build name url: (monolith name url) (archive name url)

[private]
monolith name url:
  monolith --no-js --no-fonts --isolate {{url}} --output recipes/{{name}}/index.html

[private]
archive name url:
  claude -p --dangerously-skip-permissions "/recipe-archiver {{name}} {{url}}"

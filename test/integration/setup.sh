#!/usr/bin/env bash
# Build the throwaway Factorio environment the integration tier runs in.
#
# The mod under test is mirrored as a directory of symlinks rather than one
# symlink to the repo root: the environment lives inside the repo, so linking
# the whole tree would make the mods directory contain itself.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
here="$root/test/integration"
env_dir="$here/env"
mods="$env_dir/mods"
write_data="$env_dir/write-data"

rm -rf "$mods"
mkdir -p "$mods/automatic-underground-pipe-connectors" "$write_data"

for entry in info.json control.lua lib changelog.txt thumbnail.png; do
    [[ -e "$root/$entry" ]] && ln -sfn "$root/$entry" "$mods/automatic-underground-pipe-connectors/$entry"
done
ln -sfn "$here/aupc-tests" "$mods/aupc-tests"

cat > "$mods/mod-list.json" <<'JSON'
{
  "mods": [
    { "name": "base", "enabled": true },
    { "name": "elevated-rails", "enabled": true },
    { "name": "quality", "enabled": true },
    { "name": "space-age", "enabled": true },
    { "name": "automatic-underground-pipe-connectors", "enabled": true },
    { "name": "aupc-tests", "enabled": true }
  ]
}
JSON

# Muting has to happen here: Factorio has no --disable-audio, and it rewrites
# this file on exit, so a run that turned the sound up leaves it up.
cat > "$env_dir/config.ini" <<INI
[path]
read-data=__PATH__system-read-data__
write-data=$write_data

[general]
locale=en

[sound]
master-volume=0

[graphics]
graphics-quality=medium
video-memory-usage=low
INI

echo "environment ready at $env_dir"

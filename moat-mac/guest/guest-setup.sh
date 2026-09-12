#!/bin/zsh
# Runs inside the VM during `moat-mac create`, with the mailbox mounted at
# ~/mailbox and provisioning files in ~/mailbox/.provision.
set -euo pipefail

PROVISION=~/mailbox/.provision
config() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' \
    "$PROVISION/config.json" "$1"
}
REPO_NAME=$(config repo_name)

# The bundle crossed virtiofs; make sure all of it arrived intact.
EXPECTED_SHA=$(config bundle_sha256)
ACTUAL_SHA=$(python3 -c 'import hashlib, sys
h = hashlib.sha256()
with open(sys.argv[1], "rb") as f:
    for chunk in iter(lambda: f.read(1 << 20), b""):
        h.update(chunk)
print(h.hexdigest())' ~/mailbox/repo.tar)
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "guest-setup: repo.tar checksum mismatch" >&2
  echo "guest-setup:   got $ACTUAL_SHA" >&2
  echo "guest-setup:   expected $EXPECTED_SHA" >&2
  exit 1
fi

echo "guest-setup: installing repo to ~/work/$REPO_NAME"
mkdir -p ~/work
[[ -e ~/work/$REPO_NAME ]] && { echo "guest-setup: ~/work/$REPO_NAME already exists" >&2; exit 1 }
( while :; do sleep 4; echo "guest-setup: still unpacking..."; done ) &
HEARTBEAT=$!
trap 'kill $HEARTBEAT 2>/dev/null' EXIT
tar -xf ~/mailbox/repo.tar -C ~/work
kill $HEARTBEAT 2>/dev/null
trap - EXIT

echo "guest-setup: installing moat-publish and moat-fetch"
mkdir -p ~/.local/bin
cp "$PROVISION/moat-publish" ~/.local/bin/moat-publish
cp "$PROVISION/moat-fetch" ~/.local/bin/moat-fetch
chmod +x ~/.local/bin/moat-publish ~/.local/bin/moat-fetch
cp "$PROVISION/config.json" ~/.moat-mac.json

if [[ -f "$PROVISION/CLAUDE.md" ]]; then
  mkdir -p ~/.claude
  cp "$PROVISION/CLAUDE.md" ~/.claude/CLAUDE.md
fi

# Mark the workspace trusted so claude doesn't ask on first run.
python3 - "$HOME/work/$REPO_NAME" << 'PYEOF'
import json, pathlib, sys
path = pathlib.Path.home() / ".claude.json"
settings = json.loads(path.read_text()) if path.is_file() else {}
project = settings.setdefault("projects", {}).setdefault(sys.argv[1], {})
project["hasTrustDialogAccepted"] = True
path.write_text(json.dumps(settings))
PYEOF

touch "$PROVISION/.complete"
echo "guest-setup: done"

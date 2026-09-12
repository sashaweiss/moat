"""Seeds first-run Claude settings in the VM, run on every session start
(claude rewrites ~/.claude.json, so create-time seeding isn't enough).
Prints the VM's login state for the host.

argv[1]: repo name; argv[2]: settings JSON (guest/claude-settings.json).
"""

import json
import pathlib
import sys

path = pathlib.Path.home() / ".claude.json"
settings = json.loads(path.read_text()) if path.is_file() else {}
settings.update(json.loads(sys.argv[2]))
workspace = str(pathlib.Path.home() / "work" / sys.argv[1])
settings.setdefault("projects", {}).setdefault(workspace, {})[
    "hasTrustDialogAccepted"] = True
path.write_text(json.dumps(settings))
print("logged-in" if settings.get("oauthAccount") else "logged-out")

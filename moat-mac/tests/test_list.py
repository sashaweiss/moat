"""Tests for `moat-mac list` rendering, against a stub tart. No real tart."""
import json, os, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "moat-mac"
fails = []
def check(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    if not cond: fails.append(name)

tmp = Path(tempfile.mkdtemp(prefix="moatmac-list-"))
home = tmp / "moat-home"
stub = tmp / "bin"
stub.mkdir()

# Stub tart: two session VMs plus the base image they were cloned from.
(stub / "tart").write_text("""#!/bin/sh
case "$1" in
  list) echo '[{"Name":"moat-mac-base","Running":false,"State":"stopped"},
               {"Name":"moat-mac-alpha","Running":true,"State":"running"},
               {"Name":"moat-mac-beta","Running":false,"State":"stopped"}]' ;;
  get)
    case "$2" in
      moat-mac-alpha) echo '{"Size":"82.345","Disk":140}' ;;
      moat-mac-beta)  echo '{"Size":"91.007","Disk":140}' ;;
      moat-mac-base)  echo '{"Size":"80.000","Disk":140}' ;;
      *) exit 1 ;;
    esac ;;
esac
""")
os.chmod(stub / "tart", 0o755)


def session(name, repo, branches=()):
    d = home / name
    (d / "mailbox" / "branches").mkdir(parents=True)
    for b in branches:
        (d / "mailbox" / "branches" / b).mkdir()
    (d / "session.json").write_text(json.dumps({
        "name": name, "repo": repo, "repo_name": Path(repo).name,
        "branch": "main", "base_commit": "a" * 40, "created": "x"}))

session("alpha", str(Path.home() / "dev" / "alpha"), ["fix-crash", "experiment"])
session("beta", str(Path.home() / "dev" / "alpha"))       # same repo, second session
session("gamma", "/opt/gamma")                            # no VM -> missing

env = dict(os.environ, MOAT_MAC_HOME=str(home), PATH=f"{stub}:{os.environ['PATH']}")
def run(*args):
    return subprocess.run([sys.executable, str(CLI), "list", *args],
                          env=env, capture_output=True, text=True)

r = run()
print(r.stdout, end="")
lines = r.stdout.splitlines()
check("exit 0", r.returncode == 0)
check("header order", lines[0].split() == ["SESSION", "STATE", "REPO", "SIZE"])
check("size is growth over base (82.345 - 80 = 2.3)",
      "2.3 GB" in r.stdout and "11.0 GB" in r.stdout)
check(f"base row is first, size only: {lines[1]}",
      lines[1].split() == ["<base-vm>", "-", "-", "80.0", "GB"])
check("missing VM shows dash",
      any(l.split() == ["gamma", "missing", "/opt/gamma", "-"] for l in lines))
check("repo tilde-abbreviated", "~/dev/alpha" in r.stdout)
check("same repo repeats across sessions", r.stdout.count("~/dev/alpha") == 2)
check("branches not shown", "fix-crash" not in r.stdout)
check("no trailing whitespace", all(l == l.rstrip() for l in lines))

r = run("--json")
rows = json.loads(r.stdout)
by_name = {row["name"]: row for row in rows}
check("json size_gb is growth", round(by_name["alpha"]["size_gb"], 3) == 2.345)
check("json size_gb null when VM missing", by_name["gamma"]["size_gb"] is None)
check("json has no branches key", "branches" not in by_name["alpha"])

import shutil; shutil.rmtree(tmp)
print("\n%d failures" % len(fails))
sys.exit(1 if fails else 0)

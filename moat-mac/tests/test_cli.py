"""Tests for moat-mac patch validation and the publish/pull/share loop.
Drives the real guest moat-publish against a fake $HOME. Needs git; no tart."""
import importlib.util, json, os, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "moat-mac"
PUBLISH = ROOT / "guest" / "moat-publish"
spec = importlib.util.spec_from_loader("moatmac", loader=None)
mod = importlib.util.module_from_spec(spec)
exec(compile(CLI.read_text(), str(CLI), "exec"), mod.__dict__)

V = mod.validate_patch_file
fails = []
def check(name, cond):
    print(("PASS" if cond else "FAIL"), name)
    if not cond: fails.append(name)

def expect_reject(name, content, mode=0o644, symlink=False):
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "0001.patch"
        if symlink:
            real = Path(d) / "real"; real.write_bytes(content); p.symlink_to(real)
        else:
            p.write_bytes(content); os.chmod(p, mode)
        try:
            V(p); check(name, False)
        except ValueError as e:
            check(f"{name} ({e})", True)

def expect_accept(name, content):
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "0001.patch"
        p.write_bytes(content); os.chmod(p, 0o644)
        try:
            V(p); check(name, True)
        except ValueError as e:
            check(f"{name} ({e})", False)

GOOD = b"diff --git a/f.txt b/f.txt\n--- a/f.txt\n+++ b/f.txt\n@@ -1 +1 @@\n-old\n+new\n"
expect_accept("plain ascii patch", GOOD)
expect_reject("empty", b"")
expect_reject("invalid utf-8", b"+\xff\xfe\n")
expect_accept("non-ascii allowed", "+héllo \u2014 \u2013 \U0001F600\n".encode())
expect_reject("bidi override", "+a‮b\n".encode())
expect_reject("c1 control", "+a\u009bb\n".encode())
expect_reject("bidi isolate", "+a\u2068b\u2069\n".encode())
expect_reject("zero-width space", "+a\u200bb\n".encode())
expect_reject("byte order mark", "+\ufeffa\n".encode())
expect_reject("tag character", "+a\U000E0041b\n".encode())
expect_reject("private use", "+a\ue000b\n".encode())
expect_reject("unassigned", "+a\u0378b\n".encode())
expect_accept("non-breaking and ideographic spaces", "+a\u00a0b\u3000c\n".encode())
expect_accept("zero-width joiner emoji", "+\U0001F469\u200d\U0001F4BB\n".encode())
expect_reject("carriage return", b"+a\r\n")
expect_reject("escape char", b"+a\x1b[31m\n")
expect_reject("git binary hunk", b"diff --git a/x b/x\nGIT binary patch\nliteral 5\n")
expect_reject("binary-files-differ", b"Binary files a/x and b/x differ\n")
expect_reject("symlink", GOOD, symlink=True)
expect_reject("world-writable", GOOD, mode=0o666)
expect_reject("too large", b"+x\n" * (4 * 1024 * 1024))

# --- e2e: guest publish -> host pull -> local branches ---
tmp = tempfile.mkdtemp(prefix="moatmac-e2e-")
host_env = dict(os.environ, MOAT_MAC_HOME=f"{tmp}/moat-home")
def run(*args, cwd=None, input=None):
    return subprocess.run([sys.executable, str(CLI), *args], env=host_env,
                          capture_output=True, text=True, cwd=cwd, input=input)
def git(repo, *args):
    return subprocess.run(["git", "-C", str(repo), *args],
                          capture_output=True, text=True, check=True)

host = f"{tmp}/host-repo"
os.makedirs(host)
subprocess.run(["git", "init", "-q", "-b", "main", host], check=True)
git(host, "config", "user.email", "t@t"); git(host, "config", "user.name", "t")
Path(host, "a.txt").write_text("hello\n")
git(host, "add", "."); git(host, "commit", "-qm", "init")
base = git(host, "rev-parse", "HEAD").stdout.strip()

s = Path(host_env["MOAT_MAC_HOME"]) / "proj"
(s / "mailbox" / "branches").mkdir(parents=True)
(s / "session.json").write_text(json.dumps({
    "name": "proj", "repo": host, "repo_name": "proj", "branch": "main",
    "base_commit": base, "created": "2026-09-12T00:00:00+00:00"}))

# Guest side: fake $HOME whose mailbox IS the session mailbox.
guest_home = Path(tmp) / "guest-home"
(guest_home / "work").mkdir(parents=True)
(guest_home / ".moat-mac.json").write_text(json.dumps({
    "session": "proj", "repo_name": "proj", "base_commit": base, "branch": "main"}))
os.symlink(s / "mailbox", guest_home / "mailbox")
guest = guest_home / "work" / "proj"
subprocess.run(["git", "clone", "-q", host, str(guest)], check=True)
git(guest, "config", "user.email", "r@r"); git(guest, "config", "user.name", "robot")
guest_env = dict(os.environ, HOME=str(guest_home))
def publish():
    return subprocess.run([sys.executable, str(PUBLISH)], env=guest_env,
                          capture_output=True, text=True)

# Nothing published yet.
r = run("pull", "--session", "proj", input="y\n")
check(f"pull with nothing published: {r.stdout.strip()}",
      r.returncode == 0 and "nothing published" in r.stdout)

# Publish guardrails.
r = publish()
check(f"publish with no commits refused: {r.stderr.strip()}", r.returncode != 0)
git(guest, "switch", "-qc", "moat-mac/proj/fix-crash")
Path(guest, "a.txt").write_text("hello world\n")
r = publish()
check("publish with dirty tree refused", r.returncode != 0)
git(guest, "commit", "-aqm", "fix the crash")

# Publish + pull round trip.
r = publish()
check(f"publish: {r.stdout.strip()} {r.stderr.strip()}", r.returncode == 0)
check("per-commit file exists",
      (s / "mailbox" / "branches" / "fix-crash" / "0001.patch").is_file())
r = run("pull", "--session", "proj", input="n\n")
check("pull declined does nothing", r.returncode != 0
      and subprocess.run(["git", "-C", host, "rev-parse", "--verify", "-q",
                          "moat-mac/proj/fix-crash"]).returncode != 0)
r = run("pull", "--session", "proj", input="y\n")
check(f"pull creates branch: {r.stdout.strip()} {r.stderr.strip()}", r.returncode == 0)
log = git(host, "log", "--format=%s", f"{base}..moat-mac/proj/fix-crash").stdout.splitlines()
check(f"branch commits: {log}", log == ["fix the crash"])

# Idempotent republish; up-to-date pull.
r = publish()
check(f"republish idempotent: {r.stdout.splitlines()[0]}",
      r.returncode == 0 and "0 updated" in r.stdout)
r = run("pull", "--session", "proj", input="y\n")
check("pull up to date", r.returncode == 0 and "up to date" in r.stdout)

# Second branch; pull handles both; shas on first branch stay put.
git(guest, "switch", "-qc", "moat-mac/proj/experiment", base)
Path(guest, "b.txt").write_text("exp\n")
git(guest, "add", "b.txt"); git(guest, "commit", "-qm", "experiment commit")
r = publish()
check("publish second branch", r.returncode == 0)
before = git(host, "rev-list", f"{base}..moat-mac/proj/fix-crash").stdout
r = run("pull", "--session", "proj", input="y\n")
check(f"pull both: {r.stdout.strip()} {r.stderr.strip()}", r.returncode == 0
      and "moat-mac/proj/experiment" in r.stdout)
after = git(host, "rev-list", f"{base}..moat-mac/proj/fix-crash").stdout
check("first branch untouched", before == after)

# Append to a branch.
git(guest, "switch", "-q", "moat-mac/proj/fix-crash")
Path(guest, "c.txt").write_text("more\n")
git(guest, "add", "c.txt"); git(guest, "commit", "-qm", "add regression test")
r = publish()
check("republish appends", r.returncode == 0 and "2 commits, 1 updated" in r.stdout)
r = run("pull", "fix-crash", "--session", "proj", input="y\n")
check(f"single-branch pull advances: {r.stdout.strip()}",
      r.returncode == 0 and "advanced by 1 commit " in r.stdout)

# Rewrite -> divergence error on that branch only; others still pull.
git(guest, "commit", "--amend", "-qm", "add regression test, reworded")
r = publish()
check("publish rewrite", r.returncode == 0)
r = run("pull", "--session", "proj", input="y\n")
check(f"diverged branch refused, other ok:\n{r.stderr.strip()}",
      r.returncode != 0 and "does not match" in r.stderr
      and "experiment" in r.stdout)
# Recovery per the hint.
git(host, "branch", "-f", "moat-mac/proj/fix-crash", base)
r = run("pull", "fix-crash", "--session", "proj", input="y\n")
check("post-reset pull", r.returncode == 0)
log = git(host, "log", "--format=%s", f"{base}..moat-mac/proj/fix-crash").stdout.splitlines()
check("rewritten history landed", log[0] == "add regression test, reworded")

# Shortened branch (mailbox has fewer commits than local) refused.
git(guest, "reset", "-q", "--hard", "HEAD~1")
r = publish()
check("publish shortened branch removes stale file",
      r.returncode == 0 and "1 removed" in r.stdout
      and not (s / "mailbox" / "branches" / "fix-crash" / "0002.patch").exists())
r = run("pull", "fix-crash", "--session", "proj", input="y\n")
check("shortened branch refused", r.returncode != 0 and "has 2 commits but" in r.stderr)

# Merge commits refused at publish.
git(guest, "switch", "-q", "moat-mac/proj/experiment")
git(guest, "merge", "-q", "--no-ff", "-m", "merge fix", "moat-mac/proj/fix-crash")
r = publish()
check(f"merge commit refused: {r.stderr.strip()}",
      r.returncode != 0 and "merge commits" in r.stderr)
git(guest, "reset", "-q", "--hard", "HEAD~1")

# Publishing from outside the session namespace is refused with guidance.
git(guest, "switch", "-qc", "stray", base)
Path(guest, "stray.txt").write_text("s\n")
git(guest, "add", "stray.txt"); git(guest, "commit", "-qm", "stray work")
r = publish()
check(f"publish refuses branches outside the namespace: {r.stderr.strip().splitlines()[0] if r.stderr else ''}",
      r.returncode != 0 and "outside this session" in r.stderr
      and "git branch -m stray moat-mac/proj/stray" in r.stderr)
git(guest, "switch", "-q", "moat-mac/proj/fix-crash")

# --- Stacked branches: shared history, not duplicated commits ---
git(guest, "switch", "-qc", "moat-mac/proj/feature-a", base)
Path(guest, "fa.txt").write_text("a1\n")
git(guest, "add", "fa.txt"); git(guest, "commit", "-qm", "feature-a: first")
Path(guest, "fa2.txt").write_text("a2\n")
git(guest, "add", "fa2.txt"); git(guest, "commit", "-qm", "feature-a: second")
r = publish()
check(f"publish parent branch: {r.stdout.strip()}", r.returncode == 0)

git(guest, "switch", "-qc", "moat-mac/proj/feature-b")          # branches off feature-a
Path(guest, "fb.txt").write_text("b1\n")
git(guest, "add", "fb.txt"); git(guest, "commit", "-qm", "feature-b: first")
r = publish()
check(f"publish child records parent: {r.stdout.strip()}",
      r.returncode == 0 and 'on "moat-mac/proj/feature-a"' in r.stdout)
bdir = s / "mailbox" / "branches" / "feature-b"
check(f"PARENT records parent and fork: {(bdir / 'PARENT').read_text()!r}",
      (bdir / "PARENT").read_text().split() == ["feature-a", "2"])
check("child publishes only its own commit",
      sorted(p.name for p in bdir.iterdir()) == ["0001.patch", "PARENT"])

r = run("pull", "feature-b", "--session", "proj", input="y\n")
check(f"pulling child pulls its parent first: {r.stdout.strip()}",
      r.returncode == 0 and "feature-a" in r.stdout and "feature-b" in r.stdout)
aref, bref = "moat-mac/proj/feature-a", "moat-mac/proj/feature-b"
check("parent branch has its 2 commits",
      len(git(host, "rev-list", f"{base}..{aref}").stdout.split()) == 2)
check("child contains parent's history (shared, same shas)",
      subprocess.run(["git", "-C", host, "merge-base", "--is-ancestor",
                      aref, bref]).returncode == 0)
check("child adds exactly one commit on top",
      len(git(host, "rev-list", f"{aref}..{bref}").stdout.split()) == 1)
check("no duplicated commits in the tree",
      len(git(host, "rev-list", f"{base}..{bref}").stdout.split()) == 3)

# Appending to the parent leaves the child alone and intact.
git(guest, "switch", "-q", "moat-mac/proj/feature-a")
Path(guest, "fa3.txt").write_text("a3\n")
git(guest, "add", "fa3.txt"); git(guest, "commit", "-qm", "feature-a: third")
r = publish()
check("republish parent", r.returncode == 0)
child_before = git(host, "rev-parse", bref).stdout
r = run("pull", "--session", "proj", input="y\n")
check("parent advanced", r.returncode != 0 or "advanced by 1 commit " in r.stdout)
check("child ref untouched", git(host, "rev-parse", bref).stdout == child_before)

# Rewriting the parent skips the child rather than stacking on a stale tip.
git(guest, "commit", "--amend", "-qm", "feature-a: third, reworded")
r = publish()
check("republish rewritten parent", r.returncode == 0)
r = run("pull", "feature-b", "--session", "proj", input="y\n")
check(f"child skipped when parent diverges:\n{r.stderr.strip()}",
      r.returncode != 0 and "does not match" in r.stderr
      and ('skipping "moat-mac/proj/feature-b": its parent '
           '"moat-mac/proj/feature-a" was not updated') in r.stderr)

# --force resets a diverged branch and its affected children.
r = run("pull", "feature-b", "--session", "proj", "--force", input="y\n")
check(f"force pull resets and rebuilds: {[l for l in r.stdout.splitlines() if 'reset' in l]}",
      r.returncode == 0 and 'reset "moat-mac/proj/feature-a"' in r.stdout)
log_a = git(host, "log", "--format=%s", f"{base}..moat-mac/proj/feature-a").stdout.splitlines()
check(f"rewritten parent landed: {log_a}", log_a[0] == "feature-a: third, reworded")
# The child branched off the parent's second commit, so it keeps that
# shared history rather than jumping to the parent's new tip.
merge_base = git(host, "merge-base", "moat-mac/proj/feature-a",
                 "moat-mac/proj/feature-b").stdout.strip()
check("child still shares the parent's history",
      git(host, "log", "-1", "--format=%s", merge_base).stdout.strip()
      == "feature-a: second")
check("child keeps its own commit on top",
      len(git(host, "rev-list", f"{merge_base}..moat-mac/proj/feature-b").stdout.split()) == 1)
check("no duplicated commits after force",
      len(git(host, "rev-list", f"{base}..moat-mac/proj/feature-b").stdout.split()) == 3)
r = run("pull", "feature-b", "--session", "proj", "--force", input="y\n")
check(f"force is idempotent once in sync: {r.stdout.splitlines()[-1]}",
      r.returncode == 0 and "moat-mac: reset " not in r.stdout
      and "up to date" in r.stdout)

# PARENT naming an unpublished branch: that branch is skipped, others pull.
(s / "mailbox" / "branches" / "orphan").mkdir()
src_patch = (bdir / "0001.patch").read_text()
(s / "mailbox" / "branches" / "orphan" / "0001.patch").write_text(src_patch)
os.chmod(s / "mailbox" / "branches" / "orphan" / "0001.patch", 0o644)
(s / "mailbox" / "branches" / "orphan" / "PARENT").write_text("ghost\n")
r = run("pull", "orphan", "--session", "proj", input="y\n")
check(f"orphan parent refused: {r.stderr.strip()}",
      r.returncode != 0 and 'is not published' in r.stderr)

# Self-referential PARENT refused.
(s / "mailbox" / "branches" / "orphan" / "PARENT").write_text("orphan\n")
r = run("pull", "orphan", "--session", "proj", input="y\n")
check(f"self-parent refused: {r.stderr.strip()}",
      r.returncode != 0 and "names the branch itself" in r.stderr)
import shutil as _sh; _sh.rmtree(s / "mailbox" / "branches" / "orphan")

# Unicode survives a publish; control characters do not.
git(guest, "switch", "-qc", "moat-mac/proj/emdash", base)
Path(guest, "em.txt").write_text("an em dash \u2014 h\u00e9re\n")
git(guest, "add", "em.txt"); git(guest, "commit", "-qm", "use an em dash \u2014 here")
r = publish()
check(f"unicode publishes: {r.stdout.strip().splitlines()[0] if r.stdout else r.stderr.strip()}",
      r.returncode == 0)
r = run("pull", "emdash", "--session", "proj", input="y\n")
check("unicode pulls", r.returncode == 0
      and "\u2014" in git(host, "log", "-1", "--format=%s",
                          "moat-mac/proj/emdash").stdout)

# Control-character and binary commits refused at publish.
git(guest, "switch", "-qc", "moat-mac/proj/naughty", base)
Path(guest, "u.txt").write_text("h\x1b[31mllo\n")
git(guest, "add", "u.txt"); git(guest, "commit", "-qm", "escape")
r = publish()
check(f"control char publish refused: {r.stderr.splitlines()[0] if r.stderr else ''}",
      r.returncode != 0 and "U+001B" in r.stderr)
git(guest, "reset", "-q", "--hard", base)
Path(guest, "blob.bin").write_bytes(bytes(range(256)))
git(guest, "add", "blob.bin"); git(guest, "commit", "-qm", "binary")
r = publish()
check("binary publish refused", r.returncode != 0
      and ("binary" in r.stderr or "UTF-8" in r.stderr))
check("naughty branch never landed in mailbox",
      not (s / "mailbox" / "branches" / "naughty").exists())

# Numbering gap in the mailbox refused.
gap = s / "mailbox" / "branches" / "gappy"
gap.mkdir()
src = (s / "mailbox" / "branches" / "experiment" / "0001.patch").read_text()
(gap / "0002.patch").write_text(src)
os.chmod(gap / "0002.patch", 0o644)
r = run("pull", "gappy", "--session", "proj", input="y\n")
check("numbering gap refused", r.returncode != 0 and "gaps" in r.stderr)

# Multiple commits in one file refused.
multi = s / "mailbox" / "branches" / "multi"
multi.mkdir()
(multi / "0001.patch").write_text(src + src)
os.chmod(multi / "0001.patch", 0o644)
r = run("pull", "multi", "--session", "proj", input="y\n")
check("multi-commit file refused", r.returncode != 0 and "expected exactly one" in r.stderr)

# Symlinked branch dir ignored.
os.symlink(s / "mailbox" / "branches" / "experiment",
           s / "mailbox" / "branches" / "sneaky")
r = run("pull", "sneaky", "--session", "proj", input="y\n")
check("symlinked branch dir not a published branch",
      r.returncode != 0 and "no published branch" in r.stderr)

dirty = git(host, "status", "--porcelain").stdout.strip()
check(f"host worktree untouched ({dirty!r})", dirty == "")

# share
fb = Path(tmp) / "feedback.md"; fb.write_text("rename X\n")
r = run("share", "--file", str(fb), "--session", "proj", input="n\n")
check("share declined copies nothing",
      r.returncode != 0 and not (s / "mailbox" / "shared" / "feedback.md").exists())
r = run("share", "--file", str(fb), "--session", "proj", input="y\n")
check("share ok", r.returncode == 0 and (s / "mailbox" / "shared" / "feedback.md").is_file())
r = run("share", "--file", str(fb), "--session", "proj", input="y\n")
check("share refuses overwrite", r.returncode != 0)
d = Path(tmp) / "somedir"; d.mkdir()
r = run("share", "--file", str(d), "--session", "proj")
check(f"share refuses directory: {r.stderr.strip()}",
      r.returncode != 0 and "is a directory" in r.stderr)

# cwd defaults: from inside the repo, --session is unnecessary.
r = run("pull", cwd=host, input="y\n")
check(f"pull defaults to cwd session: {r.stdout.splitlines()[0] if r.stdout else r.stderr}",
      r.returncode != 0 and f"into {host}?" in r.stdout)  # diverged branch still pending
r = run("pull", cwd=tmp, input="y\n")
check(f"no session for cwd refused: {r.stderr.strip()}",
      r.returncode != 0 and "no session for the current directory" in r.stderr)
fb2 = Path(tmp) / "notes.md"; fb2.write_text("hi\n")
r = run("share", "--file", str(fb2), cwd=host, input="y\n")
check("share defaults to cwd session", r.returncode == 0
      and (s / "mailbox" / "shared" / "notes.md").is_file())

# --- push: host -> mailbox, and moat-fetch in the VM ---
FETCH = ROOT / "guest" / "moat-fetch"
def fetch(*args):
    return subprocess.run([sys.executable, str(FETCH), *args], env=guest_env,
                          capture_output=True, text=True)

r = run("push", "--session", "proj", input="y\n")
check(f"push ok: {[l for l in r.stdout.splitlines() if 'pushed' in l]}", r.returncode == 0)
pushed_a = s / "mailbox" / "from-host" / "feature-a"
check("pushed branch written to from-host", pushed_a.is_dir()
      and (pushed_a / "0001.patch").is_file())
pushed_b = s / "mailbox" / "from-host" / "feature-b"
check("pushed child records its parent",
      (pushed_b / "PARENT").read_text().split()[0] == "feature-a"
      and sorted(p.name for p in pushed_b.iterdir()) == ["0001.patch", "PARENT"])

# A host-side commit reaches the VM.
git(host, "switch", "-q", "--detach", "moat-mac/proj/feature-a")
Path(host, "host-note.txt").write_text("from the host\n")
git(host, "add", "host-note.txt"); git(host, "commit", "-qm", "host: add a note")
git(host, "branch", "-f", "moat-mac/proj/feature-a", "HEAD")
git(host, "switch", "-q", "main")
r = run("push", "feature-a", "--session", "proj", input="y\n")
check(f"push single branch: {r.stdout.strip().splitlines()[-2:]}", r.returncode == 0)

r = fetch()
check(f"moat-fetch takes host branches: {r.stdout.strip()} {r.stderr.strip()}",
      r.returncode == 0 and "built " in r.stdout)
check("host commit arrived in the VM",
      "host: add a note" in git(guest, "log", "--format=%s",
                                "moat-mac/proj/feature-a").stdout)
check("agent's own branch fast-forwarded to the host's version",
      git(guest, "log", "--format=%s", "-1", "moat-mac/proj/feature-a").stdout.strip()
      == "host: add a note")
# feature-b forked from feature-a's second commit, so it shares that
# history rather than sitting on the parent's newer tip.
a_ref = "moat-mac/proj/feature-a"
b_ref = ("host/feature-b" if subprocess.run(
    ["git", "-C", str(guest), "rev-parse", "--verify", "-q", "host/feature-b"],
    capture_output=True).returncode == 0 else "moat-mac/proj/feature-b")
fetched_fork = git(guest, "merge-base", a_ref, b_ref).stdout.strip()
check(f"fetched child shares the fetched parent's history",
      fetched_fork != base
      and git(guest, "log", "-1", "--format=%s", fetched_fork).stdout.strip()
      == "feature-a: second")
check("fetched child has no duplicated commits",
      len(git(guest, "rev-list", f"{base}..{b_ref}").stdout.split()) == 3)
r = fetch("feature-b")
check("moat-fetch is idempotent", r.returncode == 0)
r = fetch("nonexistent")
check(f"moat-fetch rejects unknown branch: {r.stderr.strip()}", r.returncode != 0)

# Regression: pushing all branches skips ones with nothing to push
# instead of failing the whole push.
git(host, "branch", "moat-mac/proj/idle", base)
r = run("push", "--session", "proj", input="y\n")
check(f"empty branch skipped, not fatal: {[l for l in r.stdout.splitlines() if 'idle' in l]}",
      r.returncode == 0 and 'nothing to push on "moat-mac/proj/idle"' in r.stdout
      and 'pushed "moat-mac/proj/feature-a"' in r.stdout)
r = run("push", "idle", "--session", "proj", input="y\n")
check("naming an empty branch is still an error",
      r.returncode != 0 and "nothing to push" in r.stderr)
git(host, "branch", "-D", "moat-mac/proj/idle")

# Regression: a host commit on a parent must not flip the recorded
# parent/child relationship (depth heuristic used to invert it).
pushed_a = s / "mailbox" / "from-host" / "feature-a"
pushed_b = s / "mailbox" / "from-host" / "feature-b"
check("parent stays the parent after host commits",
      not (pushed_a / "PARENT").exists()
      and (pushed_b / "PARENT").read_text().split()[0] == "feature-a")

# create --name collision hint (dies before any tart call).
r = run("create", "--repo", host, "--name", "proj")
check(f"create name collision refused: {r.stderr.strip().splitlines()[0]}",
      r.returncode != 0 and "already exists" in r.stderr
      and "--name" in r.stderr)

# Two sessions on one repo: cwd resolution demands --session.
s2dir = Path(host_env["MOAT_MAC_HOME"]) / "proj-two"
(s2dir / "mailbox" / "branches").mkdir(parents=True)
(s2dir / "session.json").write_text(json.dumps({
    "name": "proj-two", "repo": host, "repo_name": "proj", "branch": "main",
    "base_commit": base, "created": "x"}))
r = run("pull", cwd=host, input="y\n")
check(f"ambiguous cwd session refused: {r.stderr.strip()}",
      r.returncode != 0 and "multiple sessions" in r.stderr
      and "proj-two" in r.stderr)
r = run("pull", "--session", "proj-two", cwd=host, input="y\n")
check("explicit --session resolves ambiguity",
      "nothing published" in r.stdout and r.returncode == 0)
import shutil as _shutil
_shutil.rmtree(s2dir)

# create marks where the session started, as moat-mac/<session>/<branch>.
create_stub = Path(tmp) / "createbin"
create_stub.mkdir()
(create_stub / "tart").write_text(
    '#!/bin/sh\ncase "$1" in list) echo \'[{"Name":"moat-mac-base","Running":false,"State":"stopped"}]\' ;; '
    'clone) exit 0 ;; *) exit 1 ;; esac\n')
os.chmod(create_stub / "tart", 0o755)
marker_home = Path(tmp) / "marker-home"
r = subprocess.run(
    [sys.executable, str(CLI), "create", "--repo", host, "--name", "marked"],
    env=dict(host_env, MOAT_MAC_HOME=str(marker_home),
             PATH=f"{create_stub}:{os.environ['PATH']}"),
    capture_output=True, text=True, input="y\n")
check(f"create announces the session branch: {[l for l in r.stdout.splitlines() if 'branch' in l]}",
      '- creates branch "moat-mac/marked/main" from main' in r.stdout
      and 'created branch "moat-mac/marked/main"' in r.stdout)
check("session branch points at the base commit",
      git(host, "rev-parse", "moat-mac/marked/main").stdout.strip() == base)
check("session is seeded from that branch",
      "@ moat-mac/marked/main" in r.stdout)

# Re-creating from that branch reuses it rather than nesting another.
r2 = subprocess.run(
    [sys.executable, str(CLI), "create", "--repo", host, "--name", "marked"],
    env=dict(host_env, MOAT_MAC_HOME=str(Path(tmp) / "marker-home-2"),
             PATH=f"{create_stub}:{os.environ['PATH']}"),
    capture_output=True, text=True, input="y\n", cwd=host)
check(f"existing session branch is reused: {[l for l in r2.stdout.splitlines() if 'branch' in l]}",
      'uses existing branch "moat-mac/marked/main"' in r2.stdout)
git(host, "branch", "-D", "moat-mac/marked/main")

# Regression: reusing an existing session branch seeds from that branch,
# not from whatever HEAD happens to be.
git(host, "switch", "-q", "main")
git(host, "branch", "moat-mac/reuse/main", base)
Path(host, "moved-on.txt").write_text("later\n")
git(host, "add", "moved-on.txt"); git(host, "commit", "-qm", "host moved on")
reuse_home = Path(tmp) / "reuse-home"
r = subprocess.run(
    [sys.executable, str(CLI), "create", "--repo", host, "--name", "reuse"],
    env=dict(host_env, MOAT_MAC_HOME=str(reuse_home),
             PATH=f"{create_stub}:{os.environ['PATH']}"),
    capture_output=True, text=True, input="y\n")
check(f"reused branch seeds from its own commit: {[l for l in r.stdout.splitlines() if 'seeds' in l]}",
      f"@ moat-mac/reuse/main ({base[:10]})" in r.stdout
      and 'uses existing branch "moat-mac/reuse/main"' in r.stdout)
check("recorded base commit matches the reused branch",
      json.loads((reuse_home / "reuse" / "session.json").read_text())["base_commit"] == base)
git(host, "branch", "-D", "moat-mac/reuse/main")
git(host, "reset", "-q", "--hard", "HEAD~1")

# Commands needing the base image point at setup when it is missing.
nobase = Path(tmp) / "nobase"
nobase.mkdir()
(nobase / "tart").write_text('#!/bin/sh\ncase "$1" in list) echo "[]" ;; esac\n')
os.chmod(nobase / "tart", 0o755)
nobase_env = dict(host_env, PATH=f"{nobase}:{os.environ['PATH']}")
for cmd in (["create", "--repo", host, "--name", "fresh"],
            ["start", "--session", "proj"]):
    r = subprocess.run([sys.executable, str(CLI), *cmd], env=nobase_env,
                       capture_output=True, text=True, input="y\n")
    check(f"{cmd[0]} without base image points at setup: {r.stderr.strip().splitlines()[0] if r.stderr else ''}",
          r.returncode != 0 and "moat-mac setup" in r.stderr)

# setup is a no-op when the base image is already installed.
withbase = Path(tmp) / "withbase"
withbase.mkdir()
(withbase / "tart").write_text(
    '#!/bin/sh\ncase "$1" in list) echo \'[{"Name":"moat-mac-base","Running":false,"State":"stopped"}]\' ;; esac\n')
os.chmod(withbase / "tart", 0o755)
r = subprocess.run([sys.executable, str(CLI), "setup"],
                   env=dict(host_env, PATH=f"{withbase}:{os.environ['PATH']}"),
                   capture_output=True, text=True)
check(f"setup is idempotent: {r.stdout.strip()}",
      r.returncode == 0 and "already installed" in r.stdout)

# delete: end-to-end with a stub tart (confirms, removes session dir).
stub = Path(tmp) / "bin"
stub.mkdir()
(stub / "tart").write_text('#!/bin/sh\ncase "$1" in list) echo "[]" ;; esac\n')
os.chmod(stub / "tart", 0o755)
del_env = dict(host_env, PATH=f"{stub}:{os.environ['PATH']}")
r = subprocess.run([sys.executable, str(CLI), "delete", "--session", "proj"],
                   env=del_env, capture_output=True, text=True, input="y\n")
check(f"delete ok: {r.stdout.strip().splitlines()[-1] if r.stdout else r.stderr.strip()}",
      r.returncode == 0 and 'deleted session "proj"' in r.stdout and not s.exists())

print("\n%d failures" % len(fails))
sys.exit(1 if fails else 0)

"""Tests for bundle_repo: local-submodule seeding without network. Needs git; no tart."""
import importlib.util, os, subprocess, sys, tempfile, tarfile
from pathlib import Path
CLI = Path(__file__).resolve().parent.parent / "moat-mac"
spec = importlib.util.spec_from_loader("moatmac", loader=None)
mod = importlib.util.module_from_spec(spec)
exec(compile(CLI.read_text(), str(CLI), "exec"), mod.__dict__)

tmp = Path(tempfile.mkdtemp(prefix="bundle-test-"))
def git(repo, *args, **kw):
    return subprocess.run(["git", "-C", str(repo), *args], check=True,
                          capture_output=True, text=True, **kw)

# Submodule origin + main repo.
sub_origin = tmp / "sub-origin"
subprocess.run(["git", "init", "-q", str(sub_origin)], check=True)
git(sub_origin, "config", "user.email", "t@t"); git(sub_origin, "config", "user.name", "t")
(sub_origin / "s.txt").write_text("sub content\n")
git(sub_origin, "add", "."); git(sub_origin, "commit", "-qm", "sub init")

main = tmp / "main"
subprocess.run(["git", "init", "-q", "-b", "main", str(main)], check=True)
git(main, "config", "user.email", "t@t"); git(main, "config", "user.name", "t")
(main / "a.txt").write_text("hi\n")
git(main, "add", ".")
git(main, "-c", "protocol.file.allow=always", "submodule", "add", str(sub_origin), "thesub")
# Sabotage the recorded URL: if bundling hits it, it fails. Proves no network.
gm = (main / ".gitmodules").read_text().replace(str(sub_origin), "https://invalid.invalid/nope.git")
(main / ".gitmodules").write_text(gm)
git(main, "add", ".gitmodules"); git(main, "commit", "-qm", "init with submodule")
branch = "main"

tar_path = tmp / "repo.tar"
mod.bundle_repo(main, branch, tar_path)

with tarfile.open(tar_path) as tf:
    names = tf.getnames()
ok1 = "main/thesub/s.txt" in names
print("PASS" if ok1 else "FAIL", "submodule populated from local checkout (bogus URL untouched)")

# Check synced URL inside the bundle points at the canonical (bogus) URL,
# not the host path.
import shutil
extract = tmp / "x"; extract.mkdir()
with tarfile.open(tar_path) as tf:
    tf.extractall(extract)
url = subprocess.run(["git", "-C", str(extract / "main"), "config", "submodule.thesub.url"],
                     capture_output=True, text=True).stdout.strip()
ok2 = url == "https://invalid.invalid/nope.git"
print("PASS" if ok2 else f"FAIL ({url})", "synced URL is canonical, not a host path")

# The bundle carries exactly one branch: the repo's current one.
git(main, "branch", "other-branch")
git(main, "branch", "third-branch")
branches = subprocess.run(
    ["git", "-C", str(extract / "main"), "branch", "--format=%(refname:short)"],
    capture_output=True, text=True).stdout.split()
ok_single = branches == [branch]
print("PASS" if ok_single else f"FAIL ({branches})",
      "bundled clone has only the seeded branch")
remotes = subprocess.run(
    ["git", "-C", str(extract / "main"), "branch", "-r", "--format=%(refname:short)"],
    capture_output=True, text=True).stdout.split()
ok_remote = all(r.endswith(f"/{branch}") or r == "origin/HEAD" for r in remotes)
print("PASS" if ok_remote else f"FAIL ({remotes})",
      "no other branches came along as remotes")

# Unpopulated-submodule fallback: de-populate and confirm bundle_repo tries
# the recorded URL (it should FAIL here since the URL is bogus = network path).
git(main, "submodule", "deinit", "-f", "thesub")
ok3 = False
try:
    mod.bundle_repo(main, branch, tmp / "repo2.tar")
    print("FAIL fallback unexpectedly succeeded")
except (subprocess.CalledProcessError, SystemExit):
    ok3 = True
    print("PASS unpopulated submodule falls back to recorded URL (fails on bogus URL as expected)")
shutil.rmtree(tmp)
sys.exit(0 if ok1 and ok2 and ok3 and ok_single and ok_remote else 1)

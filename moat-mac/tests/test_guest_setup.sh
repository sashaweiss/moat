#!/usr/bin/env zsh
# Tests for guest-setup.sh, run against a fake $HOME. Needs python3; no tart.
set -euo pipefail
ROOT=${0:a:h:h}
fails=0

run_case() {
  local corrupt=$1 name=$2 expect=$3
  local T=$(mktemp -d)
  HOME=$T
  mkdir -p $T/mailbox/.provision $T/stage
  git init -q -b moat-mac/proj/main $T/stage/proj
  git -C $T/stage/proj config user.email t@t
  git -C $T/stage/proj config user.name t
  echo hi > $T/stage/proj/a.txt
  git -C $T/stage/proj add .
  git -C $T/stage/proj commit -qm init
  tar -cf $T/mailbox/repo.tar -C $T/stage proj
  local sha=$(python3 -c "import hashlib; print(hashlib.sha256(open('$T/mailbox/repo.tar','rb').read()).hexdigest())")
  if [[ $corrupt == yes ]]; then
    python3 -c "
import os
f = open('$T/mailbox/repo.tar', 'r+b')
f.truncate(os.path.getsize('$T/mailbox/repo.tar') - 100)"
  fi
  cp $ROOT/guest/moat-publish $ROOT/guest/moat-fetch $T/mailbox/.provision/
  echo "{\"session\":\"proj\",\"repo_name\":\"proj\",\"base_commit\":\"abc\",\"branch\":\"main\",\"bundle_sha256\":\"$sha\"}" > $T/mailbox/.provision/config.json
  local result
  if HOME=$T zsh $ROOT/guest/guest-setup.sh >/dev/null 2>&1 \
      && [[ -f $T/mailbox/.provision/.complete && -x $T/.local/bin/moat-publish && -x $T/.local/bin/moat-fetch ]] \
      && [[ "$(git -C $T/work/proj rev-parse --abbrev-ref HEAD)" == "moat-mac/proj/main" ]]; then
    result=ok
  else
    result=failed
  fi
  if [[ $result == $expect ]]; then
    echo "PASS $name"
  else
    echo "FAIL $name (got $result, expected $expect)"
    fails=$((fails + 1))
  fi
  rm -rf $T
}

run_case no "happy path installs helper and writes marker" ok
run_case yes "truncated bundle refused" failed
echo "$fails failures"
exit $(( fails > 0 ))

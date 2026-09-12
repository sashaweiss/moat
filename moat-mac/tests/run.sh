#!/usr/bin/env zsh
# Runs every moat-mac test suite. Needs git, python3, zsh; no tart.
set -uo pipefail
HERE=${0:a:h}
fails=0
for suite in test_cli.py test_list.py test_bundle.py test_guest_setup.sh test_completions.zsh; do
  echo "=== $suite"
  case $suite in
    *.py) python3 $HERE/$suite ;;
    *)    zsh $HERE/$suite ;;
  esac || fails=$((fails + 1))
done
echo "==="
if (( fails > 0 )); then
  echo "run: $fails suite(s) FAILED"
  exit 1
fi
echo "run: all suites passed"

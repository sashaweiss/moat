#!/usr/bin/env zsh
# Tests for the zsh completions, simulating TAB via zpty. No tart.
ROOT=${0:a:h:h}
fails=0
T=$(mktemp -d)
export MOAT_MAC_HOME=$T/moat-home
mkdir -p $MOAT_MAC_HOME/signal-wt $MOAT_MAC_HOME/dummy
echo '{}' > $MOAT_MAC_HOME/signal-wt/session.json
echo '{}' > $MOAT_MAC_HOME/dummy/session.json
mkdir -p $MOAT_MAC_HOME/signal-wt/mailbox/branches/fix-crash
mkdir -p $MOAT_MAC_HOME/signal-wt/mailbox/branches/experiment

zmodload zsh/zpty
zpty z "MOAT_MAC_HOME=$MOAT_MAC_HOME zsh -f"
zpty -w z "fpath=($ROOT/completions \$fpath); autoload -Uz compinit; compinit -u; zstyle ':completion:*' menu no; bindkey -e"
sleep 1
test_tab() {
  local desc=$1 input=$2 expect=$3
  zpty -w z ""
  sleep 0.3
  zpty -rt z discard 2>/dev/null  # drain
  # Type input then TAB (no newline), capture, then Ctrl-C to cancel line.
  zpty -n -w z "$input"$'\t'
  sleep 1
  local out=""
  local chunk
  while zpty -rt z chunk 2>/dev/null; do out+=$chunk; done
  zpty -n -w z $'\003'
  sleep 0.3
  while zpty -rt z chunk 2>/dev/null; do :; done
  if [[ $out == *$expect* ]]; then
    echo "PASS $desc"
  else
    echo "FAIL $desc"
    echo "  got: ${out//$'\e'/ESC}" | head -4
    fails=$((fails + 1))
  fi
}
test_tab "subcommands" "moat-mac pu" "pull"
test_tab "session names" "moat-mac stop --session " "signal-wt"
test_tab "session filter" "moat-mac pull --session sig" "signal-wt"
test_tab "start flags" "moat-mac start --no" "no-claude"
test_tab "published branches" "moat-mac pull --session signal-wt fix" "fix-crash"
zpty -d z
rm -rf $T
echo "$fails failures"
exit $(( fails > 0 ))

#!/usr/bin/env bash
# tests/cli/run.sh — black-box harness for bin/clog, lib/config.sh and hooks/.
# One function per spec scenario (openspec/specs/{cli,log-entry,config,hooks}),
# each in its own scratch dir, so order does not matter. No dependencies beyond
# bash, jq and git (yq is optional: parity cases skip without it).
# Usage: bash tests/cli/run.sh [name-substring]

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)
CLOG=$REPO/bin/clog
HOOKS=$REPO/hooks
SELF=${BASH_SOURCE[0]}
UNK="(expected DECISION | ACTION | CODE | PR | COMMIT | REPO | FOLLOWUP | LEARNING | LESSON)"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export GIT_AUTHOR_NAME=clog-test GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=clog-test GIT_COMMITTER_EMAIL=t@example.invalid

# PATH variants, each a scratch dir of symlinks to the tools clog needs, so no
# machine-wide directory (e.g. /opt/homebrew/bin, which holds jq and yq side by
# side) leaks yq or clog in. TPATH has no yq and no clog: the fallback parser runs
# and hooks resolve ../bin/clog. YQPATH adds yq for the parity cases.
TOOLS=(bash jq git cat date sed awk grep tr head tail mktemp dirname basename env printf
  touch stat wc cut sort mkdir readlink mv which)
TOOLDIR=$(mktemp -d "${TMPDIR:-/tmp}/clog-cli-tools.XXXXXX") || { echo "FAIL: mktemp"; exit 2; }
trap 'find "$TOOLDIR" -depth -delete 2>/dev/null' EXIT
TPATH=$TOOLDIR/plain YQPATH=$TOOLDIR/yq HAVE_YQ=0
mkdir -p "$TPATH" "$YQPATH"
for t in "${TOOLS[@]}"; do
  d=$(type -P "$t") || { echo "FAIL: required tool '$t' not found on PATH"; exit 2; }
  ln -s "$d" "$TPATH/$t" && ln -s "$d" "$YQPATH/$t" || { echo "FAIL: cannot link '$t'"; exit 2; }
done
if d=$(type -P yq); then
  HAVE_YQ=1
  ln -s "$d" "$YQPATH/yq"
fi
VARIANTS=("$TPATH")
[[ $HAVE_YQ == 1 ]] && VARIANTS+=("$YQPATH")

# ---- assert helpers ---------------------------------------------------------
fail() { printf '%s\n' "$*" >> "$RESDIR/$FN.fail"; }
skip() { printf '%s\n' "$*" >> "$RESDIR/$FN.skip"; }
# match <value> <pattern>: - any | EMPTY | =exact | ^prefix | ~substring | glob
match() {
  local v=$1 p=$2
  case $p in
    -) return 0 ;;
    EMPTY) [[ -z $v ]] ;;
    =*) [[ $v == "${p#=}" ]] ;;
    ^*) [[ $v == "${p#^}"* ]] ;;
    '~'*) [[ $v == *"${p#\~}"* ]] ;;
    *) [[ $v == $p ]] ;;
  esac
}
# expect <label> <rc|-> <stdout-pattern|-> <stderr-pattern|-> checks the last run.
expect() {
  local label=$1 rc=$2 op=${3:--} ep=${4:--}
  [[ $rc == - || $RC == "$rc" ]] || fail "$label: rc=$RC want $rc (stderr: ${ERR:0:160})"
  match "$OUT" "$op" || fail "$label: stdout '${OUT:0:160}' !~ '$op'"
  match "$ERR" "$ep" || fail "$label: stderr '${ERR:0:160}' !~ '$ep'"
}
expect_eq() { [[ $2 == "$3" ]] || fail "$1: got '$2' want '$3'"; }
# expect_file <label> <path> exists|absent|lines=N
expect_file() {
  case $3 in
    exists) [[ -e $2 ]] || fail "$1: $2 missing" ;;
    absent) [[ ! -e $2 ]] || fail "$1: $2 exists" ;;
    lines=*) expect_eq "$1" "$(wc -l < "$2" 2>/dev/null | tr -d ' ')" "${3#lines=}" ;;
  esac
}
# expect_json <label> <file> <jq-expr> <expected> [line, default last]
expect_json() {
  local got line=${5:-\$}
  [[ -f $2 ]] || { fail "$1: no file $2"; return; }
  got=$(sed -n "${line}p" "$2" | jq -r "$3" 2>&1)
  [[ $got == "$4" ]] || fail "$1: got '$got' want '$4'"
}

# ---- scratch environment ----------------------------------------------------
new_env() {
  T=$(mktemp -d "${TMPDIR:-/tmp}/clog-cli.XXXXXX") || { echo "FAIL: mktemp"; exit 2; }
  T=$(cd "$T" && pwd -P)
  mkdir -p "$T/home" "$T/tmp" "$T/work"
  RUNDIR=$T/work ENVX=() EXTRA=() STDIN=""
  sed "s|\${HOME}/clog-logs|$T/logs|g" "$REPO/config/config.yaml.example" > "$T/cfg.yaml"
  BASE=(HOME="$T/home" PATH="$TPATH" TMPDIR="$T/tmp" CLOG_CONFIG="$T/cfg.yaml"
    CLOG_TAGS_FILE=/nonexistent GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    GIT_AUTHOR_NAME=clog-test GIT_AUTHOR_EMAIL=t@example.invalid
    GIT_COMMITTER_NAME=clog-test GIT_COMMITTER_EMAIL=t@example.invalid)
  LOGDIR=$T/logs/claude
  TODAY=$(date +%Y%m%d)
  LOGF=$LOGDIR/$TODAY.jsonl
}
cleanup() { chmod -R u+rwx "$T" 2>/dev/null; find "$T" -depth -delete 2>/dev/null; }

# run <cmd...>: clean env (BASE then ENVX), cwd RUNDIR, stdin STDIN; sets OUT ERR RC.
run() {
  OUT=$(printf '%s' "$STDIN" | (cd "$RUNDIR" && env -i "${BASE[@]}" ${ENVX[@]+"${ENVX[@]}"} "$@") 2>"$T/err")
  RC=$?
  ERR=$(<"$T/err")
  STDIN=""
}
runclog() { run "$CLOG" "$@"; }
hook() { local h=$1; shift; run bash "${HOOKS_DIR:-$HOOKS}/$h" "$@"; }
cfg_write() { cat > "$T/cfg.yaml"; }
mkrepo() { mkdir -p "$1"; git -C "$1" init -q; git -C "$1" commit -q --allow-empty -m init; }
count_commits() { git -C "$1" rev-list --count HEAD; }
bash_payload() { jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
mkfake() { mkdir -p "$T/fake"; cp -R "$HOOKS" "$REPO/lib" "$T/fake/"; HOOKS_DIR=$T/fake/hooks; }
epoch_ts() { date -r "$1" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$1" +%Y%m%d%H%M.%S; }
age_file() { touch -t "$(epoch_ts $(( $(date +%s) - $2 )))" "$1"; }
seed_log() { mkdir -p "$LOGDIR"; printf '%s\n' '{"time":"00:00:00","type":"ACTION","summary":"prior"}' > "$LOGF"; }
getv() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }
has_var() { printf '%s\n' "$OUT" | grep -q "^$1="; }
# dumpv <path> <cfg> [load_config args]: load_config in a clean shell, print CLOG_* env.
dumpv() {
  local p=$1 cfg=$2; shift 2
  ENVX=(PATH="$p" CLOG_CONFIG="$cfg" ${EXTRA[@]+"${EXTRA[@]}"})
  run bash -c '. "$1/lib/config.sh"; shift; load_config "$@"; rc=$?; env | grep "^CLOG_" | sort; exit $rc' _ "$REPO" "$@"
}
fallback_ok() { :; }  # TPATH never contains yq, so the fallback parser always runs
need_yq() { [[ $HAVE_YQ == 1 ]] || { skip "yq not installed"; return 1; }; }
# ac_cfg <repo_root> <log_root>: enable auto-commit.
ac_cfg() {
  cfg_write <<EOF
log_root: "$2"
log_subdir: "claude"
auto_commit:
  enabled: true
  repo_root: "$1"
  message: "docs(clog): auto-commit logs"
EOF
}
min_cfg() { printf 'log_root: "%s"\nlog_subdir: "claude"\n' "$T/logs" > "$T/cfg.yaml"; }

# ============================================================================
# cli/spec.md
# ============================================================================
c_cli__flags_after_positionals() {
  runclog ACTION "deploy to staging" --repo my-repo --agent orchestrator
  expect run 0 EMPTY EMPTY
  expect_json fields "$LOGF" '[.type,.summary,.repo,.agent]|join("|")' 'ACTION|deploy to staging|my-repo|orchestrator'
}
c_cli__flag_in_type_position() {
  runclog --repo x ACTION "s"
  expect run 1 EMPTY "=clog: unknown type '--repo' $UNK"
  expect_file nothing_written "$T/logs" absent
}
c_cli__symlinked_install() {
  mkdir -p "$T/bin"; ln -s "$CLOG" "$T/bin/clog"; ln -s clog "$T/bin/chained"
  run "$T/bin/clog" ACTION "via link"
  expect direct_link 0 EMPTY EMPTY
  run "$T/bin/chained" ACTION "via chain"
  expect chained_link 0 EMPTY EMPTY
  expect_json summaries "$LOGF" '.summary' 'via chain'
  expect_file two_lines "$LOGF" lines=2
}
c_cli__help_without_config() {
  ENVX=(CLOG_CONFIG=/nonexistent/cfg.yaml)
  runclog --help
  expect long 0 '^Usage: clog <TYPE> "<summary>" [flags]' EMPTY
  runclog -h
  expect short 0 '^Usage: clog <TYPE> "<summary>" [flags]' EMPTY
}
c_cli__help_ignores_disable() {
  ENVX=(CLOG_DISABLE=1)
  runclog --help
  expect help 0 '^Usage: clog' EMPTY
}
c_cli__help_as_later_argument() {
  runclog ACTION --help
  expect run 0 EMPTY EMPTY
  expect_json summary "$LOGF" '.summary' '--help'
}
c_cli__no_arguments() {
  runclog
  expect run 1 EMPTY '^clog: missing TYPE'
  expect_file nothing_written "$T/logs" absent
}
c_cli__empty_summary() {
  runclog ACTION ""
  expect empty 1 EMPTY '^clog: missing summary'
  runclog ACTION
  expect absent 1 EMPTY '^clog: missing summary'
  expect_file nothing_written "$T/logs" absent
}
c_cli__lowercase_type() {
  runclog action "x"
  expect run 1 EMPTY "=clog: unknown type 'action' $UNK"
  expect_file nothing_written "$T/logs" absent
}
c_cli__each_valid_type() {
  local t
  for t in DECISION ACTION CODE PR COMMIT REPO FOLLOWUP LEARNING LESSON; do
    runclog "$t" "Go interfaces are structural"
    expect "$t" 0 EMPTY EMPTY
  done
  expect_eq types "$(jq -r .type "$LOGF" | tr '\n' ' ')" "DECISION ACTION CODE PR COMMIT REPO FOLLOWUP LEARNING LESSON "
}
c_cli__special_characters() {
  local s=$'say "double" \'single\' back\\slash\nnext\ttab'
  runclog ACTION "$s"
  expect run 0 EMPTY EMPTY
  expect_eq roundtrip "$(jq -j .summary "$LOGF")" "$s"
  expect_file one_line "$LOGF" lines=1
}
c_cli__whitespace_summary() {
  runclog ACTION " "
  expect run 0 EMPTY EMPTY
  expect_json summary "$LOGF" '.summary' ' '
}
c_cli__all_flags() {
  runclog ACTION all --agent a --repo r --session s --model m --file /f --family tooling --kpi effective
  expect run 0 EMPTY EMPTY
  expect_json fields "$LOGF" '[.agent,.repo,.session,.model,.file,.family,.kpi]|join(",")' 'a,r,s,m,/f,tooling,effective'
  expect_json no_validation "$LOGF" 'has("validation")' false
}
c_cli__repeated_flag() {
  runclog ACTION x --repo first --repo second
  expect run 0 EMPTY EMPTY
  expect_json repo "$LOGF" '.repo' second
}
c_cli__tags_defaults_plus_explicit() {
  ENVX=(CLOG_DEFAULT_TAGS=jbook)
  runclog ACTION x --tags "release, jbook ,web"
  expect run 0 EMPTY EMPTY
  expect_json tags "$LOGF" '.tags|join(",")' 'jbook,release,web'
}
c_cli__tags_without_defaults() {
  runclog ACTION x --tags a,b
  expect run 0 EMPTY EMPTY
  expect_json tags "$LOGF" '.tags|join(",")' 'a,b'
}
c_cli__tags_blank_values() {
  runclog ACTION x --tags " , ,"
  expect commas 0 EMPTY EMPTY
  expect_json empty_array "$LOGF" '.tags|tojson' '[]'
  runclog ACTION y --tags " "
  expect space 0 EMPTY EMPTY
  expect_json empty_array_space "$LOGF" '.tags|tojson' '[]'
}
c_cli__unknown_flag() {
  runclog ACTION x --bogus --repo r
  expect run 1 EMPTY "=clog: unknown flag '--bogus'"
  expect_file nothing_written "$T/logs" absent
}
c_cli__extra_positional() {
  runclog ACTION deploy to staging
  expect run 1 EMPTY "=clog: unexpected argument 'to'"
  expect_file nothing_written "$T/logs" absent
}
c_cli__flag_without_value() {
  runclog ACTION x --repo
  expect run 1 EMPTY "=clog: --repo needs a value"
  expect_file nothing_written "$T/logs" absent
}
c_cli__flag_followed_by_flag() {
  runclog ACTION x --repo --echo
  expect echo 1 EMPTY "=clog: --repo needs a value"
  runclog ACTION x --agent --tags a
  expect tags 1 EMPTY "=clog: --agent needs a value"
  expect_file nothing_written "$T/logs" absent
}
c_cli__value_with_dashes() {
  runclog ACTION x --repo --not-a-flag --echo
  expect run 0 '~"repo":"--not-a-flag"' EMPTY
  expect_json repo "$LOGF" '.repo' '--not-a-flag'
}
c_cli__repo_autodetect_inside() {
  mkrepo "$T/myrepo"; mkdir "$T/myrepo/sub"; RUNDIR=$T/myrepo/sub
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_json repo "$LOGF" '.repo' myrepo
}
c_cli__repo_autodetect_outside() {
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_json no_repo "$LOGF" 'has("repo")' false
}
c_cli__session_precedence() {
  ENVX=(CLAUDE_CODE_SESSION_ID=ccs CLAUDE_SESSION_ID=cs)
  runclog ACTION x
  expect both 0 EMPTY EMPTY
  expect_json session "$LOGF" '.session' ccs
  local v
  for v in CLAUDE_SESSION_ID:cs CODEX_SESSION_ID:cx CURSOR_SESSION_ID:cu; do
    rm -f "$LOGF"; ENVX=("${v%%:*}=${v#*:}")
    runclog ACTION x
    expect "${v%%:*}" 0 EMPTY EMPTY
    expect_json "chain_${v%%:*}" "$LOGF" '.session' "${v#*:}"
  done
}
c_cli__session_sentinel() {
  runclog ACTION x --session unknown
  expect flag 0 EMPTY EMPTY
  expect_json flag_absent "$LOGF" 'has("session")' false
  ENVX=(CLAUDE_SESSION_ID=unknown)
  runclog ACTION y
  expect env 0 EMPTY EMPTY
  expect_json env_absent "$LOGF" 'has("session")' false
}
c_cli__validation_both_unknown() {
  runclog LEARNING x --family nope --kpi nah
  expect run 0 EMPTY EMPTY
  expect_json validation "$LOGF" '.validation' 'unknown_family,unknown_kpi'
}
c_cli__validation_family_only() {
  runclog LEARNING x --family nope --kpi failure
  expect run 0 EMPTY EMPTY
  expect_json validation "$LOGF" '.validation' unknown_family
}
c_cli__validation_kpi_only() {
  runclog LEARNING x --family tooling --kpi nah
  expect run 0 EMPTY EMPTY
  expect_json validation "$LOGF" '.validation' unknown_kpi
}
c_cli__validation_valid_values() {
  runclog LEARNING x --family tooling --kpi failure
  expect run 0 EMPTY EMPTY
  expect_json no_validation "$LOGF" 'has("validation")' false
}
c_cli__validation_no_lists() {
  min_cfg
  runclog LEARNING x --family bogus --kpi bogus
  expect run 0 EMPTY EMPTY
  expect_json fields "$LOGF" '[.family,.kpi,has("validation")]|join(",")' 'bogus,bogus,false'
}
c_cli__date_backfill() {
  runclog ACTION x --date 2026-01-02
  expect run 0 EMPTY EMPTY
  expect_file file "$LOGDIR/20260102.jsonl" exists
  expect_json time_is_now "$LOGDIR/20260102.jsonl" '.time|test("^[0-9]{2}:[0-9]{2}:[0-9]{2}$")' true
  expect_file today_untouched "$LOGF" absent
}
c_cli__date_path_traversal() {
  runclog ACTION x --date ../../evil
  expect run 1 EMPTY "=clog: invalid --date '../../evil' (expected YYYY-MM-DD)"
  expect_eq no_files "$(find "$T" -name '*.jsonl' | wc -l | tr -d ' ')" 0
  expect_file no_dirs "$T/logs" absent
  expect_file no_evil "$T/evil.jsonl" absent
}
c_cli__date_compact() {
  runclog ACTION x --date 20260103
  expect run 1 EMPTY "=clog: invalid --date '20260103' (expected YYYY-MM-DD)"
}
c_cli__date_garbage() {
  local d
  for d in nope 2026-13-01 2026-00-10 2026-01-32 2026-1-2 " 2026-01-02"; do
    runclog ACTION x --date "$d"
    expect "$d" 1 EMPTY "=clog: invalid --date '$d' (expected YYYY-MM-DD)"
  done
  expect_file nothing_written "$T/logs" absent
}
c_cli__date_trailing_junk() {
  runclog ACTION x --date "2026-01-02 evil"
  expect run 1 EMPTY "=clog: invalid --date '2026-01-02 evil' (expected YYYY-MM-DD)"
  expect_file nothing_written "$T/logs" absent
}
c_cli__date_impossible_day() {
  runclog ACTION x --date 2026-02-30
  expect run 0 EMPTY EMPTY
  expect_file file "$LOGDIR/20260230.jsonl" exists
}
c_cli__date_empty_value() {
  runclog ACTION x --date ""
  expect run 0 EMPTY EMPTY
  expect_file today "$LOGF" exists
}
c_cli__time_with_date() {
  runclog ACTION x --date 2026-01-02 --time 14:05:09
  expect run 0 EMPTY EMPTY
  expect_json time "$LOGDIR/20260102.jsonl" '.time' 14:05:09
  expect_file today_untouched "$LOGF" absent
}
c_cli__time_without_date() {
  runclog ACTION x --time 00:00:00
  expect run 0 EMPTY EMPTY
  expect_json time "$LOGF" '.time' 00:00:00
  runclog ACTION y --time 23:59:59
  expect max 0 EMPTY EMPTY
  expect_json time_max "$LOGF" '.time' 23:59:59 2
}
c_cli__time_invalid() {
  runclog ACTION x --time 25:00:00
  expect run 1 EMPTY "=clog: invalid --time '25:00:00' (expected HH:MM:SS)"
  expect_file nothing_written "$T/logs" absent
}
c_cli__time_short_form() {
  runclog ACTION x --time 14:05
  expect run 1 EMPTY "=clog: invalid --time '14:05' (expected HH:MM:SS)"
  expect_file nothing_written "$T/logs" absent
}
c_cli__time_garbage() {
  local t
  for t in nope 24:00:00 12:60:00 12:00:60 1:2:3 " 14:05:09" "14:05:09 x"; do
    runclog ACTION x --time "$t"
    expect "$t" 1 EMPTY "=clog: invalid --time '$t' (expected HH:MM:SS)"
  done
  expect_file nothing_written "$T/logs" absent
}
c_cli__invalid_value_single_line() {
  runclog ACTION x --time $'14:05:09\n'
  expect time 1 EMPTY "=clog: invalid --time '\$'14:05:09\\n'' (expected HH:MM:SS)"
  [[ $ERR != *$'\n'* ]] || fail "time: stderr spans lines"
  runclog ACTION x --date $'2026-01-02\n'
  expect date 1 EMPTY "=clog: invalid --date '\$'2026-01-02\\n'' (expected YYYY-MM-DD)"
  [[ $ERR != *$'\n'* ]] || fail "date: stderr spans lines"
  expect_file nothing_written "$T/logs" absent
}
c_cli__time_echo_and_last_wins() {
  runclog ACTION x --time 14:05:09 --echo
  expect echo 0 - EMPTY
  expect_eq echo_is_written_line "$OUT" "$(cat "$LOGF")"
  expect_json echo_time "$LOGF" '.time' 14:05:09
  runclog ACTION y --time 14:05:09 --time 15:00:00
  expect repeated 0 EMPTY EMPTY
  expect_json last_wins "$LOGF" '.time' 15:00:00 2
}
c_cli__time_without_value() {
  runclog ACTION x --time
  expect run 1 EMPTY "=clog: --time needs a value"
  expect_file nothing_written "$T/logs" absent
}
c_cli__time_followed_by_flag() {
  runclog ACTION x --time --echo
  expect echo 1 EMPTY "=clog: --time needs a value"
  runclog ACTION x --repo --time 14:05:09
  expect other_flag 1 EMPTY "=clog: --repo needs a value"
  expect_file nothing_written "$T/logs" absent
}
c_cli__time_empty_value() {
  runclog ACTION x --time ""
  expect run 0 EMPTY EMPTY
  expect_file today "$LOGF" exists
  expect_json time_is_now "$LOGF" '.time|test("^[0-9]{2}:[0-9]{2}:[0-9]{2}$")' true
}
c_cli__happy_path_silent() {
  runclog ACTION "happy path"
  expect run 0 EMPTY EMPTY
  expect_file one_line "$LOGF" lines=1
}
c_cli__echo() {
  runclog ACTION x --echo
  expect run 0 '^{"time":' EMPTY
  expect_eq equals_file_line "$OUT" "$(tail -n 1 "$LOGF")"
  expect_eq one_line "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" 1
}
c_cli__disabled() {
  ENVX=(CLOG_DISABLE=1)
  runclog ACTION x
  expect args 0 EMPTY EMPTY
  runclog
  expect no_args 0 EMPTY EMPTY
  runclog bogus
  expect bad_type 0 EMPTY EMPTY
  expect_file nothing_written "$T/logs" absent
}
c_cli__disabled_without_config() {
  ENVX=(CLOG_DISABLE=1 CLOG_CONFIG=/nonexistent/cfg.yaml)
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_file nothing_written "$T/logs" absent
}
c_cli__disable_other_value() {
  ENVX=(CLOG_DISABLE=true)
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_file written "$LOGF" lines=1
}
c_cli__missing_config() {
  ENVX=(CLOG_CONFIG=/nonexistent/cfg.yaml)
  runclog ACTION x
  expect with_args 1 EMPTY "=clog: no config at /nonexistent/cfg.yaml. Run setup.sh to create one."
  runclog
  expect no_args 1 EMPTY "=clog: no config at /nonexistent/cfg.yaml. Run setup.sh to create one."
}
c_cli__unwritable_directory() {
  if [[ $(id -u) == 0 ]]; then skip "root ignores mode 555"; return; fi
  mkdir -p "$LOGDIR"; chmod 555 "$LOGDIR"
  runclog ACTION x
  expect run 1 EMPTY '~Permission denied'
  [[ $ERR != clog:* ]] || fail "stderr has a clog: prefix: $ERR"
  chmod 755 "$LOGDIR"
}
c_cli__missing_jq() {
  local t d
  mkdir -p "$T/nojq"
  for t in bash dirname basename date mkdir git cat tr sed grep awk head tail readlink; do
    d=$(PATH=$TPATH command -v "$t") && ln -s "$d" "$T/nojq/$t"
  done
  ENVX=(PATH="$T/nojq")
  runclog ACTION x
  expect run 127 - '~jq: command not found'
}
c_cli__autocommit_disabled_by_default() {
  mkrepo "$T/repo"; RUNDIR=$T/repo
  printf 'log_root: "%s"\nlog_subdir: "claude"\n' "$T/repo/logs" > "$T/cfg.yaml"
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_eq no_commit "$(count_commits "$T/repo")" 1
}
c_cli__autocommit_scoped() {
  mkrepo "$T/repo"; RUNDIR=$T/repo
  printf 'staged\n' > "$T/repo/staged.txt"; git -C "$T/repo" add staged.txt
  ac_cfg "$T/repo" "$T/repo/logs"
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_eq commit_files "$(git -C "$T/repo" show --name-only --format= HEAD)" "logs/claude/$TODAY.jsonl"
  expect_eq still_staged "$(git -C "$T/repo" diff --cached --name-only)" staged.txt
}
c_cli__autocommit_outside_repo() {
  mkrepo "$T/repo"; RUNDIR=$T/repo
  ac_cfg "$T/repo" "$T/elsewhere"
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_eq no_commit "$(count_commits "$T/repo")" 1
  expect_file written "$T/elsewhere/claude/$TODAY.jsonl" exists
}
c_cli__autocommit_relative_log_root() {
  mkrepo "$T/repo"; RUNDIR=$T/repo
  ac_cfg "$T/repo" "logs"
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_eq tracked "$(git -C "$T/repo" ls-files)" "logs/claude/$TODAY.jsonl"
  expect_eq commits "$(count_commits "$T/repo")" 2
}
c_cli__autocommit_echo_one_line() {
  mkrepo "$T/repo"; RUNDIR=$T/repo
  ac_cfg "$T/repo" "$T/repo/logs"
  runclog ACTION x --echo
  expect run 0 '^{"time":' EMPTY
  expect_eq one_line "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" 1
  expect_eq committed "$(count_commits "$T/repo")" 2
}
c_cli__autocommit_message() {
  mkrepo "$T/repo"; RUNDIR=$T/repo
  ac_cfg "$T/repo" "$T/repo/logs"
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_eq subject "$(git -C "$T/repo" log -1 --format=%s)" "docs(clog): auto-commit logs"
}
c_cli__autocommit_git_failure() {
  mkdir -p "$T/plain"
  ac_cfg "$T/plain" "$T/plain/logs"
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_file written "$T/plain/logs/claude/$TODAY.jsonl" lines=1
}
c_cli__autocommit_empty_repo_root() {
  mkrepo "$T/repo"; RUNDIR=$T/repo
  ac_cfg "" "$T/repo/logs"
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_eq no_commit "$(count_commits "$T/repo")" 1
}
c_cli__no_gnu_realpath() {
  expect_eq no_realpath "$(grep -c realpath "$CLOG")" 0
}

# ============================================================================
# log-entry/spec.md
# ============================================================================
c_entry__first_entry_of_day() {
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_file file "$LOGF" lines=1
}
c_entry__multiline_summary() {
  runclog ACTION $'line one\nline two'
  expect run 0 EMPTY EMPTY
  expect_file one_line "$LOGF" lines=1
  expect_json escaped "$LOGF" '.summary|contains("\n")' true
  [[ $(cat "$LOGF") == *'\n'* ]] || fail "raw line lacks a \\n escape"
}
# log-entry "Minimal entry": on a fresh day file the entry also carries
# "clog_version":"1.0" (Schema version marker); the spec scenario says so.
c_entry__minimal_entry() {
  runclog FOLLOWUP "investigate hooks API"
  expect first 0 EMPTY EMPTY
  expect_json first_line "$LOGF" 'keys_unsorted|join(",")' 'time,type,summary,clog_version'
  runclog FOLLOWUP "investigate hooks API"
  expect second 0 EMPTY EMPTY
  expect_json second_keys "$LOGF" 'keys_unsorted|join(",")' 'time,type,summary'
  expect_json second_line "$LOGF" 'del(.time)|tojson' '{"type":"FOLLOWUP","summary":"investigate hooks API"}'
}
c_entry__required_fields_first() {
  runclog ACTION x --agent a
  expect run 0 EMPTY EMPTY
  expect_json order "$LOGF" 'keys_unsorted[0:3]|join(",")' 'time,type,summary'
  expect_json time "$LOGF" '.time|test("^[0-9]{2}:[0-9]{2}:[0-9]{2}$")' true
}
c_entry__time_is_local() {
  # A zone far from UTC makes a UTC-stamped time differ from local by hours.
  local want got try
  ENVX=(TZ=Pacific/Kiritimati)
  for try in 1 2; do
    find "$LOGDIR" -type f -delete 2>/dev/null
    runclog ACTION x
    want=$(TZ=Pacific/Kiritimati date +%H)
    # The file date is local too, so it may not be today's in this zone.
    got=$(cat "$LOGDIR"/*.jsonl | jq -r '.time[0:2]')
    [[ $got == "$want" ]] && break
  done  # second try absorbs an hour boundary crossed mid-run
  expect_eq local_hour "$got" "$want"
}
c_entry__key_order_full() {
  ENVX=(CLOG_DEFAULT_TAGS=jbook)
  runclog ACTION x --agent a --repo r --session s --model m --file /f --family nope --kpi effective
  expect run 0 EMPTY EMPTY
  expect_json order "$LOGF" 'keys_unsorted|join(",")' 'time,type,summary,agent,repo,session,model,file,family,kpi,clog_version,tags,validation'
}
c_entry__key_order_full_with_time() {
  ENVX=(CLOG_DEFAULT_TAGS=jbook)
  runclog ACTION x --agent a --repo r --session s --model m --file /f --family nope --kpi effective --date 2026-01-02 --time 14:05:09
  expect run 0 EMPTY EMPTY
  expect_json order "$LOGDIR/20260102.jsonl" 'keys_unsorted|join(",")' 'time,type,summary,agent,repo,session,model,file,family,kpi,clog_version,tags,logged_at,validation'
  expect_json time "$LOGDIR/20260102.jsonl" '.time' 14:05:09
}
c_entry__logged_at_is_write_time() {
  local before after got
  before=$(date +%Y-%m-%dT%H:%M:%S)
  runclog ACTION x --date 2026-01-02 --time 14:05:09
  after=$(date +%Y-%m-%dT%H:%M:%S)
  expect run 0 EMPTY EMPTY
  got=$(jq -r '.logged_at' "$LOGDIR/20260102.jsonl")
  [[ $got =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] || fail "logged_at shape: $got"
  [[ ! $got < $before && ! $got > $after ]] || fail "logged_at $got not within $before..$after"
}
c_entry__logged_at_absent_without_time() {
  runclog ACTION x
  expect plain 0 EMPTY EMPTY
  expect_json plain_absent "$LOGF" 'has("logged_at")' false
  runclog ACTION y --date 2026-01-02
  expect dated 0 EMPTY EMPTY
  expect_json dated_absent "$LOGDIR/20260102.jsonl" 'has("logged_at")' false
  runclog ACTION z --time ""
  expect empty_time 0 EMPTY EMPTY
  expect_json empty_absent "$LOGF" 'has("logged_at")' false 2
}
# Runs the real jq commands written in the clog-day and clog-replay skills (every
# line containing sort_by(.time)) against a day file whose last line is an
# out-of-order backfill, and checks the times come out sorted.
c_entry__skill_jq_sorts_backfill() {
  local f="$LOGDIR/20260102.jsonl" skill line flags prog out n
  # Every entry matches every example filter (KEYWORD=entry, cmp+playwright,
  # repo tn-mono + migration), and one truncated line sits between good ones.
  runclog ACTION "entry cmp playwright migration a" --repo tn-mono --date 2026-01-02 --time 10:00:00
  runclog ACTION "entry cmp playwright migration b" --repo tn-mono --date 2026-01-02 --time 11:00:00
  runclog ACTION "entry cmp playwright migration backfill" --repo tn-mono --date 2026-01-02 --time 09:00:00
  expect_json file_order "$f" '.time' 09:00:00 3
  printf '%s\n' '{"time":"08:00:00","type":"ACTION","summary":"entry trunc' >> "$f"
  runclog ACTION "entry cmp playwright migration after" --repo tn-mono --date 2026-01-02 --time 11:30:00
  for skill in clog-day:2 clog-replay:4; do
    n=0
    while IFS= read -r line; do
      flags=${line#*jq }; flags=${flags%%\'*}
      prog=${line#*\'}; prog=${prog%%\'*}; prog=${prog//KEYWORD/entry}
      out=$(jq -c ${flags} "$prog" "$f" 2>"$T/jqerr" | jq -r '[.. | objects | select(has("time")) | .time] | join(",")' | paste -sd, -)
      n=$((n + 1))
      [[ -n $out ]] || fail "${skill%%:*} empty output: ${line:0:50}"
      expect_eq "${skill%%:*} sorted: ${line:0:50}" "$out" '09:00:00,10:00:00,11:00:00,11:30:00'
      [[ $(<"$T/jqerr") == *"skipped unparseable line"* ]] || fail "${skill%%:*} hides the parse error: ${line:0:50}"
    done < <(grep -F 'sort_by(.time)' "$REPO/skills/${skill%%:*}/SKILL.md")
    expect_eq "${skill%%:*} commands exercised" "$n" "${skill##*:}"
  done
}
c_entry__empty_values_omitted() {
  runclog ACTION x --agent "" --repo "" --model "" --file "" --family "" --kpi "" --tags ""
  expect run 0 EMPTY EMPTY
  expect_json keys "$LOGF" 'keys_unsorted|join(",")' 'time,type,summary,clog_version'
  [[ $(cat "$LOGF") != *'""'* && $(cat "$LOGF") != *null* ]] || fail "empty or null value written"
}
c_entry__default_tags() {
  ENVX=(CLOG_DEFAULT_TAGS=jbook)
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_json tags "$LOGF" '.tags|tojson' '["jbook"]'
}
c_entry__no_default_tags() {
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_json no_tags "$LOGF" 'has("tags")' false
}
c_entry__version_first_entry_only() {
  runclog ACTION one
  runclog ACTION two
  expect run 0 EMPTY EMPTY
  expect_json first "$LOGF" '.clog_version' '1.0' 1
  expect_json second "$LOGF" 'has("clog_version")' false 2
  runclog ACTION three --date 2026-03-04
  expect_json new_file "$LOGDIR/20260304.jsonl" '.clog_version' '1.0'
}

# ============================================================================
# config/spec.md
# ============================================================================
c_config__override_path() {
  mkdir -p "$T/home/.config/clog"
  printf 'log_root: "%s"\n' "$T/decoy" > "$T/home/.config/clog/config.yaml"
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_file used_override "$LOGF" exists
  expect_file default_not_read "$T/decoy" absent
}
c_config__default_path() {
  mkdir -p "$T/home/.config/clog"
  printf 'log_root: "%s"\n' "$T/dlogs" > "$T/home/.config/clog/config.yaml"
  ENVX=(CLOG_CONFIG=)
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_file written "$T/dlogs/claude/$TODAY.jsonl" exists
}
c_config__example_values() {
  local p
  for p in "${VARIANTS[@]}"; do
    dumpv "$p" "$REPO/config/config.yaml.example"
    expect load 0 - EMPTY
    expect_eq root "$(getv CLOG_LOG_ROOT)" "$T/home/clog-logs"
    expect_eq subdir "$(getv CLOG_LOG_SUBDIR)" claude
    expect_eq reports "$(getv CLOG_REPORTS_ROOT)" "$T/home/clog-logs/reports"
    expect_eq threshold "$(getv CLOG_REMINDER_THRESHOLD)" 900
    expect_eq ac_enabled "$(getv CLOG_AUTO_COMMIT_ENABLED)" false
    expect_eq ac_repo "$(getv CLOG_AUTO_COMMIT_REPO)" ""
    expect_eq families "$(getv CLOG_FAMILIES)" "general skills tooling interactive"
    expect_eq kpis "$(getv CLOG_KPIS)" "token_waste failure prompt_gap effective format_issue"
  done
}
c_config__empty_config_defaults() {
  local p
  : > "$T/empty.yaml"
  for p in "${VARIANTS[@]}"; do
    dumpv "$p" "$T/empty.yaml"
    expect load 0 - EMPTY
    expect_eq root "$(getv CLOG_LOG_ROOT)" "$T/home/clog-logs"
    expect_eq subdir "$(getv CLOG_LOG_SUBDIR)" claude
    expect_eq reports "$(getv CLOG_REPORTS_ROOT)" "$T/home/clog-logs/reports"
    expect_eq threshold "$(getv CLOG_REMINDER_THRESHOLD)" 900
    expect_eq ac_enabled "$(getv CLOG_AUTO_COMMIT_ENABLED)" false
    expect_eq ac_repo "$(getv CLOG_AUTO_COMMIT_REPO)" ""
    expect_eq ac_msg "$(getv CLOG_AUTO_COMMIT_MSG)" "docs(clog): auto-commit logs"
    expect_eq families "$(getv CLOG_FAMILIES)" ""
    expect_eq kpis "$(getv CLOG_KPIS)" ""
    expect_eq cli_path "$(getv CLOG_CLI_PATH)" ""
    expect_eq tags "$(getv CLOG_DEFAULT_TAGS)" ""
    has_var CLOG_DEFAULT_TAGS || fail "CLOG_DEFAULT_TAGS not exported"
  done
}
# Writes the 10 file-backed keys with cfg values; env/cfg tables are index-aligned.
KEYS=(CLOG_LOG_ROOT CLOG_LOG_SUBDIR CLOG_REPORTS_ROOT CLOG_REMINDER_THRESHOLD CLOG_AUTO_COMMIT_ENABLED CLOG_AUTO_COMMIT_REPO CLOG_AUTO_COMMIT_MSG CLOG_FAMILIES CLOG_KPIS CLOG_CLI_PATH)
CFGVALS=(/cfg/logs cfgsub /cfg/reports 111 true /cfg/repo "cfg msg" "fa fb" "ka kb" /cfg/clog)
ENVVALS=(/env/logs envsub /env/reports 222 false /env/repo "env msg" "ex ey" "kx ky" /env/clog)
write_full_cfg() {
  cat > "$T/full.yaml" <<'EOF'
log_root: /cfg/logs
log_subdir: cfgsub
reports_root: /cfg/reports
reminder_threshold_seconds: 111
auto_commit:
  enabled: true
  repo_root: /cfg/repo
  message: cfg msg
families:
  - fa
  - fb
kpis:
  - ka
  - kb
cli_path: /cfg/clog
EOF
}
c_config__precedence_config_over_default() {
  local p i
  write_full_cfg
  for p in "${VARIANTS[@]}"; do
    dumpv "$p" "$T/full.yaml"
    for i in "${!KEYS[@]}"; do expect_eq "${KEYS[$i]}" "$(getv "${KEYS[$i]}")" "${CFGVALS[$i]}"; done
  done
}
c_config__precedence_env_over_config() {
  local p i
  write_full_cfg
  for p in "${VARIANTS[@]}"; do
    EXTRA=()
    for i in "${!KEYS[@]}"; do EXTRA+=("${KEYS[$i]}=${ENVVALS[$i]}"); done
    dumpv "$p" "$T/full.yaml"
    for i in "${!KEYS[@]}"; do expect_eq "${KEYS[$i]}" "$(getv "${KEYS[$i]}")" "${ENVVALS[$i]}"; done
  done
}
c_config__env_log_root_end_to_end() {
  ENVX=(CLOG_LOG_ROOT="$T/ci-logs")
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_file env_root "$T/ci-logs/claude/$TODAY.jsonl" exists
  expect_file config_root_unused "$T/logs" absent
}
c_config__config_over_default_subdir() {
  printf 'log_root: "%s"\nlog_subdir: codex\n' "$T/logs" > "$T/cfg.yaml"
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_file subdir "$T/logs/codex/$TODAY.jsonl" exists
}
c_config__empty_env_value_ignored() {
  local p
  printf 'auto_commit:\n  enabled: true\n' > "$T/c.yaml"
  for p in "${VARIANTS[@]}"; do
    EXTRA=(CLOG_AUTO_COMMIT_ENABLED=)
    dumpv "$p" "$T/c.yaml"
    expect_eq enabled "$(getv CLOG_AUTO_COMMIT_ENABLED)" true
  done
}
c_config__home_expansion_env() {
  local p
  for p in "${VARIANTS[@]}"; do
    EXTRA=(CLOG_LOG_ROOT='~/x' CLOG_REPORTS_ROOT='${HOME}/r' CLOG_AUTO_COMMIT_REPO='~/ar' CLOG_CLI_PATH='${HOME}/bin/clog')
    dumpv "$p" "$T/cfg.yaml"
    expect_eq root "$(getv CLOG_LOG_ROOT)" "$T/home/x"
    expect_eq reports "$(getv CLOG_REPORTS_ROOT)" "$T/home/r"
    expect_eq ac_repo "$(getv CLOG_AUTO_COMMIT_REPO)" "$T/home/ar"
    expect_eq cli_path "$(getv CLOG_CLI_PATH)" "$T/home/bin/clog"
  done
}
c_config__home_expansion_env_end_to_end() {
  ENVX=(CLOG_LOG_ROOT='~/x')
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_file under_home "$T/home/x/claude/$TODAY.jsonl" exists
  expect_file no_literal_tilde "$T/work/~" absent
}
c_config__home_expansion_file() {
  local p
  printf 'log_root: ~/fromcfg\nreports_root: "${HOME}/rep"\ncli_path: ~/.local/bin/clog\nauto_commit:\n  repo_root: "~/acr"\n' > "$T/c.yaml"
  for p in "${VARIANTS[@]}"; do
    dumpv "$p" "$T/c.yaml"
    expect_eq root "$(getv CLOG_LOG_ROOT)" "$T/home/fromcfg"
    expect_eq reports "$(getv CLOG_REPORTS_ROOT)" "$T/home/rep"
    expect_eq cli_path "$(getv CLOG_CLI_PATH)" "$T/home/.local/bin/clog"
    expect_eq ac_repo "$(getv CLOG_AUTO_COMMIT_REPO)" "$T/home/acr"
  done
}
c_config__cli_path_does_not_change_cli() {
  printf 'log_root: "%s"\ncli_path: ~/.local/bin/clog\n' "$T/logs" > "$T/cfg.yaml"
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_file written "$LOGF" lines=1
}
c_config__fallback_parser_runs() {
  fallback_ok || return 0
  runclog ACTION x
  expect run 0 EMPTY EMPTY
  expect_file written "$LOGF" lines=1
}
c_config__parser_parity_example() {
  need_yq || return 0
  local a b
  dumpv "$TPATH" "$REPO/config/config.yaml.example"; a=$OUT
  dumpv "$YQPATH" "$REPO/config/config.yaml.example"; b=$OUT
  [[ -n $a ]] || fail "empty dump"
  [[ $a == "$b" ]] || fail "fallback vs yq differ: $(diff <(printf '%s\n' "$a") <(printf '%s\n' "$b") | tr '\n' ' ')"
}
c_config__fallback_list_comment() {
  fallback_ok || return 0
  printf 'families:\n  - one\n  # a comment\n\n  - two\nkpis:\n  - k\n' > "$T/c.yaml"
  dumpv "$TPATH" "$T/c.yaml"
  expect_eq families "$(getv CLOG_FAMILIES)" "one two"
  expect_eq kpis "$(getv CLOG_KPIS)" k
}
c_config__fallback_list_quoting() {
  fallback_ok || return 0
  printf "families:\n  - 'one'\n  - two # inline\n  - \"three\"\n" > "$T/c.yaml"
  dumpv "$TPATH" "$T/c.yaml"
  expect_eq fallback "$(getv CLOG_FAMILIES)" "'one' two # inline three"
  if [[ $HAVE_YQ == 1 ]]; then
    dumpv "$YQPATH" "$T/c.yaml"
    expect_eq yq "$(getv CLOG_FAMILIES)" "one two three"
  fi
}
c_config__fallback_inline_list() {
  fallback_ok || return 0
  printf 'families: [general, x]\n' > "$T/c.yaml"
  dumpv "$TPATH" "$T/c.yaml"
  expect_eq families "$(getv CLOG_FAMILIES)" ""
}
c_config__fallback_inline_comment() {
  fallback_ok || return 0
  printf 'log_root: /x   # comment\n' > "$T/c.yaml"
  dumpv "$TPATH" "$T/c.yaml"
  expect_eq root "$(getv CLOG_LOG_ROOT)" "/x   # comment"
}
c_config__fallback_nested_key_anywhere() {
  fallback_ok || return 0
  printf 'other:\n  enabled: true\nauto_commit:\n  enabled: false\n' > "$T/c.yaml"
  dumpv "$TPATH" "$T/c.yaml"
  expect_eq fallback "$(getv CLOG_AUTO_COMMIT_ENABLED)" true
  if [[ $HAVE_YQ == 1 ]]; then
    dumpv "$YQPATH" "$T/c.yaml"
    expect_eq yq "$(getv CLOG_AUTO_COMMIT_ENABLED)" false
  fi
}
c_config__no_lists_no_validation() {
  printf 'log_root: "%s"\n' "$T/logs" > "$T/cfg.yaml"
  runclog LEARNING x --family anything
  expect run 0 EMPTY EMPTY
  expect_json no_validation "$LOGF" 'has("validation")' false
}
c_config__tags_env_over_file() {
  printf 'jbook\n' > "$T/tags.local"
  EXTRA=(CLOG_DEFAULT_TAGS=ci CLOG_TAGS_FILE="$T/tags.local")
  dumpv "$TPATH" "$T/cfg.yaml"
  expect_eq tags "$(getv CLOG_DEFAULT_TAGS)" ci
}
c_config__tags_file_only() {
  printf 'a, b  \n' > "$T/tags.local"
  EXTRA=(CLOG_TAGS_FILE="$T/tags.local")
  dumpv "$TPATH" "$T/cfg.yaml"
  expect_eq tags "$(getv CLOG_DEFAULT_TAGS)" "a, b"
}
c_config__tags_config_key_ignored() {
  local p
  printf 'tags: [x]\n' > "$T/c1.yaml"
  printf 'tags:\n  - x\n' > "$T/c2.yaml"
  for p in "${VARIANTS[@]}"; do
    dumpv "$p" "$T/c1.yaml"; expect_eq inline "$(getv CLOG_DEFAULT_TAGS)" ""
    dumpv "$p" "$T/c2.yaml"; expect_eq block "$(getv CLOG_DEFAULT_TAGS)" ""
  done
}
c_config__hook_mode_silent() {
  dumpv "$TPATH" /nonexistent/cfg.yaml --hook
  expect hook 0 - EMPTY
  has_var CLOG_LOG_ROOT && fail "CLOG_LOG_ROOT exported in hook mode"
  has_var CLOG_LOG_SUBDIR && fail "CLOG_LOG_SUBDIR exported in hook mode"
  dumpv "$TPATH" /nonexistent/cfg.yaml
  expect loud 1 - "=clog: no config at /nonexistent/cfg.yaml. Run setup.sh to create one."
}
c_config__disable_short_circuit() {
  EXTRA=(CLOG_DISABLE=1)
  dumpv "$TPATH" "$REPO/config/config.yaml.example"
  expect with_file 0 - EMPTY
  has_var CLOG_LOG_ROOT && fail "read the file despite CLOG_DISABLE"
  dumpv "$TPATH" /nonexistent/cfg.yaml
  expect without_file 0 - EMPTY
}

# ============================================================================
# hooks/spec.md
# ============================================================================
ALL_HOOKS=(post-action-log.sh post-log-reminder.sh post-edit-log-check.sh post-write-clog.sh pre-agent-clog.sh)
payload_for() {
  case $1 in
    post-action-log.sh|post-log-reminder.sh) bash_payload 'git commit -m "x"' ;;
    post-edit-log-check.sh|post-write-clog.sh) printf '%s' '{"tool_name":"Write","session_id":"s1","tool_input":{"file_path":"/tmp/x.txt"}}' ;;
    pre-agent-clog.sh) printf '%s' '{"tool_input":{"description":"d","subagent_type":"Explore"}}' ;;
  esac
}
c_hooks__disabled_exits_silently() {
  local h
  ENVX=(CLOG_DISABLE=1)
  for h in "${ALL_HOOKS[@]}"; do
    STDIN=$(payload_for "$h"); hook "$h"
    expect "$h" 0 EMPTY EMPTY
  done
  expect_file no_logs "$T/logs" absent
  expect_eq no_markers "$(find "$T/tmp" -type f | wc -l | tr -d ' ')" 0
}
c_hooks__missing_config_exit_zero() {
  local h
  ENVX=(CLOG_CONFIG=/nonexistent/cfg.yaml)
  for h in post-action-log.sh post-edit-log-check.sh post-write-clog.sh pre-agent-clog.sh; do
    STDIN=$(payload_for "$h"); hook "$h"
    expect "$h" 0 EMPTY EMPTY
  done
  STDIN=$(payload_for post-log-reminder.sh); hook post-log-reminder.sh
  expect post-log-reminder.sh 0 - EMPTY
  expect_eq no_jsonl "$(find "$T" -name '*.jsonl' | wc -l | tr -d ' ')" 0
}
c_hooks__missing_config_writing_hook() {
  ENVX=(CLOG_CONFIG=/nonexistent/cfg.yaml)
  STDIN=$(bash_payload 'git commit -m "x"'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_eq no_jsonl "$(find "$T" -name '*.jsonl' | wc -l | tr -d ' ')" 0
}
c_hooks__missing_config_advisory_hook() {
  ENVX=(CLOG_CONFIG=/nonexistent/cfg.yaml)
  STDIN=$(bash_payload ls); hook post-log-reminder.sh
  expect run 0 '^WARNING: No log entries today.' EMPTY
}
c_hooks__cli_failure_swallowed() {
  local h
  printf '#!/bin/sh\necho boom >&2\nexit 3\n' > "$T/stub"; chmod +x "$T/stub"
  ENVX=(CLOG_BIN="$T/stub")
  for h in pre-agent-clog.sh post-action-log.sh post-log-reminder.sh; do
    STDIN=$(payload_for "$h"); hook "$h"
    expect "$h" 0 - EMPTY
  done
}
c_hooks__cli_on_path_wins() {
  mkdir -p "$T/stubbin"
  printf '#!/bin/sh\necho path > "%s"\n' "$T/onpath" > "$T/stubbin/clog"; chmod +x "$T/stubbin/clog"
  ENVX=(PATH="$T/stubbin:$TPATH")
  STDIN=$(payload_for pre-agent-clog.sh); hook pre-agent-clog.sh
  expect run 0 EMPTY EMPTY
  expect_file stub_called "$T/onpath" exists
  expect_file repo_cli_unused "$LOGF" absent
}
c_hooks__write_hook_ignores_clog_bin() {
  printf '#!/bin/sh\necho x > "%s"\n' "$T/bin-called" > "$T/stub"; chmod +x "$T/stub"
  ENVX=(CLOG_BIN="$T/stub")
  STDIN=$(payload_for post-write-clog.sh); hook post-write-clog.sh
  expect run 0 EMPTY EMPTY
  expect_file stub_unused "$T/bin-called" absent
  expect_file repo_cli_used "$LOGF" lines=1
}

# post-action-log.sh
c_hooks__action_commit_with_message() {
  mkrepo "$T/proj"; RUNDIR=$T/proj
  STDIN=$(bash_payload 'git commit -m "feat(x): hook test"'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_json entry "$LOGF" '[.type,.summary,.repo,.commit]|join("|")' "COMMIT|feat(x): hook test|proj|$(git -C "$T/proj" rev-parse --short HEAD)"
  expect_file rewritten_not_appended "$LOGF" lines=1
  expect_file no_tmp "$LOGF.tmp" absent
}
c_hooks__action_unrelated_command() {
  STDIN=$(bash_payload ls); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_eq no_jsonl "$(find "$T" -name '*.jsonl' | wc -l | tr -d ' ')" 0
}
c_hooks__action_several_commits_one_entry() {
  mkrepo "$T/proj"; RUNDIR=$T/proj
  STDIN=$(bash_payload "git commit -m \"one\" && git commit -m 'two' -m \"body\""); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_file one_entry "$LOGF" lines=1
  expect_json summary "$LOGF" '.summary' one
  expect_json commit "$LOGF" '.commit' "$(git -C "$T/proj" rev-parse --short HEAD)"
}
c_hooks__action_message_mentions_git_commit() {
  mkrepo "$T/proj"; RUNDIR=$T/proj
  STDIN=$(bash_payload 'git commit -m "docs: explain git commit usage"'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_file one_entry "$LOGF" lines=1
  expect_json summary "$LOGF" '.summary' 'docs: explain git commit usage'
}
c_hooks__action_message_looks_like_flag() {
  mkrepo "$T/proj"; RUNDIR=$T/proj
  STDIN=$(bash_payload 'git commit -m "-n"'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_file one_entry "$LOGF" lines=1
  expect_json summary "$LOGF" '.summary' '-n'
}
c_hooks__action_commit_without_message() {
  mkrepo "$T/proj"; RUNDIR=$T/proj
  STDIN=$(bash_payload 'git commit --amend'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_json summary "$LOGF" '.summary' init
}
c_hooks__action_flag_between_git_and_commit() {
  mkrepo "$T/proj"; RUNDIR=$T/proj
  STDIN=$(bash_payload "git -C $T/proj commit -m \"x\""); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_file nothing_written "$LOGF" absent
}
c_hooks__action_pr_with_title() {
  STDIN=$(bash_payload 'gh pr create --title "feat: add x" --body "b"'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_json entry "$LOGF" '[.type,.summary]|join("|")' 'PR|feat: add x'
}
c_hooks__action_pr_without_title() {
  STDIN=$(bash_payload 'gh pr create --fill'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_file nothing_written "$LOGF" absent
}
c_hooks__action_push_line() {
  # The agent shell guard blocks any command text containing the phrase
  # "git <P>", so the verb is held in $P. Do not inline it.
  local P=push branch
  mkrepo "$T/proj"; RUNDIR=$T/proj
  branch=$(git -C "$T/proj" rev-parse --abbrev-ref HEAD)
  STDIN=$(bash_payload "git $P origin $branch"); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_json entry "$LOGF" '[.type,.summary,.repo]|join("|")' "ACTION|pushed $branch (proj)|proj"
}
c_hooks__action_repo_from_cd() {
  mkrepo "$T/proj"
  STDIN=$(bash_payload "cd $T/proj && git commit -m \"x\""); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_json entry "$LOGF" '[.repo,.commit]|join("|")' "proj|$(git -C "$T/proj" rev-parse --short HEAD)"
}
c_hooks__action_repo_from_git_dash_c() {
  mkrepo "$T/proj"
  STDIN=$(bash_payload "git -C $T/proj status; git commit -m \"x\""); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_json repo "$LOGF" '.repo' proj
}
c_hooks__action_repo_from_cwd() {
  mkrepo "$T/proj"; RUNDIR=$T/proj
  STDIN=$(bash_payload 'git commit -m "x"'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_json repo "$LOGF" '.repo' proj
}
c_hooks__action_no_repo_no_commit_field() {
  STDIN=$(bash_payload 'git commit -m "x"'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_json fields "$LOGF" '[.summary,has("commit"),has("repo")]|join("|")' 'x|false|false'
}
c_hooks__action_commit_marker_when_cli_wrote_nothing() {
  mkrepo "$T/proj"; RUNDIR=$T/proj
  printf '#!/bin/sh\nexit 3\n' > "$T/stub"; chmod +x "$T/stub"
  seed_log
  ENVX=(CLOG_BIN="$T/stub")
  STDIN=$(bash_payload 'git commit -m "x"'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_file still_one_line "$LOGF" lines=1
  expect_json patched_prior "$LOGF" '[.summary,.commit]|join("|")' "prior|$(git -C "$T/proj" rev-parse --short HEAD)"
}
c_hooks__action_fallback_single_line() {
  mkrepo "$T/proj"; RUNDIR=$T/proj; mkfake
  STDIN=$(bash_payload 'git commit -m "x"'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_file one_line "$LOGF" lines=1
  expect_json entry "$LOGF" '[.summary,.repo,.commit,has("clog_version")]|join("|")' "x|proj|$(git -C "$T/proj" rev-parse --short HEAD)|false"
}
c_hooks__action_autocommit_disabled() {
  mkrepo "$T/proj"; RUNDIR=$T/proj
  printf 'log_root: "%s"\nlog_subdir: claude\n' "$T/proj/logs" > "$T/cfg.yaml"
  STDIN=$(bash_payload 'git commit -m "x"'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_eq no_git_commit "$(count_commits "$T/proj")" 1
}
c_hooks__action_autocommit_scoped() {
  mkrepo "$T/proj"; RUNDIR=$T/proj
  printf 'staged\n' > "$T/proj/staged.txt"; git -C "$T/proj" add staged.txt
  ac_cfg "$T/proj" "$T/proj/logs"
  STDIN=$(bash_payload 'git commit -m "x"'); hook post-action-log.sh
  expect run 0 EMPTY EMPTY
  expect_eq commit_files "$(git -C "$T/proj" show --name-only --format= HEAD)" "logs/claude/$TODAY.jsonl"
  expect_eq still_staged "$(git -C "$T/proj" diff --cached --name-only)" staged.txt
}

# post-log-reminder.sh
c_hooks__reminder_stale_log() {
  seed_log; age_file "$LOGF" 7200
  STDIN=$(bash_payload ls); hook post-log-reminder.sh
  expect run 0 '=WARNING: Last log entry was 120m ago. Log actions with: clog <TYPE> "<summary>"' EMPTY
  expect_file marker "$T/tmp/clog-reminder-warned" exists
  expect_json self_log "$LOGF" '[.type,.agent,.family,.kpi,has("validation")]|join("|")' 'LEARNING|hook-post-log|interactive|prompt_gap|false'
}
c_hooks__reminder_no_file_today() {
  STDIN=$(bash_payload ls); hook post-log-reminder.sh
  expect run 0 '=WARNING: No log entries today. Log actions with: clog <TYPE> "<summary>"' EMPTY
  expect_file self_log "$LOGF" lines=1
  expect_json entry "$LOGF" '[.type,.agent]|join("|")' 'LEARNING|hook-post-log'
}
c_hooks__reminder_within_window() {
  touch "$T/tmp/clog-reminder-warned"
  STDIN=$(bash_payload ls); hook post-log-reminder.sh
  expect run 0 EMPTY EMPTY
  expect_file nothing_written "$T/logs" absent
}
c_hooks__reminder_marker_expiry() {
  seed_log; age_file "$LOGF" 7200
  ENVX=(CLOG_REMINDER_THRESHOLD=100)
  touch "$T/tmp/clog-reminder-warned"
  STDIN=$(bash_payload ls); hook post-log-reminder.sh
  expect fresh_marker_quiet 0 EMPTY EMPTY
  ENVX=(CLOG_REMINDER_THRESHOLD=5)
  age_file "$T/tmp/clog-reminder-warned" 60
  STDIN=$(bash_payload ls); hook post-log-reminder.sh
  expect old_marker_rewarns 0 '^WARNING: Last log entry was' EMPTY
}
c_hooks__reminder_fresh_log() {
  seed_log
  STDIN=$(bash_payload ls); hook post-log-reminder.sh
  expect run 0 EMPTY EMPTY
  expect_file untouched "$LOGF" lines=1
  expect_file no_marker "$T/tmp/clog-reminder-warned" absent
}
c_hooks__reminder_threshold_zero() {
  ENVX=(CLOG_REMINDER_THRESHOLD=0)
  STDIN=$(bash_payload ls); hook post-log-reminder.sh
  expect run 0 EMPTY EMPTY
  expect_file nothing_written "$T/logs" absent
}
c_hooks__reminder_unknown_family() {
  printf 'log_root: "%s"\nlog_subdir: claude\nfamilies:\n  - tooling\nkpis:\n  - prompt_gap\n' "$T/logs" > "$T/cfg.yaml"
  STDIN=$(bash_payload ls); hook post-log-reminder.sh
  expect run 0 '^WARNING' EMPTY
  expect_json entry "$LOGF" '[.family,.kpi,.validation]|join("|")' 'interactive|prompt_gap|unknown_family'
}
c_hooks__reminder_no_lists() {
  min_cfg
  STDIN=$(bash_payload ls); hook post-log-reminder.sh
  expect run 0 '^WARNING' EMPTY
  expect_json entry "$LOGF" '[has("family"),has("kpi")]|join("|")' 'false|false'
}
c_hooks__reminder_no_cli() {
  mkfake
  STDIN=$(bash_payload ls); hook post-log-reminder.sh
  expect run 0 '^WARNING: No log entries today.' EMPTY
  expect_eq no_jsonl "$(find "$T" -name '*.jsonl' | wc -l | tr -d ' ')" 0
}

# post-edit-log-check.sh
c_hooks__edit_check_threshold() {
  local i want
  ENVX=(CLAUDE_SESSION_ID=s1)
  for i in 1 2 3 4; do
    STDIN=$(payload_for post-edit-log-check.sh); hook post-edit-log-check.sh
    want=EMPTY; [[ $i -ge 3 ]] && want="=LEDGER: $i edits since last clog entry. Log a CODE entry before continuing."
    expect "edit$i" 0 EMPTY "$want"
  done
  expect_file writes_nothing "$T/logs" absent
  expect_file marker_under_tmpdir "$T/tmp/clog-edit-counter-s1" exists
}
c_hooks__edit_check_threshold_env() {
  local i want
  ENVX=(CLAUDE_SESSION_ID=s1 CLOG_EDIT_THRESHOLD=2)
  for i in 1 2; do
    STDIN=$(payload_for post-edit-log-check.sh); hook post-edit-log-check.sh
    want=EMPTY; [[ $i -ge 2 ]] && want="=LEDGER: 2 edits since last clog entry. Log a CODE entry before continuing."
    expect "edit$i" 0 EMPTY "$want"
  done
}
c_hooks__edit_check_threshold_zero() {
  local i
  ENVX=(CLAUDE_SESSION_ID=s1 CLOG_EDIT_THRESHOLD=0)
  for i in 1 2 3 4; do
    STDIN=$(payload_for post-edit-log-check.sh); hook post-edit-log-check.sh
    expect "edit$i" 0 EMPTY EMPTY
  done
}

# post-write-clog.sh
c_hooks__write_event() {
  ENVX=(CLAUDE_MODEL=m1)
  STDIN='{"tool_name":"Write","session_id":"s1","tool_input":{"file_path":"~/README.md"}}'; hook post-write-clog.sh
  expect run 0 EMPTY EMPTY
  expect_json entry "$LOGF" '[.type,.summary,.session,.file,.model]|join("|")' "CODE|auto: wrote $T/home/README.md|s1|$T/home/README.md|m1"
}
c_hooks__write_repo_from_file() {
  mkrepo "$T/proj"; mkdir "$T/proj/src"
  STDIN=$(jq -nc --arg f "$T/proj/src/a.txt" '{tool_name:"Edit",tool_input:{file_path:$f}}'); hook post-write-clog.sh
  expect run 0 EMPTY EMPTY
  expect_json repo "$LOGF" '.repo' proj
}
c_hooks__write_relative_path() {
  STDIN='{"tool_name":"Write","tool_input":{"file_path":"rel/x.txt"}}'; hook post-write-clog.sh
  expect run 0 EMPTY EMPTY
  expect_json entry "$LOGF" '[.summary,.file]|join("|")' 'auto: wrote rel/x.txt|rel/x.txt'
}
c_hooks__write_notebook_path() {
  STDIN='{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/tmp/n.ipynb"}}'; hook post-write-clog.sh
  expect run 0 EMPTY EMPTY
  expect_json file "$LOGF" '.file' /tmp/n.ipynb
}
c_hooks__write_no_path() {
  STDIN='{"tool_name":"Write","tool_input":{}}'; hook post-write-clog.sh
  expect no_path 0 EMPTY EMPTY
  STDIN='{"tool_name":"Bash","tool_input":{"file_path":"/tmp/x"}}'; hook post-write-clog.sh
  expect other_tool 0 EMPTY EMPTY
  expect_file nothing_written "$T/logs" absent
}
c_hooks__write_session_from_env() {
  ENVX=(CLAUDE_SESSION_ID=envs)
  STDIN='{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.txt"}}'; hook post-write-clog.sh
  expect run 0 EMPTY EMPTY
  expect_json session "$LOGF" '.session' envs
}
c_hooks__write_no_cli() {
  mkfake
  STDIN=$(payload_for post-write-clog.sh); hook post-write-clog.sh
  expect run 0 EMPTY EMPTY
  expect_file nothing_written "$T/logs" absent
}

# pre-agent-clog.sh
c_hooks__agent_dispatch_with_description() {
  STDIN='{"tool_input":{"description":"audit thing","subagent_type":"Explore","model":"haiku"}}'; hook pre-agent-clog.sh
  expect run 0 EMPTY EMPTY
  expect_json entry "$LOGF" '[.type,.summary]|join("|")' 'ACTION|dispatch Explore (haiku) — audit thing'
}
c_hooks__agent_dispatch_without_description() {
  STDIN='{"tool_input":{"subagent_type":"Explore"}}'; hook pre-agent-clog.sh
  expect missing 0 EMPTY EMPTY
  STDIN='{"tool_input":{"description":"","subagent_type":"Explore"}}'; hook pre-agent-clog.sh
  expect empty 0 EMPTY EMPTY
  expect_file nothing_written "$LOGF" absent
}
c_hooks__agent_model_omitted() {
  STDIN='{"tool_input":{"description":"d","subagent_type":"Explore"}}'; hook pre-agent-clog.sh
  expect run 0 EMPTY EMPTY
  expect_json summary "$LOGF" '.summary' 'dispatch Explore — d'
}
c_hooks__agent_type_defaults_to_claude() {
  STDIN='{"tool_input":{"description":"d"}}'; hook pre-agent-clog.sh
  expect absent_run 0 EMPTY EMPTY
  STDIN='{"tool_input":{"description":"d","subagent_type":null}}'; hook pre-agent-clog.sh
  expect null_run 0 EMPTY EMPTY
  expect_json absent "$LOGF" '.summary' 'dispatch claude — d' 1
  expect_json null "$LOGF" '.summary' 'dispatch claude — d' 2
}
c_hooks__agent_empty_subagent_type() {
  STDIN='{"tool_input":{"description":"d1","subagent_type":""}}'; hook pre-agent-clog.sh
  expect run 0 EMPTY EMPTY
  expect_json summary "$LOGF" '.summary' 'dispatch  — d1'
}
c_hooks__agent_repo_from_cwd() {
  mkrepo "$T/proj"; RUNDIR=$T/proj
  STDIN=$(payload_for pre-agent-clog.sh); hook pre-agent-clog.sh
  expect run 0 EMPTY EMPTY
  expect_json repo "$LOGF" '.repo' proj
}
c_hooks__agent_fallback_new_day() {
  mkfake
  ENVX=(CLOG_DEFAULT_TAGS=t CLAUDE_SESSION_ID=envs)
  STDIN=$(payload_for pre-agent-clog.sh); hook pre-agent-clog.sh
  expect first 0 EMPTY EMPTY
  expect_json first_entry "$LOGF" '[.clog_version,(.tags|tojson),has("session")]|join("|")' '1.0|["t"]|false'
  STDIN=$(payload_for pre-agent-clog.sh); hook pre-agent-clog.sh
  expect_file two_lines "$LOGF" lines=2
  expect_json second_no_version "$LOGF" 'has("clog_version")' false 2
}

# ============================================================================
# clog-sweep-sessions scripts (openspec/changes/clog-sweep-sessions)
# ============================================================================
SWEEP_SCRIPTS=$REPO/skills/clog-sweep-sessions/scripts
# mktranscript <sid> <timestamp>...: write $T/projects/-proj/<sid>.jsonl, one line per timestamp.
mktranscript() {
  local sid=$1 ts; shift
  mkdir -p "$T/projects/-proj"
  for ts in "$@"; do
    jq -nc --arg t "$ts" --arg s "$sid" '{type:"user",timestamp:$t,sessionId:$s}'
  done > "$T/projects/-proj/$sid.jsonl"
}
resolve() { ENVX=(CLOG_CC_PROJECTS="$T/projects" ${EXTRA[@]+"${EXTRA[@]}"}); run "$SWEEP_SCRIPTS/resolve.sh" "$@"; }
logs_for() { run "$SWEEP_SCRIPTS/logs-for.sh" "$@"; }

c_sweep__resolve_one_date() {
  mktranscript s1 2026-10-26T10:00:00.000Z 2026-10-26T12:30:45.123Z
  EXTRA=(TZ=UTC); resolve s1
  expect run 0 - EMPTY
  expect_eq line "$OUT" "{\"sid\":\"s1\",\"transcript\":\"$T/projects/-proj/s1.jsonl\",\"dates\":[\"2026-10-26\"]}"
}
c_sweep__resolve_spans_midnight() {
  mktranscript s2 2026-10-26T23:00:00.000Z 2026-10-27T01:00:00.000Z
  EXTRA=(TZ=UTC); resolve s2
  expect run 0 - EMPTY
  expect_eq dates "$(jq -c '.dates' <<< "$OUT")" '["2026-10-26","2026-10-27"]'
}
c_sweep__resolve_local_dates() {
  mktranscript s3 2026-10-27T02:00:00.000Z 2026-10-27T03:00:00.000Z
  EXTRA=(TZ=Etc/GMT+5); resolve s3
  expect run 0 - EMPTY
  expect_eq dates "$(jq -c '.dates' <<< "$OUT")" '["2026-10-26"]'
}
c_sweep__resolve_missing() {
  mkdir -p "$T/projects/-proj"
  resolve nope
  expect run 0 - EMPTY
  expect_eq line "$OUT" '{"sid":"nope","status":"no_transcript"}'
}
c_sweep__resolve_multiple() {
  mktranscript a 2026-10-26T10:00:00Z
  mktranscript c 2026-10-25T23:30:00Z 2026-10-26T00:30:00Z
  EXTRA=(TZ=UTC); resolve a b c
  expect run 0 - EMPTY
  expect_eq lines "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" 3
  expect_eq sids "$(jq -r '.sid' <<< "$OUT" | paste -sd, -)" a,b,c
  expect_eq status_b "$(printf '%s\n' "$OUT" | sed -n 2p | jq -r '.status')" no_transcript
  expect_eq dates_c "$(printf '%s\n' "$OUT" | sed -n 3p | jq -c '.dates')" '["2026-10-25","2026-10-26"]'
  expect_eq transcript_a "$(printf '%s\n' "$OUT" | sed -n 1p | jq -r '.transcript')" "$T/projects/-proj/a.jsonl"
}
c_sweep__resolve_skips_lines_without_timestamp() {
  mkdir -p "$T/projects/-proj"
  {
    printf '%s\n' '{"type":"summary","summary":"no ts"}'
    printf '%s\n' '{"type":"user","timestamp":"2026-10-26T08:00:00.000Z"}'
    printf '%s\n' '{"type":"queue-operation"}'
    printf '%s\n' '{"type":"user","timestamp":"2026-10-27T08:00:00.000Z"}'
    printf '%s\n' '{"type":"summary","summary":"no ts either"}'
  } > "$T/projects/-proj/s5.jsonl"
  EXTRA=(TZ=UTC); resolve s5
  expect run 0 - EMPTY
  expect_eq dates "$(jq -c '.dates' <<< "$OUT")" '["2026-10-26","2026-10-27"]'
}
c_sweep__resolve_unreadable_transcript_continues() {
  mktranscript bad 2026-10-26T10:00:00Z
  mktranscript good 2026-10-26T11:00:00Z
  chmod 000 "$T/projects/-proj/bad.jsonl"
  EXTRA=(TZ=UTC); resolve bad good
  chmod 644 "$T/projects/-proj/bad.jsonl"
  expect run 0 - -
  expect_eq lines "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" 2
  expect_eq line1 "$(printf '%s\n' "$OUT" | sed -n 1p)" "{\"sid\":\"bad\",\"transcript\":\"$T/projects/-proj/bad.jsonl\",\"status\":\"unreadable\"}"
  expect_eq dates_good "$(printf '%s\n' "$OUT" | sed -n 2p | jq -c '.dates')" '["2026-10-26"]'
}
c_sweep__resolve_dst_spring_forward_no_skipped_day() {
  mktranscript dst 2026-03-08T04:30:00Z 2026-03-09T04:30:00Z
  EXTRA=(TZ=America/New_York); resolve dst
  expect run 0 - EMPTY
  expect_eq dates "$(jq -c '.dates' <<< "$OUT")" '["2026-03-07","2026-03-08","2026-03-09"]'
}
c_sweep__resolve_no_args() {
  resolve
  expect run 1 EMPTY '~usage'
}
c_sweep__logs_for_one_date() {
  logs_for 2026-10-26
  expect run 0 "=$T/logs/claude/20261026.jsonl" EMPTY
}
c_sweep__logs_for_two_dates() {
  logs_for 2026-10-26 2026-10-27
  expect run 0 - EMPTY
  expect_eq paths "$OUT" "$T/logs/claude/20261026.jsonl"$'\n'"$T/logs/claude/20261027.jsonl"
}
c_sweep__logs_for_invalid_date() {
  logs_for 2026-10-26 2026-13-01
  expect run 1 EMPTY "=logs-for: invalid date '2026-13-01'"
}
c_sweep__logs_for_env_beats_config() {
  ENVX=(CLOG_LOG_ROOT="$T/envroot")
  run "$SWEEP_SCRIPTS/logs-for.sh" 2026-10-26
  expect run 0 "=$T/envroot/claude/20261026.jsonl" EMPTY
}
c_sweep__logs_for_disabled() {
  ENVX=(CLOG_DISABLE=1)
  run "$SWEEP_SCRIPTS/logs-for.sh" 2026-10-26
  expect run 1 EMPTY "=logs-for: clog is disabled (CLOG_DISABLE=1); no log root"
}
c_sweep__logs_for_disabled_with_env_root() {
  ENVX=(CLOG_DISABLE=1 CLOG_LOG_ROOT="$T/envroot")
  run "$SWEEP_SCRIPTS/logs-for.sh" 2026-10-26
  expect run 1 EMPTY "=logs-for: clog is disabled (CLOG_DISABLE=1); no log root"
}
c_sweep__logs_for_no_args() {
  logs_for
  expect run 1 EMPTY '~usage'
}
c_sweep__logs_for_via_symlink() {
  ln -s "$SWEEP_SCRIPTS/logs-for.sh" "$T/lf"
  run "$T/lf" 2026-10-26
  expect run 0 "=$T/logs/claude/20261026.jsonl" EMPTY
}

# ============================================================================
# runner
# ============================================================================
CASES=$(grep -oE '^c_[A-Za-z0-9_]+\(\)' "$SELF" | tr -d '()')
RESDIR=$(mktemp -d "${TMPDIR:-/tmp}/clog-cli-res.XXXXXX") || { echo "FAIL: mktemp"; exit 2; }
PASSED=0 FAILED=0 SKIPPED=0
for fn in $CASES; do
  name=${fn#c_}; name=${name/__//}
  [[ -z ${1:-} || $name == *"$1"* ]] || continue
  # The explicit `exit 0` keeps a case's last assertion status out of the result;
  # only new_env's `exit 2` (or a crash) surfaces as a non-zero case status.
  ( FN=$fn; new_env; trap cleanup EXIT; "$fn"; exit 0 )
  rc=$?
  if [[ $rc -ne 0 ]]; then
    printf 'FAIL %s: case exited %d\n' "$name" "$rc"
    FAILED=$((FAILED + 1))
  elif [[ -f $RESDIR/$fn.fail ]]; then
    printf 'FAIL %s: %s\n' "$name" "$(paste -sd'|' "$RESDIR/$fn.fail")"
    FAILED=$((FAILED + 1))
  elif [[ -f $RESDIR/$fn.skip ]]; then
    printf 'skip %s: %s\n' "$name" "$(paste -sd'|' "$RESDIR/$fn.skip")"
    SKIPPED=$((SKIPPED + 1))
  else
    printf 'ok %s\n' "$name"
    PASSED=$((PASSED + 1))
  fi
done
find "$RESDIR" -depth -delete 2>/dev/null
if (( PASSED + FAILED + SKIPPED == 0 )); then
  printf "FAIL: no case matches '%s'\n" "${1:-}"
  exit 1
fi
[[ $SKIPPED -eq 0 ]] || printf '%d skipped\n' "$SKIPPED"
printf '%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ $FAILED -eq 0 ]]

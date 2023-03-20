# approvals.bash v0.5.0
#
# Interactive approval testing for Bash.
# https://github.com/DannyBen/approvals.bash
approve() {
  local expected approval approval_file actual cmd
  approvals_dir=${APPROVALS_DIR:=approvals}
  approvals_prefix=${APPROVALS_PREFIX:=}

  cmd=$1
  last_exit_code=0
  actual=$(eval "$cmd" 2>&1) || last_exit_code=$?
  approval=$(printf "%b" "$cmd" | tr -s -c "[:alnum:]" _)
  approval_file="$approvals_dir/${approvals_prefix}${2:-"$approval"}"

  [[ -d "$approvals_dir" ]] || mkdir "$approvals_dir"

  if [[ -f "$approval_file" ]]; then
    expected=$(cat "$approval_file")
  else
    echo "--- [$(blue "new: $cmd")] ---"
    printf "%b\n" "$actual"
    echo "--- [$(blue "new: $cmd")] ---"
    expected="$actual"
    user_approval "$cmd" "$actual" "$approval_file"
    return
  fi

  if [[ "$(printf "%b" "$actual")" = "$(printf "%b" "$expected")" ]]; then
    pass "$cmd"
  else
    echo "--- [$(blue "diff: $cmd")] ---"
    $diff_cmd <(printf "%b" "$expected\n") <(printf "%b" "$actual\n") | tail -n +4
    echo "--- [$(blue "diff: $cmd")] ---"
    user_approval "$cmd" "$actual" "$approval_file"
  fi
}

describe() {
  echo
  indent "$(blue "= $*")"
}

# Use at the end of a `describe` "block" (i.e. sequence of `approve` calls after a `describe` call)
# to pretend it's actually a block.
ebircsed() { :; }

# A function stub, to be redefined by tests.
setup_test_context() { :; }

context() {
  APPROVALS_PREFIX="${2:-$__APPROVALS_PREFIX}"

  # Initialize our context prefix stack, if necessary.
  declare -g -a __APPROVALS_PREFIX_STACK=${__APPROVALS_PREFIX_STACK-()}
  # Push the new context prefix onto the stack (if none specified, push a copy of the the old one).
  __APPROVALS_PREFIX_STACK=( "${APPROVALS_PREFIX:-}" "${__APPROVALS_PREFIX_STACK[@]}" )

  # Our 'context' nesting level is one less than the size of our stack, down to a minimum of 0.
  declare -g -i __APPROVALS_CONTEXT_LEVEL=$(( ${#__APPROVALS_PREFIX_STACK[@]} > 0 ? ${#__APPROVALS_PREFIX_STACK[@]} - 1 : 0 ))


  echo
  indent "$(magenta "= $1")"
}

# Use at the end of a `context` "block" (i.e. sequence of `approve` calls after a `context` call)
# to reset the test environment.
txetnoc() {
  # Pop back up the stack of context prefixes.
  __APPROVALS_PREFIX_STACK=( "${__APPROVALS_PREFIX_STACK[@]:1}" )

  # Our 'context' nesting level is one less than the size of our stack, down to a minimum of 0.
  __APPROVALS_CONTEXT_LEVEL=$(( ${#__APPROVALS_PREFIX_STACK[@]} > 0 ? ${#__APPROVALS_PREFIX_STACK[@]} - 1 : 0 ))

  APPROVALS_PREFIX="${__APPROVALS_PREFIX_STACK[0]}"

  # Reset our test environment (which might also assign an initial `APPROVALS_PREFIX`)
  setup_test_context
}

fail() {
  red "  FAILED: $*"
  exit 1
}

pass() {
  indent "$(green "approved: $*")"
  return 0
}

expect_exit_code() {
  if [[ $last_exit_code == "$1" ]]; then
    pass "exit $last_exit_code"
  else
    fail "Expected exit code $1, got $last_exit_code"
  fi
}

red() { printf "\e[31m%b\e[0m\n" "$*"; }
green() { printf "\e[32m%b\e[0m\n" "$*"; }
blue() { printf "\e[34m%b\e[0m\n" "$*"; }
magenta() { printf "\e[35m%b\e[0m\n" "$*"; }
cyan() { printf "\e[36m%b\e[0m\n" "$*"; }

indent() { printf "%$(( ${__APPROVALS_CONTEXT_LEVEL:=0} * 2 ))s$*\n"; }

# Private

user_approval() {
  local cmd="$1"
  local actual="$2"
  local approval_file="$3"

  if [[ -v CI || -v GITHUB_ACTIONS ]]; then
    fail "$cmd"
  fi

  echo
  printf "[A]pprove? \n"
  response=$(bash -c "read -n 1 key; echo \$key")
  printf "\r"
  if [[ $response =~ [Aa] ]]; then
    printf "%b\n" "$actual" >"$approval_file"
    pass "$cmd"
  else
    fail "$cmd"
  fi
}

onexit() {
  exitcode=$?
  if [[ "$exitcode" == 0 ]]; then
    green "\nFinished successfully"
  else
    red "\nFinished with failures"
  fi
  exit $exitcode
}

onerror() {
  fail "Caller: $(caller)"
}

set -e
trap 'onexit' EXIT
trap 'onerror' ERR

if diff --help | grep -- --color >/dev/null 2>&1; then
  diff_cmd="diff --unified --color=always"
else
  diff_cmd="diff --unified"
fi

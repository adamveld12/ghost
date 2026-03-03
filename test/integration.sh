#!/usr/bin/env bash
# Ghost integration test suite
set -euo pipefail

GHOST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_DIR="$(mktemp -d)"
export PATH="${GHOST_ROOT}/bin:$PATH"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf "  \033[32m✓\033[0m %s\n" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf "  \033[31m✗\033[0m %s\n" "$1"; }
assert() {
  if eval "$1" 2>/dev/null; then
    pass "$2"
  else
    fail "$2"
  fi
}

section() { printf "\n\033[1m%s\033[0m\n" "$1"; }

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

# Configure git identity for test commits
export GIT_AUTHOR_NAME="Ghost Test"
export GIT_AUTHOR_EMAIL="ghost@test.local"
export GIT_COMMITTER_NAME="Ghost Test"
export GIT_COMMITTER_EMAIL="ghost@test.local"

section "Test 1: ghost init"
cd "$TEST_DIR"
git init -q
ghost init

assert '[ -x .git/hooks/prepare-commit-msg ]' "hook installed and executable"
assert '[ -d .ghost ]' ".ghost directory created"

section "Test 2: ghost commit generates code"
ghost commit -m "Create a C program called hello.c that prints 'Hello, Ghost!' to stdout and exits 0"

assert '[ -f hello.c ]' "hello.c was created"
assert 'git log --oneline -1 | grep -q "Create a C program"' "commit message contains prompt"
assert 'git log -1 --format=%B | grep -q "ghost-meta"' "commit has ghost metadata"
assert 'git log -1 --format=%B | grep -q "ghost-prompt:"' "commit has ghost-prompt field"
assert 'git log -1 --format=%B | grep -q "ghost-model:"' "commit has ghost-model field"
assert 'git log -1 --format=%B | grep -q "ghost-session:"' "commit has ghost-session field"
assert 'git log -1 --format=%B | grep -q "ghost-files:"' "commit has ghost-files field"

section "Test 3: generated C code compiles"
cc -o hello hello.c
assert '[ -x hello ]' "hello.c compiled successfully"

section "Test 4: compiled program runs correctly"
OUTPUT="$(./hello)"
assert '[ "$OUTPUT" = "Hello, Ghost!" ]' "program outputs 'Hello, Ghost!'"

section "Test 5: ghost log shows the commit"
GHOST_LOG="$(ghost log)"
assert 'echo "$GHOST_LOG" | grep -q "Create a C program"' "ghost log shows prompt"

section "Test 6: ghost commit --dry-run does not commit"
BEFORE="$(git rev-parse HEAD)"
ghost commit --dry-run -m "add a Makefile" || true
AFTER="$(git rev-parse HEAD)"
assert '[ "$BEFORE" = "$AFTER" ]' "dry-run did not create a commit"

section "Test 7: GHOST_SKIP passthrough"
echo "// manual" > manual.c
git add manual.c
GHOST_SKIP=1 ghost commit -m "manual commit"
assert '! git log -1 --format=%B | grep -q "ghost-meta"' "GHOST_SKIP skips ghost metadata"

# ---------------------------------------------------------------------------
# Rebase-regen tests — separate temp repo in /tmp, uses gemini agent
# ---------------------------------------------------------------------------

section "Test 8: ghost rebase --dry-run shows prompts, no changes"

REBASE_TEST_DIR="$(mktemp -d /tmp/ghost-rebase-test-XXXXXX)"
(
  set -euo pipefail
  cd "$REBASE_TEST_DIR"
  git init -q
  ghost init

  # Commit 1 (claude): create a hello-world bash script
  ghost commit -m "Create a bash script called hello.sh that prints 'Hello World' to stdout and exits 0"

  # Commit 2 (claude): colorize the output
  ghost commit -m "Modify hello.sh to print the text in red using ANSI escape codes (\\033[31m...\\033[0m), keeping the same message"

  HEAD_BEFORE="$(git rev-parse HEAD)"

  # dry-run should list prompts and exit without touching anything
  OUT="$(ghost rebase --dry-run HEAD~2 2>&1 || true)"

  assert 'echo "$OUT" | grep -q "Create a bash script"' "dry-run lists first prompt"
  assert 'echo "$OUT" | grep -q "Modify hello.sh"'      "dry-run lists second prompt"
  assert '[ "$(git rev-parse HEAD)" = "$HEAD_BEFORE" ]'  "dry-run leaves HEAD unchanged"
)
rm -rf "$REBASE_TEST_DIR"

section "Test 9: ghost rebase --help prints usage"
OUT="$(ghost rebase --help 2>&1 || true)"
assert 'echo "$OUT" | grep -q "rebase-regen"' "rebase --help contains rebase-regen"
assert 'echo "$OUT" | grep -q "\-\-agent"'    "rebase --help documents --agent flag"
assert 'echo "$OUT" | grep -q "\-\-model"'    "rebase --help documents --model flag"

OUT2="$(ghost rebase help 2>&1 || true)"
assert 'echo "$OUT2" | grep -q "rebase-regen"' "ghost rebase help also works"

section "Test 10: ghost rebase with gemini agent"
# Requires: gemini CLI installed and authenticated
if ! command -v gemini >/dev/null 2>&1; then
  printf "  \033[33m⚠\033[0m  gemini CLI not found — skipping rebase gemini test\n"
else
  REBASE_GEMINI_DIR="$(mktemp -d /tmp/ghost-rebase-gemini-XXXXXX)"
  (
    set -euo pipefail
    cd "$REBASE_GEMINI_DIR"
    git init -q

    # Use a plain initial commit so HEAD~2 lands on a real commit
    touch .gitkeep
    git add .gitkeep
    GHOST_SKIP=1 git commit -m "init"

    ghost init

    # Commit 1 (claude default): create hello.sh
    ghost commit -m "Create a bash script called hello.sh that prints 'Hello World' to stdout and exits 0"
    assert '[ -f hello.sh ]' "hello.sh created by claude"

    # Commit 2 (claude default): make text red
    ghost commit -m "Modify hello.sh to print the text in red using ANSI escape codes (\\033[31m...\\033[0m), keeping the same message"

    COMMIT_COUNT_BEFORE="$(git rev-list --count HEAD)"
    HEAD_BEFORE="$(git rev-parse HEAD)"

    # Confirm non-interactively by piping 'y'
    echo "y" | ghost rebase --agent gemini HEAD~2

    HEAD_AFTER="$(git rev-parse HEAD)"

    # HEAD must have changed (history was rewritten)
    assert '[ "$HEAD_AFTER" != "$HEAD_BEFORE" ]' "rebase changed HEAD"

    # Verify ghost-meta present on both new commits
    assert 'git log -1 HEAD  --format=%B | grep -q "ghost-meta"'  "HEAD commit has ghost-meta"
    assert 'git log -1 HEAD~1 --format=%B | grep -q "ghost-meta"' "HEAD~1 commit has ghost-meta"

    # Verify both commits list gemini as the agent
    assert 'git log -1 HEAD  --format=%B | grep -q "ghost-agent: gemini"' "HEAD commit agent is gemini"
    assert 'git log -1 HEAD~1 --format=%B | grep -q "ghost-agent: gemini"' "HEAD~1 commit agent is gemini"

    # hello.sh must still exist and be executable/runnable
    assert '[ -f hello.sh ]' "hello.sh exists after rebase"

    OUTPUT="$(bash hello.sh 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' || true)"
    assert 'echo "$OUTPUT" | grep -qi "hello"' "hello.sh still outputs Hello World (ignoring ANSI)"
  )
  rm -rf "$REBASE_GEMINI_DIR"
fi

# --- Summary ---
printf "\n\033[1mResults:\033[0m %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1

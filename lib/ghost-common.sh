#!/usr/bin/env bash
# ghost-common.sh — shared constants and utilities

GHOST_META_MARKER="ghost-meta"
GHOST_PROMPT_KEY="ghost-prompt"
GHOST_AGENT_KEY="ghost-agent"
GHOST_MODEL_KEY="ghost-model"
GHOST_SESSION_KEY="ghost-session"
GHOST_FILES_KEY="ghost-files"

GHOST_DEFAULT_AGENT="${GHOST_AGENT:-claude}"
GHOST_DEFAULT_MODEL="${GHOST_MODEL:-claude-sonnet-4-6}"

ghost_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

ghost_ensure_repo() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: not a git repository. Run 'ghost init' first." >&2
    exit 1
  fi
}

ghost_is_skip() {
  [ "${GHOST_SKIP:-0}" = "1" ]
}

ghost_hooks_path() {
  local hooks_path
  hooks_path="$(git config --local core.hooksPath 2>/dev/null)"
  if [ -z "$hooks_path" ]; then
    hooks_path="$(git rev-parse --git-dir)/hooks"
  else
    # Make absolute if relative
    if [[ "$hooks_path" != /* ]]; then
      hooks_path="$(git rev-parse --show-toplevel)/$hooks_path"
    fi
  fi
  echo "$hooks_path"
}

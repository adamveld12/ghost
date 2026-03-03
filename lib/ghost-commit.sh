#!/usr/bin/env bash
# ghost-commit.sh — run agent, detect changes, stage, commit

set -euo pipefail

# shellcheck source=lib/ghost-common.sh
source "${GHOST_ROOT}/lib/ghost-common.sh"
# shellcheck source=lib/ghost-agents.sh
source "${GHOST_ROOT}/lib/ghost-agents.sh"

_snapshot() {
  git status --porcelain=v2 2>/dev/null || true
}

_changed_files() {
  local before="$1"
  local after="$2"

  # Extract file paths from porcelain v2 output
  # Format for changed: "1 <xy> <sub> <mH> <mI> <mW> <hH> <hI> <path>"
  # Format for renamed: "2 <xy> ... <path><sep><origPath>"
  # Format for untracked: "? <path>"

  local -a files=()

  while IFS= read -r line; do
    if [[ "$line" == "1 "* ]] || [[ "$line" == "2 "* ]]; then
      local path
      path="$(echo "$line" | awk '{print $NF}')"
      # For renames, NF gives new\torig — take first part
      path="${path%%$'\t'*}"
      files+=("$path")
    elif [[ "$line" == "? "* ]]; then
      local path="${line:2}"
      files+=("$path")
    fi
  done < <(comm -13 <(echo "$before" | sort) <(echo "$after" | sort))

  # Deduplicate
  printf '%s\n' "${files[@]}" | sort -u
}

cmd_commit() {
  ghost_ensure_repo

  local prompt=""
  local agent="${GHOST_DEFAULT_AGENT}"
  local model=""
  local dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--message)
        shift
        prompt="$1"
        shift
        ;;
      --agent)
        shift
        agent="$1"
        shift
        ;;
      --model)
        shift
        model="$1"
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      *)
        echo "error: unknown option: $1" >&2
        echo "usage: ghost commit -m \"prompt\" [--agent AGENT] [--model MODEL] [--dry-run]" >&2
        exit 1
        ;;
    esac
  done

  if [ -z "$prompt" ]; then
    echo "error: prompt required. Use -m \"your intent here\"" >&2
    exit 1
  fi

  if ! ghost_validate_agent "$agent"; then
    echo "error: unsupported agent: ${agent}" >&2
    echo "  supported: ${GHOST_SUPPORTED_AGENTS[*]}" >&2
    exit 1
  fi

  # Resolve model: flag > env > agent default
  if [ -z "$model" ]; then
    model="$(ghost_default_model "$agent")"
  fi

  echo "Ghost: running ${agent}..."
  echo "  prompt: ${prompt}"
  [ -n "$model" ] && echo "  model:  ${model}"
  [ "$dry_run" = "1" ] && echo "  mode:   dry-run"
  echo ""

  # Snapshot before
  local snapshot_before
  snapshot_before="$(_snapshot)"

  local session_id
  session_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"

  local agent_exit=0
  ghost_run_agent "$agent" "$model" "$prompt" || agent_exit=$?

  if [ "$agent_exit" -ne 0 ]; then
    echo "" >&2
    echo "error: ${agent} exited with code ${agent_exit}" >&2
    exit "$agent_exit"
  fi

  # Snapshot after
  local snapshot_after
  snapshot_after="$(_snapshot)"

  # Find changed files
  local changed_files
  changed_files="$(_changed_files "$snapshot_before" "$snapshot_after")"

  if [ -z "$changed_files" ]; then
    echo ""
    echo "Ghost: no file changes detected. Nothing to commit."
    exit 1
  fi

  echo ""
  echo "Ghost: detected changes:"
  echo "$changed_files" | sed 's/^/  /'

  if [ "$dry_run" = "1" ]; then
    echo ""
    echo "Ghost: dry-run complete. No commit made."
    exit 0
  fi

  # Stage changed files
  while IFS= read -r f; do
    [ -n "$f" ] && git add -- "$f"
  done <<< "$changed_files"

  # Build file list for metadata (comma-separated)
  local files_csv
  files_csv="$(echo "$changed_files" | tr '\n' ',' | sed 's/,$//')"

  # Build enriched commit message
  local commit_msg
  commit_msg="${prompt}

${GHOST_META_MARKER}
${GHOST_PROMPT_KEY}: ${prompt}
${GHOST_AGENT_KEY}: ${agent}
${GHOST_MODEL_KEY}: ${model}
${GHOST_SESSION_KEY}: ${session_id}
${GHOST_FILES_KEY}: ${files_csv}"

  # Commit
  GHOST_ENRICHING=1 git commit -m "$commit_msg"

  echo ""
  echo "Ghost: committed '${prompt}'"
}

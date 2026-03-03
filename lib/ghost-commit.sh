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
  ghost_init_colors

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
        gh_error "error: unknown option: $1"
        gh_error "usage: ghost commit -m \"prompt\" [--agent AGENT] [--model MODEL] [--dry-run]"
        exit 1
        ;;
    esac
  done

  if [ -z "$prompt" ]; then
    gh_error "error: prompt required. Use -m \"your intent here\""
    exit 1
  fi

  if ! ghost_validate_agent "$agent"; then
    gh_error "error: unsupported agent: ${agent}"
    gh_error "  supported: ${GHOST_SUPPORTED_AGENTS[*]}"
    exit 1
  fi

  # Resolve model: flag > env > agent default
  if [ -z "$model" ]; then
    model="$(ghost_default_model "$agent")"
  fi

  # ── Header ────────────────────────────────────────────────────────────────
  printf "\n%b  ▸ ghost%b\n" "${GH_PINK}${GH_BOLD}" "${GH_RESET}"
  gh_kv "agent"  "${agent}"
  [ -n "$model" ] && gh_kv "model" "${model}"
  gh_kv "intent" "${prompt}"
  [ "$dry_run" = "1" ] && gh_kv "mode" "dry-run"
  printf "\n"

  # Snapshot before
  local snapshot_before head_before
  snapshot_before="$(_snapshot)"
  head_before="$(git rev-parse HEAD 2>/dev/null || true)"

  local session_id
  session_id="$(uuidgen | tr '[:upper:]' '[:lower:]')"

  # ── Run agent (spinner in background while it works) ──────────────────────
  ghost_spinner_start "running ${agent}…"
  local agent_exit=0
  ghost_run_agent "$agent" "$model" "$prompt" || agent_exit=$?
  ghost_spinner_stop

  if [ "$agent_exit" -ne 0 ]; then
    printf "\n" >&2
    gh_error "error: ${agent} exited with code ${agent_exit}"
    exit "$agent_exit"
  fi

  # ── Post-process ──────────────────────────────────────────────────────────
  ghost_spinner_start "detecting changes…"

  # Snapshot after
  local snapshot_after head_after
  snapshot_after="$(_snapshot)"
  head_after="$(git rev-parse HEAD 2>/dev/null || true)"

  # Find changed files (working-tree changes the agent left unstaged/uncommitted)
  local changed_files
  changed_files="$(_changed_files "$snapshot_before" "$snapshot_after")"

  ghost_spinner_stop

  # ── Handle agent self-commits ─────────────────────────────────────────────
  # If the agent ran git commit itself, HEAD will have moved. We inject
  # ghost-meta into the most recent commit via --amend so it appears in
  # ghost log. Any remaining working-tree changes are staged and committed
  # separately below.
  if [ -n "$head_before" ] && [ "$head_after" != "$head_before" ]; then
    local agent_commit_body agent_commit_msg files_in_agent_commit files_csv
    agent_commit_body="$(git log -1 --format=%B)"

    # Only amend if ghost-meta not already present
    if ! echo "$agent_commit_body" | grep -q "^${GHOST_META_MARKER}$"; then
      files_in_agent_commit="$(git diff-tree --no-commit-id -r --name-only HEAD | tr '\n' ',' | sed 's/,$//')"
      agent_commit_msg="${agent_commit_body}
${GHOST_META_MARKER}
${GHOST_PROMPT_KEY}: ${prompt}
${GHOST_AGENT_KEY}: ${agent}
${GHOST_MODEL_KEY}: ${model}
${GHOST_SESSION_KEY}: ${session_id}
${GHOST_FILES_KEY}: ${files_in_agent_commit}"
      GHOST_ENRICHING=1 git commit --amend -m "$agent_commit_msg"
      printf "\n"
      gh_success "  ✓ ghost: tagged agent commit with ghost-meta '${prompt}'"
    fi

    # Stage and commit any remaining working-tree changes
    if [ -n "$changed_files" ]; then
      if [ "$dry_run" = "1" ]; then
        printf "\n%bremaining changes:%b\n" "${GH_PURPLE}" "${GH_RESET}"
        while IFS= read -r f; do
          printf "  %b+%b %s\n" "${GH_CYAN}" "${GH_RESET}" "$f"
        done <<< "$changed_files"
        printf "\n"
        gh_label "  ghost: dry-run complete. No commit made."
        exit 0
      fi
      while IFS= read -r f; do
        [ -n "$f" ] && git add -- "$f"
      done <<< "$changed_files"
      files_csv="$(echo "$changed_files" | tr '\n' ',' | sed 's/,$//')"
      local followup_msg
      followup_msg="${prompt} (follow-up)

${GHOST_META_MARKER}
${GHOST_PROMPT_KEY}: ${prompt}
${GHOST_AGENT_KEY}: ${agent}
${GHOST_MODEL_KEY}: ${model}
${GHOST_SESSION_KEY}: ${session_id}
${GHOST_FILES_KEY}: ${files_csv}"
      GHOST_ENRICHING=1 git commit -m "$followup_msg"
      printf "\n"
      gh_success "  ✓ ghost: committed follow-up changes '${prompt}'"
    fi
    printf "\n"
    return 0
  fi

  # ── Normal flow: agent left changes in the working tree ───────────────────
  if [ -z "$changed_files" ]; then
    printf "\n"
    gh_label "  ghost: no file changes detected. Nothing to commit."
    exit 1
  fi

  printf "\n%bchanges:%b\n" "${GH_PURPLE}" "${GH_RESET}"
  while IFS= read -r f; do
    printf "  %b+%b %s\n" "${GH_CYAN}" "${GH_RESET}" "$f"
  done <<< "$changed_files"

  if [ "$dry_run" = "1" ]; then
    printf "\n"
    gh_label "  ghost: dry-run complete. No commit made."
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

  printf "\n"
  gh_success "  ✓ ghost: committed '${prompt}'"
  printf "\n"
}

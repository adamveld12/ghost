#!/usr/bin/env bash
# ghost-log.sh — pretty-print ghost commit history

set -euo pipefail

# shellcheck source=lib/ghost-common.sh
source "${GHOST_ROOT}/lib/ghost-common.sh"

# Colors
_RESET='\033[0m'
_BOLD='\033[1m'
_YELLOW='\033[0;33m'
_CYAN='\033[0;36m'
_GREEN='\033[0;32m'
_DIM='\033[2m'

cmd_log() {
  ghost_ensure_repo

  local count=0

  while IFS= read -r hash; do
    local body
    body="$(git log -1 --format=%B "$hash")"

    # Skip non-ghost commits
    echo "$body" | grep -q "^${GHOST_META_MARKER}$" || continue

    local short_hash="${hash:0:7}"
    local date author prompt agent model session files

    date="$(git log -1 --format='%ad' --date=short "$hash")"
    author="$(git log -1 --format='%an' "$hash")"
    prompt="$(echo "$body" | grep "^${GHOST_PROMPT_KEY}:" | sed "s/^${GHOST_PROMPT_KEY}: //")"
    agent="$(echo "$body" | grep "^${GHOST_AGENT_KEY}:" | sed "s/^${GHOST_AGENT_KEY}: //")"
    model="$(echo "$body" | grep "^${GHOST_MODEL_KEY}:" | sed "s/^${GHOST_MODEL_KEY}: //")"
    session="$(echo "$body" | grep "^${GHOST_SESSION_KEY}:" | sed "s/^${GHOST_SESSION_KEY}: //")"
    files="$(echo "$body" | grep "^${GHOST_FILES_KEY}:" | sed "s/^${GHOST_FILES_KEY}: //")"

    [ "$count" -gt 0 ] && echo ""

    printf "${_BOLD}${_YELLOW}%s${_RESET} ${_DIM}%s (%s)${_RESET}\n" \
      "$short_hash" "$date" "$author"
    printf "  ${_CYAN}intent:${_RESET}  %s\n" "$prompt"
    printf "  ${_DIM}agent:   %s${_RESET}\n" "${agent:-claude}"
    printf "  ${_DIM}model:   %s${_RESET}\n" "${model:-unknown}"
    printf "  ${_DIM}session: %s${_RESET}\n" "${session:-unknown}"
    if [ -n "$files" ]; then
      printf "  ${_GREEN}files:   %s${_RESET}\n" "$files"
    fi

    count=$((count + 1))
  done < <(git log --format="%H" 2>/dev/null || true)

  if [ "$count" -eq 0 ]; then
    echo "No ghost commits found."
  fi
}

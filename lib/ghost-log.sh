#!/usr/bin/env bash
# ghost-log.sh — pretty-print ghost commit history

set -euo pipefail

# shellcheck source=lib/ghost-common.sh
source "${GHOST_ROOT}/lib/ghost-common.sh"

cmd_log() {
  ghost_ensure_repo
  ghost_init_colors

  local count=0
  local max_count=""

  # Parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n)
        shift
        max_count="${1:?"-n requires a number"}"
        shift
        ;;
      -n*)
        max_count="${1#-n}"
        shift
        ;;
      *)
        echo "error: unknown option: $1" >&2
        exit 1
        ;;
    esac
  done

  local git_log_args=("--format=%H")

  while IFS= read -r hash; do
    local body
    body="$(git log -1 --format=%B "$hash")"

    # Skip non-ghost commits
    echo "$body" | grep -q "^${GHOST_META_MARKER}$" || continue

    local short_hash="${hash:0:7}"
    local date author prompt agent model session files

    date="$(git log -1 --format='%ad' --date=short "$hash")"
    author="$(git log -1 --format='%an' "$hash")"
    prompt="$(echo "$body" | grep "^${GHOST_PROMPT_KEY}:" | sed "s/^${GHOST_PROMPT_KEY}: //" || true)"
    agent="$(echo "$body" | grep "^${GHOST_AGENT_KEY}:" | sed "s/^${GHOST_AGENT_KEY}: //" || true)"
    model="$(echo "$body" | grep "^${GHOST_MODEL_KEY}:" | sed "s/^${GHOST_MODEL_KEY}: //" || true)"
    session="$(echo "$body" | grep "^${GHOST_SESSION_KEY}:" | sed "s/^${GHOST_SESSION_KEY}: //" || true)"
    files="$(echo "$body" | grep "^${GHOST_FILES_KEY}:" | sed "s/^${GHOST_FILES_KEY}: //" || true)"

    # Honour -n limit (counts ghost commits, not total commits scanned)
    [[ -n "$max_count" ]] && [[ "$count" -ge "$max_count" ]] && break

    [ "$count" -gt 0 ] && printf "\n"

    # hash + date + author
    printf "%b%s%b %b%s%b %b(%s)%b\n" \
      "${GH_PINK}${GH_BOLD}" "$short_hash" "${GH_RESET}" \
      "${GH_BLUE}"           "$date"       "${GH_RESET}" \
      "${GH_DIM}"            "$author"     "${GH_RESET}"

    # intent
    printf "  %bintent%b   %s\n" "${GH_PURPLE}" "${GH_RESET}" "$prompt"

    # agent / model / session
    printf "  %bagent%b    %b%s%b\n"   "${GH_DIM}" "${GH_RESET}" "${GH_CYAN}" "${agent:-claude}"   "${GH_RESET}"
    printf "  %bmodel%b    %b%s%b\n"   "${GH_DIM}" "${GH_RESET}" "${GH_CYAN}" "${model:-unknown}"  "${GH_RESET}"
    printf "  %bsession%b  %b%s%b\n"   "${GH_DIM}" "${GH_RESET}" "${GH_DIM}"  "${session:-unknown}" "${GH_RESET}"

    if [ -n "$files" ]; then
      printf "  %bfiles%b    %b%s%b\n" "${GH_DIM}" "${GH_RESET}" "${GH_GREEN}" "$files" "${GH_RESET}"
    fi

    count=$((count + 1))
  done < <(git log "${git_log_args[@]}" 2>/dev/null || true)

  if [ "$count" -eq 0 ]; then
    gh_dim "No ghost commits found."
  fi
}

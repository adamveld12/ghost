#!/usr/bin/env bash
# ghost-agents.sh — agent registry and dispatch

# Supported agents
GHOST_SUPPORTED_AGENTS=("claude" "gemini" "codex" "opencode")

# Default model per agent (overridden by GHOST_MODEL env or --model flag)
ghost_default_model() {
  local agent="$1"
  case "$agent" in
    claude)   echo "${GHOST_MODEL:-claude-sonnet-4-6}" ;;
    gemini)   echo "${GHOST_MODEL:-gemini-3-flash-preview}" ;;
    codex)    echo "${GHOST_MODEL:-o4-mini}" ;;
    opencode) echo "${GHOST_MODEL:-}" ;;  # opencode uses its own config
    *)        echo "" ;;
  esac
}

ghost_validate_agent() {
  local agent="$1"
  case "$agent" in
    claude|gemini|codex|opencode) return 0 ;;
    *) return 1 ;;
  esac
}

# Dispatch: ghost_run_agent <agent> <model> <prompt>
ghost_run_agent() {
  local agent="$1"
  local model="$2"
  local prompt="$3"

  case "$agent" in
    claude)   _ghost_run_claude "$model" "$prompt" ;;
    gemini)   _ghost_run_gemini "$model" "$prompt" ;;
    codex)    _ghost_run_codex  "$model" "$prompt" ;;
    opencode) _ghost_run_opencode "$model" "$prompt" ;;
    *)
      echo "error: unsupported agent: ${agent}" >&2
      echo "  supported: ${GHOST_SUPPORTED_AGENTS[*]}" >&2
      exit 1
      ;;
  esac
}

# claude — Claude Code CLI
# https://docs.anthropic.com/en/docs/claude-code
# Flags: --model MODEL, -p PROMPT, --dangerously-skip-permissions
_ghost_run_claude() {
  local model="$1"
  local prompt="$2"
  env -u CLAUDECODE claude \
    --model "$model" \
    -p "$prompt" \
    --dangerously-skip-permissions
}

# gemini — Google Gemini CLI
# https://github.com/google-gemini/gemini-cli
# Flags: --model MODEL, -p PROMPT, -y (auto-approve)
_ghost_run_gemini() {
  local model="$1"
  local prompt="$2"
  local args=(-y -p "$prompt")
  [ -n "$model" ] && args=(--model "$model" "${args[@]}")
  gemini "${args[@]}"
}

# codex — OpenAI Codex CLI
# https://github.com/openai/codex
# Flags: --model MODEL, --approval-mode full-auto, positional prompt
_ghost_run_codex() {
  local model="$1"
  local prompt="$2"
  local args=(--approval-mode full-auto)
  [ -n "$model" ] && args+=(--model "$model")
  codex "${args[@]}" "$prompt"
}

# opencode — OpenCode CLI (sst.dev)
# https://opencode.ai
# Flags: --model MODEL (optional, uses opencode config by default), -p PROMPT
_ghost_run_opencode() {
  local model="$1"
  local prompt="$2"
  local args=()
  [ -n "$model" ] && args+=(--model "$model")
  opencode run "${args[@]}" -p "$prompt"
}

# Ghost

**Commit intentions, not code.**

Ghost is a CLI that flips the git workflow: instead of committing code, you commit *prompts*. An AI coding agent generates the artifacts; the commit captures both the intent and the output. Your git history becomes a chain of prompts + their results.

Supports **claude**, **gemini**, **codex**, and **opencode** — swap agents per-commit or set a default.

<img width="935" height="657" alt="image" src="https://github.com/user-attachments/assets/cc33324e-7a33-4572-b9ab-be1b3d773c0e" />


## The Idea

Code is ephemeral. Intent is permanent.

Every `ghost commit` answers: *what did I want to happen here?* Not *what bytes changed*. Each commit is reproducible from its prompt — if the code breaks, you have the exact instruction that generated it. The git log reads like a design document, not a diff summary.

```
git log --oneline

a3f2c1b  add JWT authentication middleware
7e91d4a  create user registration endpoint with email validation
2bc0f88  scaffold Express app with TypeScript and Prettier
```

Each of those is a ghost commit. Behind each message is an AI that turned words into working code, and a session ID that ties the output back to the generation.

## Why Intent-Based Commits?

**Code is the artifact, intent is the source of truth.**

When you read a traditional git log, you see *what* changed. With ghost, you see *prompts* — the human decision that triggered the change. A year from now when LLMs are more amazing you can replay the git log and generate a better version.

**Every commit is reproducible.** The prompt is preserved with some extra attributes about which model and agent was used. You can re-run any commit against a fresh checkout to see what Claude generates from the same instruction.

**The log becomes a design document.** Read `ghost log` top-to-bottom and you'll see the intent behind every architectural decision, not just the code that resulted from it.

**Diffs show what the AI decided; messages show what you asked for.** The two together give you full context: the goal and the implementation, inseparably linked.

## How It Works

```
you: ghost commit -m "add user auth with JWT"
     ↓
agent generates code → files written to working tree
     ↓
ghost detects changes → stages new/modified files
     ↓
git commit with enriched message (prompt + agent + model + session + file list)
```

## Quick Start

```bash
git clone <this-repo>
export PATH="/path/to/ghost/bin:$PATH"

cd your-project
ghost init
ghost commit -m "create a REST API endpoint for user registration"
```

## Commands

| Command | Description |
|---|---|
| `ghost init` | Init git repo (if needed), install hook, create `.ghost/` dir |
| `ghost commit -m "prompt"` | Generate code from prompt, stage changed files, commit |
| `ghost commit --agent gemini -m "prompt"` | Use a specific agent (claude, gemini, codex, opencode) |
| `ghost commit --dry-run -m "prompt"` | Generate code, show what changed, don't commit |
| `ghost log` | Pretty-print ghost commit history (prompt, agent, model, session, files) |
| `ghost rebase --agent AGENT <base>` | Replay ghost commit prompts through a different agent |
| `GHOST_SKIP=1 ghost commit -m "..."` | Pass-through to plain `git commit` |

### Examples

```bash
# New feature (default agent: claude)
ghost commit -m "add a login page with email/password form and client-side validation"

# Use Gemini
ghost commit --agent gemini -m "refactor the database layer to use connection pooling"

# Use Codex
ghost commit --agent codex -m "fix the race condition in the payment processing queue"

# Use OpenCode
ghost commit --agent opencode -m "add OpenAPI documentation for all endpoints"

# With a specific model
ghost commit --agent claude --model claude-opus-4-6 -m "architect a microservices migration plan as code comments"

# Preview without committing
ghost commit --dry-run -m "add OpenAPI documentation for all endpoints"

# Set default agent via env
GHOST_AGENT=gemini ghost commit -m "scaffold a new service"

# Manual commit (bypass ghost entirely)
GHOST_SKIP=1 ghost commit -m "bump version to 1.2.0"
```

## Rebase-Regen

`ghost rebase` is the killer feature: take any range of ghost commits, swap out the AI, and rebuild your codebase from scratch using the same prompts.

```
ghost rebase [--agent AGENT] [--model MODEL] <base>
```

It works like `git rebase -i` conceptually, but instead of squashing or reordering commits it *replays every prompt* through a different agent:

```
before:
  HEAD    [claude] make the output red with ANSI codes
  HEAD~1  [claude] create hello.sh that prints Hello World
  HEAD~2  (base)

after: ghost rebase --agent gemini HEAD~2
  HEAD    [gemini] make the output red with ANSI codes
  HEAD~1  [gemini] create hello.sh that prints Hello World
  HEAD~2  (base, unchanged)
```

### Rebase Examples

```bash
# Re-run the last 3 ghost commits with Gemini
ghost rebase --agent gemini HEAD~3

# Re-run with a specific model
ghost rebase --agent gemini --model gemini-2.5-pro HEAD~5

# Re-run from a named commit
ghost rebase --agent codex abc1234

# Preview what would be replayed (no changes made)
ghost rebase --dry-run HEAD~3

# Re-run all ghost commits since branching from main
ghost rebase --agent claude --model claude-opus-4-6 main
```

### How Rebase-Regen Works

```
1. Scan <base>..HEAD for ghost commits → extract prompts in order
2. Check working tree is clean
3. git reset --hard <base>
4. For each prompt (oldest → newest):
     ghost commit --agent AGENT --model MODEL -m "<original prompt>"
5. New commits are created with updated ghost-agent / ghost-model metadata
```

Plain git commits in the range (those without `ghost-meta`) are silently skipped — only ghost commits are replayed.

> **Warning**: This rewrites history. Coordinate with your team before rebasing commits that have been pushed to a shared remote.

## Commit Message Format

Every ghost commit has an enriched message body:

```
add a login page

ghost-meta
ghost-prompt: add a login page
ghost-agent: claude
ghost-model: claude-sonnet-4-6
ghost-session: 7f3a2b1c-4d5e-6f7a-8b9c-0d1e2f3a4b5c
ghost-files: src/pages/login.tsx,src/hooks/useAuth.ts,src/api/auth.ts
```

| Field | Description |
|---|---|
| `ghost-meta` | Marker that identifies this as a ghost commit |
| `ghost-prompt` | The exact prompt passed to the agent |
| `ghost-agent` | The agent that generated the code (claude, gemini, codex, opencode) |
| `ghost-model` | The model used by the agent |
| `ghost-session` | UUID for this generation session |
| `ghost-files` | Comma-separated list of files created or modified |

## Configuration

| Variable | Description |
|---|---|
| `GHOST_SKIP=1` | Pass-through to plain `git commit`, no agent invocation |
| `GHOST_AGENT=<agent>` | Default agent (overridden by `--agent`) |
| `GHOST_MODEL=<model>` | Default model (overridden by `--model`) |

| Flag | Description |
|---|---|
| `--agent AGENT` | Agent for this commit (claude, gemini, codex, opencode) |
| `--model MODEL` | Model override for the agent |
| `--dry-run` | Generate code but do not stage or commit |

## Requirements

- `git` 2.x+
- `bash` 4+
- `uuidgen` (available on macOS and most Linux distros)
- Agent CLI installed and configured for whichever agent(s) you use:
  - **claude**: [`claude`](https://docs.anthropic.com/en/docs/claude-code) CLI
  - **gemini**: [`gemini`](https://github.com/google-gemini/gemini-cli) CLI
  - **codex**: [`codex`](https://github.com/openai/codex) CLI
  - **opencode**: [`opencode`](https://opencode.ai) CLI


## Running Tests

```bash
bash test/integration.sh
```

The integration test spins up a temp git repo, runs a full ghost workflow including generating and compiling a C program, and verifies all metadata fields.

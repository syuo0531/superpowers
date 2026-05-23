#!/usr/bin/env bash
#
# collect-data.sh — Gather a snapshot of the current session for health inspection.
#
# WHAT IT DOES:
#   Collects information about your environment, Git state, running processes,
#   and configuration files. The output is used by the inspector agents to
#   check whether your session is healthy.
#
# HOW TO USE:
#   Print to terminal:
#     ./scripts/collect-data.sh
#
#   Save to a file (recommended — easier to paste into inspector agents):
#     ./scripts/collect-data.sh --output snapshot.txt
#
# PRIVACY:
#   Values that look like secrets (tokens, passwords, API keys) are replaced
#   with [REDACTED] so you can safely share the output.

set -euo pipefail

# --- Parse arguments ---
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--output <file>]" >&2
      exit 1
      ;;
  esac
done

# --- Main collection function ---
collect() {
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  echo "# Session Health Snapshot"
  echo "# Generated: $timestamp"
  echo "# This file was created by collect-data.sh — safe to share (secrets redacted)"
  echo ""

  # ── Basic environment ──────────────────────────────────────────────────────
  # Tells inspectors what OS and shell you're using
  echo "## Environment"
  echo "OS: $(uname -s) $(uname -r)"
  echo "Shell: ${SHELL:-unknown}"
  echo "User: $(id -un)"
  echo "Hostname: $(hostname 2>/dev/null || echo unknown)"
  echo "Working directory: $(pwd)"
  echo ""

  # ── Environment variables ──────────────────────────────────────────────────
  # Lists all variables set in the shell.
  # Any variable whose name contains TOKEN, SECRET, PASSWORD, KEY, etc.
  # has its value replaced with [REDACTED] for safety.
  echo "## Environment Variables (secrets redacted)"
  env | sort | while IFS='=' read -r key value; do
    case "$key" in
      *TOKEN*|*SECRET*|*PASSWORD*|*KEY*|*CREDENTIAL*|*AUTH*|*API_KEY*)
        echo "$key=[REDACTED]"
        ;;
      *)
        echo "$key=$value"
        ;;
    esac
  done
  echo ""

  # ── Git state ──────────────────────────────────────────────────────────────
  # Shows which branch you're on, the last commit, and any uncommitted changes.
  # Helps inspectors check whether your repo is in a consistent state.
  echo "## Git State"
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    echo "Last commit: $(git log -1 --format='%h %s' 2>/dev/null || echo none)"
    echo "Uncommitted changes:"
    git status --short 2>/dev/null || echo "(none or unavailable)"
    echo "Remote repositories:"
    git remote -v 2>/dev/null | head -10 || echo "(none configured)"
  else
    echo "(not inside a git repository)"
  fi
  echo ""

  # ── Disk usage ─────────────────────────────────────────────────────────────
  # Shows how much space each top-level directory is using.
  # Helps spot unexpectedly large files or directories.
  echo "## Filesystem (disk usage by top-level item)"
  du -sh ./* 2>/dev/null | sort -h | tail -20 || echo "(unavailable)"
  echo ""

  # ── Running processes ──────────────────────────────────────────────────────
  # Shows what processes are currently running.
  # Helps spot leftover processes from previous tasks.
  echo "## Running Processes (sample)"
  echo "Script PID: $$  |  Parent PID: $PPID"
  if command -v ps &>/dev/null; then
    ps aux 2>/dev/null | head -20 || echo "(unavailable)"
  else
    echo "(ps command not available)"
  fi
  echo ""

  # ── Configuration files ────────────────────────────────────────────────────
  # Checks whether common configuration files exist.
  # Missing or unexpected config files can cause subtle problems.
  echo "## Configuration Files"
  echo "Checking for common files:"
  local config_files=(
    ".claude/settings.json"      # Claude Code project settings
    ".claude/settings.local.json" # Local overrides (not committed)
    "CLAUDE.md"                  # Instructions for Claude in this project
    ".env"                       # Environment variables (often contains secrets)
    ".env.local"                 # Local environment overrides
    "package.json"               # Node.js project config
    "pyproject.toml"             # Python project config
    "Cargo.toml"                 # Rust project config
  )
  for f in "${config_files[@]}"; do
    if [[ -f "$f" ]]; then
      echo "  FOUND:  $f  ($(wc -l < "$f") lines)"
    else
      echo "  absent: $f"
    fi
  done
  echo ""

  # ── Claude settings ────────────────────────────────────────────────────────
  # Shows the content of Claude's settings file.
  # Values that look like secrets are redacted automatically.
  echo "## Claude Settings (.claude/settings.json)"
  local settings=".claude/settings.json"
  if [[ -f "$settings" ]]; then
    sed 's/"[^"]*[Tt]oken[^"]*"\s*:\s*"[^"]*"/"token": "[REDACTED]"/g;
         s/"[^"]*[Kk]ey[^"]*"\s*:\s*"[^"]*"/"key": "[REDACTED]"/g' "$settings" 2>/dev/null || cat "$settings"
  else
    echo "(file not found — Claude Code may not be configured for this project)"
  fi
  echo ""
}

# --- Run and output ---
if [[ -n "$OUTPUT" ]]; then
  collect > "$OUTPUT"
  echo "Snapshot saved to: $OUTPUT" >&2
  echo "Next step: paste the contents into the inspector agent prompts." >&2
else
  collect
fi

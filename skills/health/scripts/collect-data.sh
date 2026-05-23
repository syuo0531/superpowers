#!/usr/bin/env bash
# Collect session and environment state for health inspection.
# Outputs a structured snapshot to stdout; redirect to a file to pass to inspector agents.
# Usage: ./collect-data.sh [--output <file>]

set -euo pipefail

OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

collect() {
  local timestamp
  timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  echo "# Session Health Snapshot"
  echo "# Generated: $timestamp"
  echo ""

  echo "## Environment"
  echo "OS: $(uname -s) $(uname -r)"
  echo "Shell: ${SHELL:-unknown}"
  echo "User: $(id -un)"
  echo "Hostname: $(hostname 2>/dev/null || echo unknown)"
  echo "Working directory: $(pwd)"
  echo ""

  echo "## Environment Variables (sanitized)"
  # Print names of all set env vars; redact values that look like secrets
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

  echo "## Git State"
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    echo "Last commit: $(git log -1 --format='%h %s' 2>/dev/null || echo none)"
    echo "Status:"
    git status --short 2>/dev/null || echo "(unavailable)"
    echo "Remotes:"
    git remote -v 2>/dev/null | head -10 || echo "(none)"
  else
    echo "(not a git repository)"
  fi
  echo ""

  echo "## Filesystem"
  echo "Disk usage (top-level):"
  du -sh ./* 2>/dev/null | sort -h | tail -20 || echo "(unavailable)"
  echo ""

  echo "## Process Context"
  echo "PID: $$"
  echo "Parent PID: $PPID"
  if command -v ps &>/dev/null; then
    echo "Running processes (sample):"
    ps aux 2>/dev/null | head -20 || echo "(unavailable)"
  fi
  echo ""

  echo "## Configuration Files (presence check)"
  local config_files=(
    ".claude/settings.json"
    ".claude/settings.local.json"
    "CLAUDE.md"
    ".env"
    ".env.local"
    "package.json"
    "pyproject.toml"
    "Cargo.toml"
  )
  for f in "${config_files[@]}"; do
    if [[ -f "$f" ]]; then
      echo "FOUND: $f ($(wc -l < "$f") lines)"
    else
      echo "absent: $f"
    fi
  done
  echo ""

  echo "## Claude Settings (sanitized)"
  local settings=".claude/settings.json"
  if [[ -f "$settings" ]]; then
    # Print settings but redact any values that look like secrets
    sed 's/"[^"]*[Tt]oken[^"]*"\s*:\s*"[^"]*"/"token": "[REDACTED]"/g;
         s/"[^"]*[Kk]ey[^"]*"\s*:\s*"[^"]*"/"key": "[REDACTED]"/g' "$settings" 2>/dev/null || cat "$settings"
  else
    echo "(no settings.json found)"
  fi
  echo ""
}

if [[ -n "$OUTPUT" ]]; then
  collect > "$OUTPUT"
  echo "Snapshot written to: $OUTPUT" >&2
else
  collect
fi

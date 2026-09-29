#!/bin/bash
# PreToolUse hook (Bash): block git commit/push when called from the coder or reviewer subagents.
input=$(cat)
agent_type=$(jq -r '.agent_type // empty' <<<"$input")
command=$(jq -r '.tool_input.command // empty' <<<"$input")

case "$agent_type" in
  coder|reviewer|*:coder|*:reviewer) ;;
  *) exit 0 ;;
esac

# Match "git ... commit|push" within one shell segment (split on ; & |)
if grep -Eq '(^|[;&|[:space:](])git([[:space:]]+[^;&|]*)?[[:space:]]+(commit|push)([[:space:]]|$|[;&|)])' <<<"$command"; then
  echo "Blocked: the '$agent_type' subagent is not allowed to run git commit/push. Leave committing to the user." >&2
  exit 2
fi
exit 0

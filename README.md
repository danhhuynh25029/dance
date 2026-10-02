# dance

A Claude Code plugin that splits work between two subagents, one writing code and one reviewing it independently, with an orchestrator agent that runs the loop between them. It also includes a production-safety checklist for backend code and a hook that stops both subagents from committing or pushing.

## What's included

| Component | Type | Purpose |
|---|---|---|
| `coder` | Subagent | Implements features, fixes and refactors. Reads surrounding code first, makes focused changes, runs build/tests, and reports what it changed. Preloads the `production-safety` skill. |
| `reviewer` | Subagent | Read-only code review of a diff, branch or files. Runs on Sonnet so it doesn't share the coder's blind spots, and treats any claims about the code as unverified. Reports findings by severity with `file:line` and a suggested fix. |
| `orchestrator` | Main-session agent | Controls `coder` and `reviewer`: delegates every code change through the `orchestrate` loop and never edits files itself. Start it with `claude --agent dance:orchestrator`. |
| `orchestrate` | Skill | The loop the orchestrator follows, also usable from a normal session: sends the task to `coder`, then automatically has a fresh `reviewer` review the diff, sends Critical/Major findings back to the coder, and repeats (max 3 review rounds) before reporting to you. |
| `production-safety` | Skill | Checklist for backend changes: no full table scans, idempotent payment/money flows, no memory/resource leaks, no race conditions. |
| `block-subagent-git` | Hook (`PreToolUse` on Bash) | Blocks `git commit` and `git push` when run by `coder` or `reviewer`. Your main session can still commit. |

## Install

```bash
claude plugin marketplace add danhhuynh25029/dance
claude plugin install dance@dance
```

Start a new Claude Code session afterwards so the agents, skill and hook load.

Requirements: `jq` on your `PATH` (used by the hook script) and a Unix-like shell (macOS, Linux, or WSL).

## Usage

### Orchestrator as the main agent

```bash
claude --agent dance:orchestrator
```

The whole session then runs as the orchestrator. Ask for changes as usual; it sends each one to the coder, has the reviewer check it, loops fixes, and reports back. To make it the default for a project, add `"agent": "dance:orchestrator"` to that project's `.claude/settings.json`.

The orchestrator has to be the main agent, not a subagent, because subagents can't launch other subagents.

### Orchestrate from a normal session

```
/dance:orchestrate add an endpoint that lists classes by date (paginated, max 100 per page)
```

Claude also loads this skill on its own when it delegates work to the coder agent, so the reviewer runs after every coder task.

### Calling the agents directly

Name the agent in your request:

```
Use the coder agent to add an endpoint that lists classes by date.
```

```
Use the reviewer agent to review the uncommitted changes.
```

Or chain them:

```
Use the coder agent to implement X (requirements: ...).
Then use the reviewer agent on the git diff. Give it only the original requirements, not the coder's report.
If it reports Critical or Major issues, have the coder fix them and review again.
```

Tips:

- **Don't commit between coding and review.** By default the reviewer reads the uncommitted diff (`git diff`, `git diff --staged`). If you have committed, tell it which branch or commit range to review.
- **Keep the reviewer independent.** Each subagent starts with a fresh context and sees only the prompt it is given. Pass it the requirements and the scope, not the coder's summary.
- **The reviewer never edits files.** Send its findings back to the coder to fix.

## The git guard

The hook reads the `agent_type` Claude Code attaches to tool calls made inside a subagent. If the agent is `coder` or `reviewer` (with or without a plugin prefix such as `dance:coder`) and the command contains `git commit` or `git push`, the call is blocked and the agent is told to leave committing to you.

It matches the command text, so it will not catch a commit hidden inside another script (for example `./release.sh` that runs `git commit` internally).

## Updating

After pulling changes or editing a local checkout:

```bash
claude plugin marketplace update dance
claude plugin update dance@dance
```

Then start a new session.

## Layout

```
.claude-plugin/
  plugin.json          # plugin manifest
  marketplace.json     # single-plugin marketplace pointing at this repo
agents/
  orchestrator.md      # main-session agent
  coder.md
  reviewer.md
skills/
  orchestrate/SKILL.md
  production-safety/SKILL.md
hooks/
  hooks.json           # registers the PreToolUse hook
  block-subagent-git.sh
```

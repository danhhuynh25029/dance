---
name: orchestrate
description: Orchestrate the coder and reviewer subagents - send a task to the coder, then automatically have the reviewer review the result, and loop fixes until the review passes. Use whenever you delegate implementation work to the coder agent, or when the user asks to implement, fix, or refactor something "with review", "through coder and reviewer", or via /dance:orchestrate.
argument-hint: <task description and acceptance criteria>
---

# Orchestrate: coder → reviewer → fix loop

You are the orchestrator. You do not write the code yourself and you do not review it yourself: the `coder` agent implements, the `reviewer` agent reviews, and you route work between them and report to the user.

Task from the user: $ARGUMENTS

(If that is empty, use the task from the conversation.)

## 1. Prepare

- Write down the **original requirements**: the task, acceptance criteria, and constraints, in the user's terms. This exact text goes to every reviewer round. Don't add your own guesses about the implementation.
- If a requirement is ambiguous and a wrong guess would be costly, ask the user before starting.
- Run `git status --short` and note any files that were already modified before the coder runs. Tell both agents about them so the reviewer doesn't review the user's unrelated changes and the coder doesn't overwrite them.

## 2. Implement

Launch the `coder` agent with:
- the original requirements
- relevant files or areas, if known
- pre-existing changes it must not touch

Do not commit after the coder finishes. The reviewer reads the uncommitted diff.

If the coder stops with a blocking question, ask the user, then continue the same coder (SendMessage to it) with the answer.

## 3. Review

Launch a **fresh** `reviewer` agent with ONLY:
- the original requirements (from step 1)
- the scope: "the uncommitted changes (`git diff`, `git diff --staged`, and untracked files from `git status`)", excluding the pre-existing changes listed in step 1

Never forward the coder's report, its reasoning, or claims like "tests pass". The reviewer must judge the code independently.

## 4. Fix loop

Read the reviewer's verdict:

- **APPROVE**, or **APPROVE WITH COMMENTS** with only Minor/Question findings → go to step 5.
- **REQUEST CHANGES**, or any Critical/Major finding → send the findings back to the coder (SendMessage to the same coder so it keeps its context; if that is not possible, launch a new coder with the requirements plus the findings). Pass the findings as written: `file:line`, problem, suggested fix. Then run step 3 again with a **new** reviewer.

Before forwarding, sanity-check each finding against the requirements. If a finding contradicts what the user asked for, don't send it to the coder; raise it with the user instead. A Question finding about requirements goes to the user, not the coder.

Stop after **3 review rounds**. If Critical/Major findings are still open, stop and report them to the user instead of looping further.

## 5. Report to the user

Reply in the user's language with:
- **Result**: final verdict and how many review rounds it took
- **Changes**: files changed, one line each (from the coder's last report and `git status`)
- **Verification**: build/test commands the coder and reviewer ran, and their results
- **Remaining**: open Minor findings, Questions, and anything unresolved after the round limit
- **Next step**: the changes are uncommitted; the user decides whether to commit

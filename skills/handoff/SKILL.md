---
name: handoff
description: Compact the current conversation into a handoff document for another agent to pick up. Use when the user wants to hand off the current session to a fresh agent, save context before compact, or asks for '交接'/'移交'/'handoff'/'下一个 agent 接手'. Complements save-session (which writes to docs/history/), while handoff writes to OS tmp dir for cross-session pickup.
argument-hint: "What will the next session be used for?"
---

<!-- Adapted from mattpocock/skills (skills/productivity/handoff) under MIT-compatible terms. -->

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save to the temporary directory of the user's OS - not the current workspace.

Include a "suggested skills" section in the document, which suggests skills that the agent should invoke.

Do not duplicate content already captured in other artifacts (PRDs, plans, ADRs, issues, commits, diffs). Reference them by path or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the user passed arguments, treat them as a description of what the next session will focus on and tailor the doc accordingly.

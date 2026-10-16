---
name: guided-k8s-lab-task
description: Guide hands-on Ansible and Kubernetes lab tasks with scoped prompts, learner challenges, review, and evidence-based validation. Use when teaching, implementing, reviewing, or debugging work in this repository.
---

# Guided K8s Lab Task

Turn the request into this compact task brief before doing material work:

```text
Goal:
Scope:
Constraints:
Definition of done:
Learning mode:
```

Infer fields already established by the request and repository context. State material assumptions, but do not make the learner rewrite information Codex already has.

Choose the learning mode from the request:

- **Teach:** Explain one concept at a time, make no edits, and give one small challenge before advancing.
- **Review:** Inspect without editing. Separate confirmed findings from suggestions, and offer hints before complete solutions.
- **Implement:** Explain the approach, make the smallest in-scope change, run relevant validation, and debrief the result.
- **Debug:** Separate observations, hypotheses, verification commands, and possible fixes. Do not implement a fix unless requested.

Default to **Teach** when the learner is building a concept or completing a challenge. If the learner explicitly asks for completed code, provide or implement it without withholding the answer.

For challenge work, scaffold only enough structure to make the next step approachable. Review the learner's attempt, explain errors, and let them retry before revealing the completed section unless they request it.

Use validation proportional to the change. Prefer the narrowest relevant check first, then the repository-required checks. Never claim a live cluster result without redacted evidence from the cluster.

Finish with what changed or was learned, the validation evidence, and the next single useful step.

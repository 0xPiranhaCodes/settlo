# 2026-11-09 Merge rules

Calls already made by the manager that matter to the owner. Recorded here so agents follow them; they are process, not architecture, so they are not ADRs.

## 1. Merge rules are enforced by the manager
The repository is private on the GitHub free plan, so branch protection and required reviews are not available. The manager enforces the rules by hand:
- Nobody merges their own PR.
- A PR merges only after a review from a different role that starts with `APPROVE`, and after its checks pass (once CI exists, #3).
- Only the manager merges, into `main`.

## 2. Reviews are comment reviews
All agents use one GitHub account, and GitHub does not let an account approve or request changes on its own PR. Reviews are posted as **comment** reviews whose first line is `APPROVE` or `REQUEST CHANGES`, followed by specific comments. That first line is the verdict the manager reads.

## 3. PR #16: local-dev Supabase config isolated (option C)
The dev-only Supabase settings in PR #16 (phone test numbers with a fixed OTP and the placeholder SMS provider that keeps phone login on) are kept out of the base config. They live in a local-dev overlay applied through a wrapper script, so the base `supabase/config.toml` carries no dev-only auth settings and production config never picks them up by accident.

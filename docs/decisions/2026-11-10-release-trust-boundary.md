# Release trust boundary: main only, no required reviewer

**Date:** 10 Nov 2026 · **Decided by:** Owner (manager ruling on PR #122)

The **Release** and **Supabase hosted** workflows hold the credentials that sign and upload the app and change the hosted project. The repository is public, so the boundary has to be enforced, not agreed.

**No required reviewer on the `production` environment.** The owner is the only collaborator, and every run comes from the owner's account. A reviewer gate, with or without prevent-self-review, would only add a click to the owner's own runs. Revisit this when a second person can push.

The guards that stand in for it:

- **`production` environment.** Its deployment policy admits only `main` and tags matching `v*`. Every job that reads a secret runs in it. The four App Store Connect secrets live there and nowhere else.
- **`SUPABASE_ACCESS_TOKEN` stays a repository secret.** The environment policy still gates the jobs that use it, and the workflow hands it only to the steps that call Supabase; checkout and tool setup run without it.
- **Release tags come from `main`.** A guard job fails the run unless the tagged commit is an ancestor of `origin/main`, before any build code runs or any secret is read. A tag ruleset lets only admins create or move `v*` tags.
- **Hosted changes come from `main`.** Both **Supabase hosted** jobs refuse any ref but `refs/heads/main`: the dry run, the apply, and the test OTP numbers.
- **`main` is protected.** A ruleset requires a pull request and the required checks ([merge rule](../release.md#merge-rule)).
- **No manual trigger on Release.** It runs on `v*` tags only.
- **Nothing sensitive in the public logs.** The test OTP step discards the API response and prints only the HTTP status and a fixed message.

A consequence: a release cannot be proven from a pull-request branch. The first TestFlight upload is #110's acceptance check, run from a `v0.1.0-rc` tag on `main` after merge.

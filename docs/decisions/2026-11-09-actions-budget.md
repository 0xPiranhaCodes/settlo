# GitHub Actions budget

**Date:** 9 Nov 2026 · **Decided by:** Owner

Actions stopped on the free plan ("an Actions budget is preventing further use"). The owner briefly chose to skip CI, then moved the account to GitHub Pro, and Actions runs again. CI stays on GitHub; the short-lived local-CI decision is withdrawn. To save macOS minutes, the iOS debug build runs only on main and on PRs that touch iOS-relevant paths (#39).

The iOS path decision runs on Ubuntu; the macOS job is scheduled only when that decision reports an iOS-relevant change. A skipped macOS job remains a reported, passing check without consuming a macOS runner.

Golden regeneration commits use the repository `GITHUB_TOKEN`, so their pushes do not start the normal push or pull-request CI run. After the bot commit lands, manually re-run **CI** with **Regenerate app and core goldens** disabled on the branch; that hosted run is required merge evidence. A future replacement token may trigger CI only if it is deliberately scoped and approved for that purpose.

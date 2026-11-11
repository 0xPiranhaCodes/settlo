# Reminders (#107)

The captures show the actual Flutter components with bundled Figtree, at 360 logical
pixels wide: [enabled](remind-enabled.png), [sent/cooldown](remind-sent.png),
[retryable error](remind-error.png), [Profile on](profile-reminders-on.png) and
[Profile off](profile-reminders-off.png). They contain no account/contact data.

Reproduce them from `app`:

```sh
flutter test test/reminders_test.dart --dart-define=REMINDER_EVIDENCE=true
```

The test uses a held response to prove a double tap sends once, restores a saved cooldown,
retries a failed send, and verifies that a failed preference write preserves the saved value.

Database checks use this worktree's isolated Supabase stack:

```sh
scripts/supabase-local.sh start
scripts/supabase-local.sh db reset
scripts/supabase-local.sh test db
scripts/supabase-local.sh stop --no-backup
```

Notification scheduling tests cover India timezone/year rollover, day-after at 09:00,
prepayment and final partial instalments, disabled/closed/lender suppression, remote flag
off, and serialized native account cleanup during an in-flight write.

```sh
cd packages/platform
flutter test
```

Delivery limits: iOS local notifications use the last synced loan state. Payments or
preferences changed on another device take effect on this device's next successful sync.
Manual reminders reach Activity on sync; local notification follows that fetch, not a
background push. The remote flag and transport boundary are present, but no APNs/FCM
sender or credentials are installed. Android local delivery is intentionally a no-op.
Space Remind remains unchanged because a net space balance has no loan cooldown key.

The in-screen goldens are generated with the repository's pinned Linux Flutter image,
not the macOS renderer. The visible Loan detail and Profile images were inspected after
regeneration. The scheduling API uses Apple's
[calendar notification triggers](https://developer.apple.com/documentation/usernotifications/uncalendarnotificationtrigger)
with explicit Asia/Kolkata date components.

## Validation at handoff

- Pinned Linux `flutter analyze`: passed.
- Pinned Linux `cd app && flutter test --coverage`: 657 passed, including goldens.
- Own-stack `scripts/supabase-local.sh test db`: 27 files, 1,164 assertions passed; stack stopped with `stop --no-backup`.
- `deno test --allow-env supabase/functions`: 8 passed.
- Host `cd packages/features/profile && flutter test --coverage`: 32 passed.
- Host `cd packages/platform && flutter test --coverage`: 30 passed.
- Host `cd packages/core && flutter test test/export/large_export_test.dart`: passed.
- `cd app && flutter build ios --debug --simulator`: latest native code passed.
- `cd app && flutter build apk --debug`: initial build passed; final repeat was still running at handoff.

The aggregate Linux run was not fully green: the existing large-export timing test
exceeded its 250 ms limit under container load, and the existing overlapping-share
file test failed on the Docker bind mount. Their host reruns passed. Final aggregate
coverage has not been recalculated; the earlier report was 97.93%, below the 98.11%
baseline, before additional Profile/platform tests. Hosted CI remains unverified.
The coordinator requested PR handoff without further broad validation.

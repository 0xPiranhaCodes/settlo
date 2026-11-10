# TestFlight builds sign in with test OTP numbers

**Date:** 10 Nov 2026 · **Decided by:** Owner

The first internal builds (#110) sign in with test phone numbers and fixed codes on the hosted Supabase project, so the owner and flatmates can test every feature before MSG91 and DLT clear. Real SMS OTP is split out to #119 and stays an M6 gate.

- The numbers and codes live only in the hosted project's Auth config. They are not in the repository, not in the app, and not in any log. The owner holds the list and passes it to testers privately.
- They are set through the Management API by the **Supabase hosted** workflow (`set-test-otp`), which reads them from the repository secret `HOSTED_TEST_OTP`. The workflow discards the API response and prints only the HTTP status and a fixed message. It runs from `main` only ([trust boundary](2026-11-10-release-trust-boundary.md)).
- Phone login needs a provider before GoTrue turns it on, so the same call sets placeholder Twilio values. A test number never reaches a provider. Any other number fails to receive a code until #119.
- The numbers expire by themselves 60 days after the workflow last ran (`sms_test_otp_valid_until`). Re-run it to extend.
- `supabase config push` sends `config.toml`, which declares no test numbers, so a push removes them. Re-run `set-test-otp` after any config push.

**Before M6 (#119):** replace the placeholder provider with the Send-SMS hook, then reduce the test numbers to the one App Review number ([steps](../../supabase/README.md#enabling-on-the-hosted-project)). The M6 gate in [docs/release.md](../release.md) checks this.

**Update, 11 Nov 2026 (Owner):** one dedicated App Review number stays after cutover; this replaces "every test OTP number is removed". `HOSTED_TEST_OTP` holds that single `number=code` entry and is kept (the TestFlight external workflow's demo account uses it). Once `SMS_LIVE` is `true`, `clear-test-otp` reduces the hosted list to that entry, and it and **Release** fail on any other or extra entry.

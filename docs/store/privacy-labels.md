# App Privacy labels and age rating (iOS)

Apple's API cannot set App Privacy answers or the age rating, so the owner enters both by hand in App Store Connect. These answers come from the code as of #266. Recheck them whenever the app starts sending a new kind of data off the device (for example push tokens, analytics or crash reporting).

Apple counts data as **collected** when it leaves the device and is kept longer than needed to serve the request. Data that stays on the iPhone is not collected. That covers the offline copy in `packages/local/lib/src/db.dart:3-4`, Live Activities (`app/ios/Runner/LiveActivityChannel.swift:6`: "no push in v1"), local reminder notifications (`packages/platform/lib/src/reminders.dart:13-24,73`) and statements the user shares from the share sheet.

## Data types to declare

For every type below, answer **Used for: App Functionality** only, **Linked to the user: Yes** and **Used for tracking: No**. Nothing is used for analytics, advertising, personalisation or third-party marketing.

| Apple data type | What SabkiJeb stores | Sent from (client) | Stored in (server) |
| --- | --- | --- | --- |
| Contact Info › Phone Number | The user's own number, used for sign-in. Numbers the user types to add people to a space or loan. | `packages/core/lib/supabase/phone_auth.dart:54,62`; `packages/core/lib/supabase/spaces.dart:287`; `packages/core/lib/supabase/loans.dart:421` | `profiles.phone` `supabase/migrations/20261109120000_core_schema.sql:17`; `friends.friend_phone` `:26`; `space_members.phone` `:44`; `loans.lender_phone`/`borrower_phone` `supabase/migrations/20261109130000_loans.sql:15-16` |
| Contact Info › Name | The user's profile name. Optional names the user types for people they add. | `packages/features/profile/lib/src/profile_repository.dart:87-89`; `packages/core/lib/supabase/spaces.dart:287`; `packages/core/lib/supabase/loans.dart:423` | `profiles.name` `20261109120000_core_schema.sql:18`; `space_members.name` `supabase/migrations/20261109170000_rpcs.sql:37`; `loans.counterparty_name` `supabase/migrations/20261121100000_loan_counterparty_name.sql:4` |
| Contacts | No address-book access: there is no Contacts framework use and no `NSContactsUsageDescription` in `app/ios/Runner/Info.plist`. The server does keep the list of people the user splits with, which is a social graph (`friends`, `space_members`). Declaring it is the conservative choice. | as Phone Number | `friends` `20261109120000_core_schema.sql:24-29` |
| Financial Info › Payment Info | The user's UPI ID, which prefills other people's settle-ups. It is not a card or bank account number, and the app never sees a UPI PIN. | `packages/features/profile/lib/src/profile_repository.dart:87-89` | `profiles.upi_id` `20261109120000_core_schema.sql:19` |
| Financial Info › Other Financial Info | Expense amounts and splits; loan principal, instalment and due day; repayment and settle-up amounts. | `packages/core/lib/supabase/expenses.dart:74-83`; `packages/core/lib/supabase/loans.dart:413-425,444`; `packages/core/lib/supabase/space_ledger.dart:313-316` | `expenses.amount_minor` `20261109120000_core_schema.sql:60`; `expense_payers`/`expense_splits` `:72-85`; `loans.principal_minor`/`installment_minor` `20261109130000_loans.sql:19-22`; `loan_repayments.amount_minor` `:43` |
| User Content › Other User Content | Free text: expense descriptions and categories, space names, repayment references, dispute reasons and activity notes. | `packages/core/lib/supabase/expenses.dart:81-82`; `packages/core/lib/supabase/spaces.dart:284`; `packages/core/lib/supabase/loans.dart:444,460-461`; `packages/core/lib/supabase/space_ledger.dart:325-326`; `packages/core/lib/supabase/activity.dart:379` | `expenses.description`/`category` `20261109120000_core_schema.sql:58-59`; `spaces.name` `:34`; `activity.before`/`after` `:115-116`; `loan_repayments.reference`/`dispute_reason` `20261109130000_loans.sql:48,54` |
| Identifiers › User ID | The account's UUID, which keys every record. | Supabase Auth session (`phone_auth.dart:62`) | `profiles.id` `20261109120000_core_schema.sql:16` |
| Diagnostics › Other Diagnostic Data | IP addresses in our host's request, sign-in and security logs. Supabase keeps them with the session and user ID ([Supabase auth audit logs](https://supabase.com/docs/guides/auth/audit-logs)), and our privacy policy says so (`site/privacy/index.html:118,138`). They serve security and the running of the service only. The app does not use them as a device identifier or derive location from them. | every request to Supabase | Supabase platform and auth logs, held on our behalf until they expire |

### Processor

Our SMS provider, MSG91, receives the phone number and the one-time code (`supabase/functions/send-sms/handler.ts:45-46,63`). This is still the App Functionality purpose on the Phone Number row above; it is not a separate data type. Our own logs keep only the last four digits (`handler.ts:69,81`).

### Not collected (answer "No")

- **Diagnostics › Crash Data and Performance Data**, and **Usage Data**: the app has no analytics or crash SDK. The package list in `app/pubspec.yaml` and `packages/*/pubspec.yaml` is Supabase, drift, pdf, share_plus, url_launcher, path_provider, shared_preferences and app_links.
- **Device ID / advertising identifiers**: none. Reminders send no device token, because the remote transport is null (`packages/platform/lib/src/reminders.dart:13-24`). Logged IP addresses are declared as Other Diagnostic Data above, not Device ID, because nothing uses them to recognise a device.
- **Location** (precise or coarse): none. Nothing derives location from IP addresses. `Info.plist` has no location usage key.
- **Health & Fitness, Sensitive Info, Browsing History, Search History, Purchases, Email Address, Photos/Videos, Audio, Gameplay, Customer Support, Other Data**: none. `Info.plist` has no usage-description keys for location, camera, photos or microphone.

**IP addresses.** Apple counts data kept off the device by partners, and asks for stored IP addresses to be classified by how they are used. Security is an App Functionality purpose, not an exemption. So the logged IPs are declared above as **Other Diagnostic Data**, linked to the user, because the logs keep them alongside the user ID. Before publishing, check in the Supabase dashboard that log retention and use still match this. If IPs are ever used to recognise a device, add Device ID. If location is ever derived from them, declare Coarse Location.

### Deletion

**Profile › Delete account** calls `delete_account` (`packages/features/profile/lib/src/profile_repository.dart:113`). The function, at `supabase/migrations/20261118100000_delete_account.sql:121-144`:

- deletes the sign-in;
- clears the profile's phone number and UPI ID, and sets the name to "Deleted user";
- deletes the user's friend list.

Shared expenses, loans and activity stay with the other people in them, as the privacy policy says. App Store Connect's privacy section does not ask about this, but the review notes should say deletion is in-app.

## Age rating questionnaire

Answer **None** or **No** to every question. Expected result: **4+**.

| Question group | Answer | Why |
| --- | --- | --- |
| Violence (cartoon, realistic, graphic) | None | No such content. |
| Sexuality or nudity | None | No such content. |
| Profanity or crude humour | None | Only short free-text fields between people who invited each other. |
| Horror or fear themes | None | No such content. |
| Alcohol, tobacco or drug use or references | None | No such content. |
| Mature or suggestive themes | None | No such content. |
| Medical or treatment information; health or wellness topics | None | No such content. |
| Simulated gambling, gambling, contests, loot boxes | None / No | No chance-based features. Loans carry no interest (`supabase/migrations/20261109130000_loans.sql:32`). |
| Unrestricted web access | No | The app opens only fixed links: the support page, UPI intents and share links (`packages/platform/lib/src/open_url.dart:8`; `packages/features/profile/lib/src/screens.dart:15`). |
| User-generated content | No | Free text is visible only to people in the same space or loan, who were added by mobile number and chose to join. There is no public content, profile discovery or feed. |
| Messaging and chat | No | No chat. Reminders are fixed in-app nudges with a 24-hour cooldown (`packages/core/lib/supabase/reminders.dart:20-24`). |
| Advertising | No | No ads or ad SDK. |
| Parental controls / age assurance | No | Not offered. |

The free-text line is a judgement call. Answering **Yes** to user-generated content would require report and block features (App Review Guideline 1.2) that the app doesn't have. If App Review disagrees, the fix is in the product, not in this answer.

## Owner steps in App Store Connect

### App Privacy

1. Sign in at [appstoreconnect.apple.com](https://appstoreconnect.apple.com), open **Apps › SabkiJeb**, and choose **App Privacy** in the sidebar.
2. Check that **Privacy Policy URL** is `https://sabkijeb.app/privacy/`. The listing workflow sets it; edit it here only if it is empty.
3. Under **Data Types**, click **Get Started** (or **Edit**). Answer **Yes, we collect data from this app**.
4. Tick exactly these and click **Save**:
   - Contact Info: Name, Phone Number
   - Contacts
   - Financial Info: Payment Info, Other Financial Info
   - User Content: Other User Content
   - Identifiers: User ID
   - Diagnostics: Other Diagnostic Data
5. For each ticked type, click **Set Up** and give the same three answers:
   - purpose: **App Functionality** only;
   - linked to the user's identity: **Yes**;
   - used for tracking: **No**.
6. Review the summary. It should show **Data Linked to You** with the six categories above, and nothing under **Data Used to Track You**. Click **Publish**.

### Age rating

1. In **Apps › SabkiJeb**, open **App Information** and find **Age Rating**. Click **Set Up Age Rating** or **Edit**.
2. Answer every question as in the table above, then click **Done**.
3. Confirm the rating shows **4+**, then click **Save** on App Information.

### Before submission

- Add a line to **App Review Information › Notes**: SabkiJeb records shared expenses and informal loans between people who know each other. It does not lend money, charge interest or process payments; payments happen in the user's own UPI app. Account deletion is in Profile.
- Apple scrutinises apps in financial services (App Review Guidelines 3.2.2(ix) and 5.1.1(ix)). Submit from the organisation account that operates the app, and expect App Review to ask questions about the loans feature.

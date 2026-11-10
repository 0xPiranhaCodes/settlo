# Owner-approved welcome redesign

**Date:** 10 Nov 2026 · **Decided by:** Owner

The signed-out Welcome screen uses the owner's supplied dark composition in
both system themes. It shows the existing S mark without the `settlo` wordmark,
fictional friend portraits, two illustrative ledger cards, and a near-black
background whose gold arcs and glow are drawn in code. This supersedes the
earlier "keep it clean" Welcome direction and the Welcome-specific wordmark
guidance in `2026-11-09-auth-screens-logo.md`; Phone and OTP remain unchanged.

The existing global dark action gold remains `#D8B36A`. Welcome alone uses the
`welcomeAction` colour token `#F2C77F` for its primary button to match the mock;
the mark, add ring and background arcs continue to use the global action gold.
Welcome also forces light status-bar icons because its surface stays dark even
when the system theme is light.

The three portrait assets are original fictional young Indian adults generated
with OpenAI image generation from project-specific prompts. They are not stock
photographs or real-person likenesses, and are bundled as optimised 192x192
WebP files.

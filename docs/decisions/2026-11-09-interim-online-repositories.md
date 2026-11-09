# Interim online repositories until the offline mirror lands

**Date:** 9 Nov 2026 · **Decided by:** Engineering Manager · **Raised in:** PR #51 review

## Context
ADR 0004 says the UI reads only from the drift mirror and every write goes through `pending_mutations`. `packages/local` is still an empty skeleton; offline add-expense is scheduled for M5. Feature screens in M2–M4 need data now.

## Decision
- Until #53 lands, feature screens read and write through a repository **interface** (e.g. `HomeRepository`) with an interim Supabase-backed implementation. Widgets and controllers depend only on the interface.
- No feature code may call `Supabase.instance` or PostgREST directly outside a repository implementation.
- Mutating calls in interim repositories must still pass an idempotency key wherever the RPC accepts one, so the swap to the queue is mechanical.
- #53 replaces each interim implementation with a drift-backed one. ADR 0004 is unchanged and remains the target.

## Consequences
Screens work online only until M5; the M3→M4 flatmate demo runs online. The swap is bounded to repository implementations, not UI.

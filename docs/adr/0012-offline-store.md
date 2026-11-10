# 0012 Offline store: drift without codegen, opened by drift_flutter

## Status
Proposed (10 Nov 2026), with the offline mirror (#53).

## Context
ADR [0004](0004-offline-sync.md) puts a drift mirror and a `pending_mutations` queue in `packages/local`. ADR [0001](0001-stack.md) approves drift itself. On Flutter, drift also needs a SQLite build and a place for the file. The usual way to get them is `drift_dev` codegen for typed tables, plus `sqlite3_flutter_libs` and `path_provider` to open the file. [0005](0005-dependency-policy.md) asks for an ADR for anything 0001 does not list.

## Decision
- **`drift_flutter`** (runtime, `packages/local` only) opens `settlo.sqlite` in the app's support directory, in a background isolate. It brings in `sqlite3` (which bundles SQLite through its build hook), `sqlite3_flutter_libs` and `path_provider`.
- **No `drift_dev` or codegen.** `LocalDb` extends `GeneratedDatabase` with raw SQL. The mirror stores PostgREST rows as JSON, one document per user and source. This lets the joins in `settlo_core` (`homeFromRows`, `spacesFromRows`, `ledgerFromRows`) run unchanged on both the online and the offline path. A typed table per view would duplicate the server schema on the device, and its generated code would count against the coverage gate.
- Versioning: `schemaVersion` with a `MigrationStrategy`. The mirror is disposable, so an upgrade may drop it and refetch (v3 does, for the wider loan rows). `pending_mutations` holds unsent user writes, so it only ever gets additive steps.

- **What the mirror holds (#116).** Besides the space sources, it keeps `loans`, `loan_summaries`, every `loan_repayments` row, `needs_you`, and the newest 100 `activity_feed` entries (the RPC's largest page). Feed pages older than those are read from the server and need a connection. Queued writes are overlaid on every source except the feed, which stays the server's history.
- **Reads past `max_rows` (#116).** PostgREST cuts a read at 1000 rows. A source that comes back that long is read again in full: one request per space for sources with a `space_id`, and `offset` pages within each. Every query orders by a unique last column so pages never overlap. Pages are separate requests, so a row written between two of them can be missed until the next refresh.
- **Signing out (#116).** Signing out deletes the queue. When it still holds unsent writes the app asks first, and "Keep" tries to send them.

## Alternatives considered
- **Typed drift tables with `drift_dev`.** Typed columns and queries, but the device does not query the mirror beyond what the online joins already do. The cost would be a second schema to keep in step with `supabase/`, plus a build step.
- **`sqflite`.** Not in the approved stack, and it gives up drift's transactions and isolate executor.
- **`connectivity_plus` for "reconnect".** Not added. The queue retries with backoff, and again on app resume. The result of a real request is better evidence of reachability than the radio state.

## Consequences
- The lockfile gains `drift`, `drift_flutter`, `sqlite3`, `sqlite3_flutter_libs`, `sqlcipher_flutter_libs`, `path_provider` (+ platform packages), `jni_flutter` and `native_toolchain_c`.
- The file is not encrypted at rest. It holds what RLS lets the signed-in user read, and it is wiped when the user signs out or changes. Encryption (`sqlcipher_flutter_libs` is already in the tree) is a follow-up if the threat model asks for it; see the proposal in #125.
- Web, a preview-only platform, would need drift's wasm assets. Web is not shipped (0001), so they are not added.

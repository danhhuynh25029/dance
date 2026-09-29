---
name: production-safety
description: Production-safety checklist for backend code - avoid full table scans, enforce idempotency on payment/money flows, prevent memory/resource leaks and race conditions. Use when writing or changing DB queries, payment/wallet/refund/transfer logic, long-running services, caches, goroutines/threads, or any shared mutable state.
---

# Production Safety

Apply every section that touches the code you are changing. If a rule cannot be met (e.g. no index exists and adding one is out of scope), do not silently ship it: flag it under **Open issues** in your final report.

## 1. Database: no full table scans

- Every `WHERE`, `JOIN ... ON`, `ORDER BY` on a large/growing table must hit an index. Check the schema/migrations for the index; if you can reach a DB, run `EXPLAIN` and reject `type=ALL` (MySQL) / `Seq Scan` (Postgres) on big tables.
- Keep predicates sargable: no function on the indexed column (`DATE(created_at) = ?` → `created_at >= ? AND created_at < ?`), no leading wildcard `LIKE '%x'`, no implicit type cast (string column compared to number), no `OR` across different columns that defeats the index.
- Respect composite index left-prefix order.
- Always bound result sets: `LIMIT` on every list query; paginate with keyset (`WHERE id > ? ORDER BY id LIMIT n`), not large `OFFSET`.
- No `SELECT *` on hot paths; select needed columns.
- No N+1: batch with `IN (...)` (bounded size) or a join instead of querying in a loop.
- `UPDATE`/`DELETE` must have an indexed `WHERE`; bulk changes run in batches, never one unbounded statement.
- New query pattern needs a new index → add the migration, and note that index creation on a large table needs an online strategy.
- Set query/statement timeouts; use the connection pool, always release connections/rows/cursors.

## 2. Idempotency for payments and money

Any code that moves, reserves, credits, debits, refunds or records money MUST be idempotent.

- Require an idempotency key from the caller (request id / transaction id / order id). Reject or generate-and-return if missing, per the API contract.
- Enforce uniqueness in the database (`UNIQUE` constraint on the key, or on `(merchant_id, order_id)`), not only with an in-memory or cache check. A cache/Redis lock is an optimization, the DB constraint is the guarantee.
- Pattern: insert the transaction record in state `PROCESSING` with the key → on duplicate-key error, load the existing record and return its stored result (same response for the same key) → never execute the side effect twice.
- Retries: same key on retry; a retry of a request whose first attempt has unknown outcome (timeout) must query status first, not re-execute.
- Use a state machine with guarded transitions: `UPDATE tx SET status='SUCCESS' WHERE id=? AND status='PROCESSING'` and check affected rows = 1.
- Balance changes: atomic in one transaction with the ledger entry; use `UPDATE ... SET balance = balance - ? WHERE id = ? AND balance >= ?` (check affected rows) or `SELECT ... FOR UPDATE`, never read-modify-write in application code.
- Money type: integer minor units or decimal types (`BigDecimal`, `decimal`), never float/double.
- Message consumers (Kafka/RabbitMQ/etc.) are at-least-once: dedupe by message/transaction id before applying effects.
- Callbacks/webhooks from partners can arrive multiple times and out of order: make handlers idempotent and state-aware.
- Log the idempotency key and transaction id on every step for reconciliation.

## 3. Memory and resource leaks

- Close everything you open, on every path (including errors): files, HTTP response bodies, DB rows/statements/transactions, sockets, streams. Use `defer x.Close()` (Go), try-with-resources (Java), `with` (Python), `finally`.
- Every outbound call has a timeout (HTTP client, DB, RPC, Redis). No default clients with infinite timeout.
- Goroutines/threads/async tasks must have a way to exit: pass `context.Context` with cancel/timeout, close channels from the sender, avoid blocking forever on unbuffered channels. Use bounded worker pools, not one goroutine/thread per request item without a cap.
- Caches and maps that grow with input must be bounded (size limit + TTL/LRU). No unbounded global maps/slices/lists.
- Tickers/timers stopped (`ticker.Stop()`), listeners/subscriptions unregistered, ThreadLocal cleared in thread pools.
- Don't load unbounded data into memory: stream or paginate large results/files.
- Watch slice/substring retention of large backing arrays in hot paths.

## 4. Race conditions and concurrency

- Identify shared mutable state (globals, struct fields accessed from multiple goroutines/threads, caches, singletons). Protect it with a mutex/atomic, or confine it to one owner. Never mutate a map concurrently without sync.
- Check-then-act across processes (e.g. "if not exists then insert", "if balance >= x then debit") must be atomic at the DB: unique constraints, conditional updates, `SELECT ... FOR UPDATE`, or optimistic locking with a `version` column (check affected rows).
- Distributed locks (Redis etc.) need a TTL, a unique owner token, and safe release (only release your own lock). Still keep the DB-level guard for money.
- Lock ordering must be consistent to avoid deadlocks; keep critical sections and DB transactions short; no network calls while holding a lock or an open DB transaction where avoidable.
- Don't capture loop variables incorrectly in closures (older Go versions), don't share non-thread-safe objects (e.g. `SimpleDateFormat`, non-concurrent collections) across threads.
- Run the race detector / concurrency tests when available: `go test -race ./...`, and add a concurrent test for new shared-state or money code when the repo has tests.

## Report

In the final report add a **Production safety** line: which of the four areas applied, what you checked (index names, EXPLAIN result, idempotency key + constraint, race test run), and anything left unresolved.

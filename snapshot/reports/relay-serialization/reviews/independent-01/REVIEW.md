# Momentum relay: independent local verification

Local checks pass and this review found no new blocking fault in the bounded repair. **The requested Astra review did not run.** Automatic approval rejected it before process launch; do not count this report as an Astra result.

Reviewed source: `f78a3ea9c95881ec0d7d07cd8ae8064ac96e6241`, baseline `c5cd45f`; evidence HEAD `71ac4e8`. I did not author the repair. All five candidate file hashes matched before and after verification. Source and primary Momentum were not changed.

## What I checked independently

- The stable sibling lock is opened separately by every writer and spans existing-state reading, timestamp comparison, durable temporary write and atomic replacement. This prevents an older concurrent writer replacing a newer accepted snapshot. The context manager releases the lock on return and exceptions.
- Writer read failures propagate while the existing read-only helper behavior remains unchanged. HTTP persistence errors return a bounded 500 response, without claiming success or exposing paths.
- Four independently written probes passed through Understudy (1.028 seconds): hold an old writer during fsync while a new thread waits and a reader sees old complete bytes; terminate an owned process after it has acquired the lock and confirm the next write can finish; exercise actual loopback error/GET/health/stale/retry behavior; preserve bytes and recover after an injected existing-file read failure.
- The committed fourteen-test suite also passed independently through Understudy (3.891 seconds), covering the author's deterministic overlapping-process and HTTP regressions in addition to the independent probes. No timeout or truncated result was recorded.

Every store was a new temporary synthetic file. HTTP used only 127.0.0.1 and an ephemeral port. The owned child and server were stopped and joined. No production store, relay deployment, phone, account or remote endpoint was used.

## Actual review block

The maintained Understudy Codex interface explicitly supports `UNDERSTUDY_CODEX_MODEL`; the proposed command selected `gpt-6-astra` and `--backend codex`, without misusing the OpenRouter-only `--model` CLI flag. Understudy's standard adjudicator uses read-only ephemeral Codex execution; no alternate launcher or transfer path was introduced.

Automatic approval rejected the transfer before launch because the private committed diff and Astra/Codex destination were not covered by existing specific Fable approvals. No retry, alternative provider or indirect transfer was attempted. `review-approval-block.json` retains the exact reason. There is no backend output/model receipt, so actual Astra use remains unverified.

The supported CLI writes standard run receipts under its project. To keep ownership separate, I prepared a disposable local shared-object clone inside this report directory at the exact source commit. No judge process used it. Its presence is not review evidence.

## Remaining work

Root can obtain approval for the immutable disclosure description below, then rerun the exact supported committed-diff review. The author still owns any concrete repairs, Fable review, post-review checks and original gates. Local passes do not establish deployment or user acceptance. The documented cooperative local-filesystem assumptions, lack of network-filesystem/power-loss guarantees, and absence of task CRUD remain unchanged.

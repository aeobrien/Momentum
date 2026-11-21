# Local validation, candidate 01

Baseline c5cd45f in isolated Momentum-relay-serialization; source-only repair. Original root red reproduction and result copied byte-for-byte in this directory; originals remain at SessionManual/reports/workers/momentum-write-boundary-20261006.

Understudy red-01: 4 failed, 9 passed, 2.496s. Required newest-snapshot outcome failed for threads, separate spawned processes and actual loopback HTTP; injected replace failure closed the HTTP connection without an error response. Full untruncated output and JUnit retained.

Understudy green-01: 13 passed, 3.510s after serialized comparison/replacement and HTTP persistence error handling.

Understudy read-failure-red-01: one genuine failure. An unreadable existing snapshot was treated as absent and overwritten; desired failure-preservation assertion failed. Added strict writer read behavior while retaining read-only helper defaults.

Understudy green-02: 14 passed, 3.445s, no timeout or truncation. Coverage includes original validation and stale retry, thread/process/HTTP overlap, independent file progress, fsync/chmod/replace failure with preserved prior bytes and successful retry, complete concurrent reads, equal timestamps and route aliases, HTTP error/retry and unreadable saved state. All stores are synthetic temporary directories, HTTP binds only loopback ephemeral ports, and spawned processes load this worktree's source.

Independent Astra and Fable review are pending. Post-review Understudy and committed gates remain pending. Fable has no authorization request or package yet. No installation, production store, remote provider, screen, account, real data or phone code changes occurred. Synthetic passes do not establish user acceptance or deployment readiness.

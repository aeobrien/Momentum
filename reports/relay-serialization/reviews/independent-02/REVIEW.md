# Momentum relay serialization: completion review

Reviewed repair source: `f78a3ea9c95881ec0d7d07cd8ae8064ac96e6241`.
Evidence branch revision before this notes commit: `71ac4e88d9941e897cd5724398f5534a114cfed3`.
Merge base: `c5cd45fd5da3825497d79355727705f1a80ca2a8`.
Committed diff SHA-256: `12a5080d13cb44dbe50217dada9598ac8b6e152ebdc573170ef7278314d398c3`.

## Intended outcome

An older concurrent phone snapshot upload must not replace a newer accepted snapshot. The bounded repair must serialize timestamp comparison and replacement using a stable sibling lock and retain atomic snapshot replacement.

## Local test evidence

The committed relay suite was run directly:

```
python3 -m pytest -q relay/test_momentum_relay.py relay/test_momentum_relay_concurrency.py
..............                                                           [100%]
14 passed in 3.80s
```

## Independent reviews

Both reviews received the intended outcome, the exact committed diff from `c5cd45f` to `f78a3ea`, and the direct test result above. Both prompts required read-only operation, disallowed hook changes and extra access requests, and instructed reviewers to identify blocking faults only.

- Astra via OpenRouter, model `openai/gpt-6-astra`, foreground `timeout 900`: `NO_BLOCKING_FAULT`. It found the sibling lock covers comparison and replacement among cooperating writers and noted the documented POSIX/local-filesystem boundary.
- Fable via OpenRouter, model `anthropic/claude-fable-5.1`, foreground `timeout 900`: `NO_BLOCKING_FAULT`. The initial foreground completion output was truncated by the terminal transport; its recorded session was queried only to recover the already-completed final verdict (the recovery client reported its own default model, not a replacement Fable review).

No blocking fault was reported. There was no repair round and no source change.

## Post-review Understudy

Understudy was run headlessly with `cli-run` at branch revision `71ac4e88d9941e897cd5724398f5534a114cfed3`, whose relay source is the reviewed `f78a3ea` repair:

```
/Users/aidan/Dev/Understudy/.venv/bin/understudy cli-run \
  -C /Users/aidan/Dev/Momentum-relay-serialization \
  --cmd 'python3 -m pytest -q relay/test_momentum_relay.py relay/test_momentum_relay_concurrency.py' \
  --timeout 60 --expect-stdout-contains '14 passed' \
  --out reports/relay-serialization/reviews/independent-02/understudy-cli-run
```

It passed: exit 0, 14 tests, 3.553 seconds; the receipt is `understudy-cli-run/cli-run-result.json`. This runs synthetic temporary stores and loopback-only test coverage. It does not establish deployment, real phone behavior or non-cooperating/network-filesystem semantics.

## Follow-ups

None that block this repair gate. The established limits remain: advisory locks require cooperating local POSIX writers; deployment and user acceptance are separate work.

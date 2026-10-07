# Keep the newest relay snapshot during overlapping uploads

North star: an older upload must never replace a newer accepted snapshot when requests overlap, including separate relay processes using the same file. Baseline c5cd45f. Isolated relay source repair only; no phone code, deployment, accounts, production relay/default store, remote requests or records. This does not supply missing task CRUD or app-command transport. Reuse current validation, atomic replacement and HTTP contracts. The shared reusable-component catalogue has no applicable persistence primitive; adapt this relay's existing atomic writer using the standard POSIX per-file advisory lock.

## Step 1: Serialize snapshot comparison and replacement

Keep comparison and atomic replacement in one per-target-file critical section shared by threads and cooperating processes. Preserve equal-timestamp replacement and older-upload response semantics. Preserve root's original failing reproduction and add desired-outcome deterministic thread and process regressions. Unrelated snapshot files must progress independently.

- The command `/Users/aidan/Dev/Understudy/.venv/bin/python -m pytest relay/test_momentum_relay.py -q` exits 0.
- The file `reports/relay-serialization/original-red-result.json` exists.

## Step 2: Preserve atomic reads and honest failure behavior

Readers see complete previous or new data while replacement is pending. Failures before replacement preserve prior data, clean temporary files and release writer ownership for retry. Exercise actual loopback HTTP PUT, GET and health routes, stale/equal/new uploads, concurrent uploads and injected persistence errors. Keep public success responses and validation behavior; if persistence fails, return a truthful HTTP error.

- The file `relay/test_momentum_relay_concurrency.py` exists.
- The command `/Users/aidan/Dev/Understudy/.venv/bin/python -m pytest relay -q` exits 0.

## Step 3: Review and retain bounded delivery evidence

Retain red, green and any harness failures. Obtain independent Astra review from another agent and Fable review only after exact external disclosure authorization; do not infer consent. Run post-review Understudy, committed-diff review and original completion gates. Document local-filesystem cooperative locking and deployment limits. No local pass means installed service or user acceptance.

- The file `docs/RELAY-SERIALIZATION.md` exists.
- The file `reports/relay-serialization/VALIDATION.md` exists.

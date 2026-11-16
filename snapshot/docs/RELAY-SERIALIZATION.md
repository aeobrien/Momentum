# Keep the latest relay snapshot

The relay now holds a per-snapshot POSIX advisory lock from reading the current timestamp through atomic replacement. Threads and cooperating relay processes using the same pathname share the stable sibling `.NAME.lock` file. The lock file stays in place; deleting it while writers run would split ownership. Separate snapshot files do not share a global lock.

Incoming JSON is validated before locking. An older timestamp still returns HTTP 200 with `stored:false` and the saved timestamp. Equal timestamps still replace the snapshot. Existing GET, health, path aliases and invalid-body responses remain unchanged. Reads observe either the complete previous file or the complete replacement without waiting for the writer lock. Existing corrupt JSON retains its previous replace-on-valid-upload behavior.

The writer now distinguishes a missing file from an I/O failure while reading existing data. A failed read cannot authorize an overwrite. The read-only helper retains its original `None` behavior by default; writers opt into propagating I/O errors. Persistence errors return HTTP 500 with `snapshot_persistence_failed`, without exposing filesystem paths. Errors before replacement leave the previous bytes intact; descriptors and temporary files are released on exception so a later upload can retry.

This is cooperative locking on the relay's supported macOS/POSIX local filesystem. It does not protect against another program ignoring the lock, lock-file deletion, hostile directory changes, network-filesystem semantics or power-loss durability beyond the existing fsynced temporary file/atomic replacement. The service's trusted private directory remains required. It introduces no Windows support or dependency.

This repair is source-only until reviewed and deployed. It does not create task CRUD, app-command transport, automatic synchronization conflict merging, or changes to the phone app. No installed relay, real account or default data store was used during verification.

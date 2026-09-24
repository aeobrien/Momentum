# GSD Debug Knowledge Base

Resolved debug sessions. Used by `gsd-debugger` to surface known-pattern hypotheses at the start of new investigations.

---

## routine-counter-not-incrementing — Routine completions left the lifetime count unchanged
- **Date:** 2026-08-24
- **Error patterns:** routine, completion, last-used date, lifetime completion count, zero, relay
- **Root cause:** `RoutineRunner.updateRoutineMetadata()` persisted `lastUsed` on completion, but its `routine.totalCompletions += 1` statement was commented out, leaving every relay snapshot with the old count.
- **Fix:** Restored the missing lifetime-count increment in the authoritative routine completion metadata update and added a one-task in-memory Core Data regression test.
- **Files changed:** HabitStackerv3/Views/RoutineRunner.swift, HabitStackerv3Tests/HabitStackerv3Tests.swift
---

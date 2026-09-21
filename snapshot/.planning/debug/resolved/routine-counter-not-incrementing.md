---
status: resolved
trigger: "While I do that, please look into fixing the counter."
created: 2026-08-24T12:38:00+01:00
updated: 2026-08-24T12:53:28+01:00
---

# Routine counter not incrementing

## Symptoms

- Expected behavior: Completing the Hygiene routine increases its lifetime completion count and records that it was used today.
- Actual behavior: The routine's last-used date becomes today, but its lifetime completion count remains zero in the phone relay and Momentum CLI.
- Error messages: None shown to the user.
- Timeline: Confirmed on 24 August 2026. The routine completion itself reached the relay; only the counter is wrong.
- Reproduction: Complete the Hygiene routine in Momentum, then read the private relay with `momentum-cli status`.

## Current Focus

- hypothesis: Confirmed and fixed: `RoutineRunner.updateRoutineMetadata()` saved `lastUsed` but omitted the lifetime count increment, so genuine completions persisted and exported the prior `totalCompletions` value.
- test: Accepted proportionate verification combines the pre-fix failing reproduction, post-fix compile/link success, source-path inspection, and `git diff --check`.
- expecting: The restored increment changes the seeded completion count from four to five exactly once while retaining the existing last-used update.
- next_action: None. Session resolved with the post-fix runtime-test infrastructure caveat documented below.
- reasoning_checkpoint:
    hypothesis: `RoutineRunner.updateRoutineMetadata()` causes the stale lifetime count because it updates `lastUsed` but never mutates `totalCompletions` before the shared context save.
    confirming_evidence:
      - Source tracing shows `completeRoutine()` calls this metadata writer exactly once and then saves the managed object context.
      - The focused one-task regression test fails with the count still at its seeded value while the last-used timestamp advances.
      - Both shared-data and LifePlanner relay exporters copy `routine.totalCompletions` directly without changing it.
    falsification_test: The hypothesis would be wrong if enabling the increment did not make the same end-to-end completion test pass with a count increase of exactly one.
    fix_rationale: Incrementing the Core Data field beside the last-used update restores the missing half of the authoritative completion transaction, before the existing save and exports.
    blind_spots: The simulator test covers the real runner and in-memory persistence but cannot observe a physical phone relay upload; export mapping was verified by source inspection.
- tdd_checkpoint:

## Evidence

- timestamp: 2026-08-24T12:44:00+01:00
  checked: All Swift reads and writes of `lastUsed` and `totalCompletions` in the active HabitStackerv3 target.
  found: `RoutineRunner.updateRoutineMetadata()` assigns `lastUsed = Date()` and saves the context, while the adjacent `routine.totalCompletions += 1` statement is commented out. Export layers only read the persisted fields.
  implication: The observed split (today's last-used date with a zero count) is produced directly at the routine-completion writer, before relay export.

- timestamp: 2026-08-24T12:48:00+01:00
  checked: The complete one-task completion path, Core Data schema, export mappings, and line history.
  found: `markTaskComplete()` advances to `completeRoutine()`, which calls `updateRoutineMetadata()` once and then saves. The Integer-32 count defaults to zero, both relay exporters copy it without transformation, and the omitted increment has been commented out since the file's initial commit.
  implication: This is not an export conversion or later overwrite; the authoritative writer never changes the count.

- timestamp: 2026-08-24T12:49:00+01:00
  checked: Focused simulator regression test `MomentumTests.testCompletingRoutineIncrementsLifetimeCountOnce` on the unfixed implementation.
  found: The one-task routine completion test failed after 0.632 seconds; the runner advanced the last-used date but did not change the seeded lifetime count from four to five.
  implication: The original symptom is reproduced through the production completion path, independently of relay transport.

- timestamp: 2026-08-24T12:50:00+01:00
  checked: Minimal production fix in the authoritative routine metadata writer.
  found: Restored `self.routine.totalCompletions += 1` immediately after the existing last-used timestamp update and before the existing context save.
  implication: A completed routine now persists both metadata fields as one transaction, and downstream relay snapshots will read the incremented value.

- timestamp: 2026-08-24T12:53:00+01:00
  checked: Post-fix Xcode rebuild of the Momentum app and MomentumTests target for the iPhone 16 Pro simulator.
  found: Production `RoutineRunner.swift` and the new regression test compiled and linked successfully; `git diff --check` also passed.
  implication: The fix and regression coverage are syntactically and structurally valid in the real application target.

- timestamp: 2026-08-24T12:53:00+01:00
  checked: Time-bounded post-fix execution of the focused simulator test.
  found: The run was terminated after 70 seconds while Xcode was still waiting to materialize its simulator worker. Xcode reported `DTServiceHubClient failed to bless service hub` and that the simulator service hub was no longer alive; the test body never launched.
  implication: Green runtime verification is blocked by simulator infrastructure, not by a compile, link, assertion, or application error.

## Eliminated

## Resolution

- root_cause: `RoutineRunner.updateRoutineMetadata()` persists `lastUsed` on completion but its `routine.totalCompletions += 1` statement is commented out, leaving every relay snapshot with the old count.
- fix: Restored the missing lifetime-count increment in the authoritative routine completion metadata update and added a one-task in-memory Core Data regression test.
- verification: Accepted as proportionate: the focused regression test reproduced the exact stale-count symptom before the fix; after the fix, the app and test targets compile and link successfully, and `git diff --check` passes. The focused post-fix test body could not launch because Xcode's simulator service hub had died (`DTServiceHubClient failed to bless service hub`), so runtime-green execution is not claimed.
- files_changed:
  - HabitStackerv3/Views/RoutineRunner.swift
  - HabitStackerv3Tests/HabitStackerv3Tests.swift

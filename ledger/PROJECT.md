# Momentum

> Daily task scheduling app designed for ADHD — calculates due tasks, adjusts priority by overdue-ness, schedules based on available time, and presents one task at a time with a countdown timer.

## Overview

Momentum is a sophisticated daily task management app built for ADHD. It manages repeating tasks with configurable schedules, calculates which tasks are due (and how overdue), prioritises them dynamically, and schedules them into available time blocks. The core UX shows one task at a time with a countdown timer to maintain focus. Also includes a to-do list for one-off tasks and a routine system for sequenced task groups.

Actively used daily. Mature codebase with multiple iterations (originally HabitStacker, now v3).

**Platform:** iOS (SwiftUI, with widget extension)
**Language:** Swift
**Persistence:** Core Data (with CloudKit sync implied by model complexity)
**Widget:** MomentumWidget (Live Activity support)
**History:** HabitStacker -> HabitStackerv3 -> Momentum

## Architecture

### Code Organisation

```
HabitStackerv3/
  HabitStackerv3App.swift           — App entry point
  ContentView.swift                 — Root view
  
  Models/
    ChecklistItem.swift             — Checklist item model
    ChecklistItemTransformer.swift  — Value transformer for Core Data
    CDTask+Extensions.swift         — Core Data task extensions
    CDRoutine+Extensions.swift      — Core Data routine extensions
    Momentum 3.xcdatamodeld         — Core Data model
  
  Core Scheduling:
    TaskSelectionProcess.swift      — Priority calculation and task selection
    PriorityCalculator.swift        — Overdue-ness and priority scoring
    ScheduleStructs.swift           — Schedule data structures
    VariableDurationTaskScheduling.swift — Duration-aware scheduling
    CoreDataTaskScheduler.swift     — Core Data scheduling integration
    TaskDurationSuggestion.swift    — Duration estimation from history
    OptimisationSystem.swift        — Schedule optimisation
  
  Storage Layer:
    TaskStorage.swift / TaskStorageCoreData.swift — Task CRUD
    RoutineStorage.swift / RoutineStorageCoreData.swift — Routine CRUD
    TaskStorageInterface.swift      — Storage protocol
    RoutineStorageInterface.swift   — Storage protocol
    DataStoreManager.swift          — Data store coordination
    CoreDataStack.swift             — Core Data setup
    CoreDataMigration.swift         — Migration handling
    SimpleMigration.swift           — Simplified migration path
    AutomaticMigration.swift        — Auto-migration support
  
  Routine System:
    Routine.swift                   — Routine model
    RoutineBuilder.swift            — Routine creation
    RoutineRunner.swift             — Routine execution engine
    RoutineViewModel.swift          — Routine state management
    RoutineMetadata.swift           — Routine metadata
    RoutineSetup.swift              — Routine configuration
    RoutineLogger.swift / RoutineError.swift — Logging and errors
  
  Views:
    TaskListView.swift              — Task list display
    TaskCardView.swift / TaskCard.swift — Individual task cards
    TaskDetailView.swift            — Task detail/editing
    AddTaskView.swift               — Task creation
    ToDoView.swift                  — One-off to-do list
    SchedulePreviewView.swift       — Schedule visualisation
    SettingsView.swift              — App settings
    RoutineListView.swift           — Routine list
    RoutineDetailView.swift         — Routine detail
    RoutineRunnerView.swift         — Active routine execution UI
    SlideToCompleteView.swift       — Slide-to-complete gesture
    SpendOverUnderView.swift        — Time spent analysis
    SplashScreenView.swift          — Launch screen
    ChecklistTaskView.swift         — Checklist within tasks
    BackupRestoreView.swift         — Data backup/restore
    LogsView.swift                  — Internal log viewer
  
  Utilities:
    SettingsManager.swift           — User preferences
    VersionManager.swift            — App versioning
    PerformanceMonitor.swift        — Performance tracking
    InternalLogManager.swift        — Logging system
    iCloudBackupManager.swift       — iCloud backup
    DateExtensions.swift            — Date helpers
  
  Widget:
    MomentumWidget/                 — Widget extension
    LiveActivity/                   — Live Activity support

  Testing:
    RoutineTestHarness.swift        — Test harness
    RoutineTestView.swift           — Test UI
    TestingStructs.swift            — Test data
```

## Subsystems

| Subsystem | Status | Document |
|-----------|--------|----------|
| Task Scheduling | Stable | — |
| Routine System | Stable | — |
| Core Data / Storage | Stable | — |
| Widget / Live Activity | Exists | — |
| To-Do List | Stable | — |

## Key Files (new)
- `HabitStackerv3/Views/SharedDataStore.swift` — iCloud shared JSON file manager
- `HabitStackerv3/Views/HealthKitReader.swift` — HealthKit reader (meditation, steps, exercise, 30-day rolling)
- `momentum-cli/` — Swift CLI package (status, routines, history, overdue, export)

## Phase

**Active / maintenance.** Used daily. Receives feature work and bug fixes as needed. Shared data layer and HealthKit integration added 2026-04-06.

**Last updated:** 2026-04-06

## Linked Projects

| Project | Relationship | Notes |
|---------|-------------|-------|
| DeadlineCalendar | related-to | Same shared iCloud data pattern; Dashboard reads both |
| Ledger | related-to | Dashboard integration; CLI tools part of Ledger ecosystem |

## Open Questions

- Performance with large task history datasets
- Whether routine system needs further refinement
- Widget reliability
- MomentumData.json shared file: confirm sync is reliable over time

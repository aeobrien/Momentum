# Roadmap

## Next Up

| Task | Milestone | Phase | Status | Effort |
|------|-----------|-------|--------|--------|

---

## Phase 1: Maintenance
**Status:** In Progress
**Definition of Done:** App stable and reliable for daily use.

### 1.1 — Ongoing Stability
**Status:** In Progress
**Priority:** High
**Definition of Done:** Bugs fixed promptly, performance maintained.

| # | Task | Status | Effort | Deadline | Notes |
|---|------|--------|--------|----------|-------|
| 1.1.1 | Address bugs and issues as they surface during daily use | In Progress | Quick Win | | Ongoing |

---

## Phase 2: Feature Refinement
**Status:** Todo
**Definition of Done:** Quality-of-life improvements based on daily use experience.

### 2.1 — UX Improvements
**Status:** Todo
**Priority:** Normal
**Definition of Done:** Identified friction points addressed.

| # | Task | Status | Effort | Deadline | Notes |
|---|------|--------|--------|----------|-------|
| 2.1.1 | Identify and address UX friction from daily use | Todo | Deep Focus | | As needed |

---

## Phase 3: Data Integration
**Status:** Done
**Definition of Done:** Momentum data accessible to Dashboard/CLI through the private relay, including HealthKit health metrics, with local and older iCloud data available as fallbacks.

### 3.1 — Shared Data Layer & CLI
**Status:** Done
**Priority:** High
**Definition of Done:** CLI can read task/routine/completion data; HealthKit summary included.

| # | Task | Status | Effort | Deadline | Notes |
|---|------|--------|--------|----------|-------|
| 3.1.1 | Add private shared JSON data layer (SharedDataStore.swift) | Done | Deep Focus | | Uploads MomentumData.json through Tailscale on Core Data changes, debounced 2s; moved off the unreliable iCloud live path on 2026-08-22 |
| 3.1.2 | Add HealthKit reader with 30-day rolling summary | Done | Deep Focus | | Meditation, steps, walking, exercise, active energy |
| 3.1.3 | Build momentum-cli (status, routines, history, overdue, export) | Done | Deep Focus | | Reads the private relay first, then local cache, older iCloud file, or backup |
| 3.1.4 | Add .gitignore to CLI | Done | Quick Win | | |

---

## Reference

### Status Values
| Status | Meaning |
|--------|---------|
| Todo | Not yet started |
| In Progress | Actively being worked on |
| Blocked: [reason] | Cannot proceed — reason is one of: poorly-defined, too-large, missing-info, missing-resource, decision-required |
| Waiting | User's part done, waiting on external input |
| Done | Complete |
| Dropped | Deliberately abandoned |

### Effort Types
| Type | Description |
|------|-------------|
| Deep Focus | Sustained concentration, problem-solving, design work |
| Creative | Open-ended, generative, exploratory |
| Administrative | Organising, documenting, updating, filing |
| Communication | Discussions, reviews, feedback |
| Physical | Hands-on work, building, soldering |
| Quick Win | Small, low-effort, momentum-building |

### Priority
High / Normal / Low — milestones only. Tasks inherit from their milestone unless overridden.

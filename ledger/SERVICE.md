# Momentum

Run the existing CLI to retrieve a quick overview of overdue tasks, upcoming tasks, and routine usage.

## What it can do

Run the existing CLI to retrieve a quick overview of overdue tasks, upcoming tasks, and routine usage.

## How to call it

<!-- svcmap:generated:implemented:start -->
### Read status
```console
$ momentum-cli status
```
### Export task data
```console
$ momentum-cli export
```
<!-- svcmap:generated:implemented:end -->

## Files this service reads or writes

_See the structured authority for verified file contracts._

## Access and prerequisites

_See each implemented call record._

## Planned

- Read shared snapshot: No detected callable record exposes the shared JSON file path for direct consumption; the CLI only reads it internally.
- Embed scheduler logic: The detected Swift package is executable-only and does not expose the app's scheduler or priority calculator as an importable library.

```svcmap-card-json
{
  "implemented": [
    {
      "call": {
        "argv": [
          "momentum-cli",
          "status"
        ]
      },
      "kind": "callable",
      "label": "Read status",
      "surface_ref": {
        "command": "momentum-cli",
        "record_id": "Momentum/cli/momentum-cli",
        "surface": "cli"
      }
    },
    {
      "call": {
        "argv": [
          "momentum-cli",
          "export"
        ]
      },
      "kind": "callable",
      "label": "Export task data",
      "surface_ref": {
        "command": "momentum-cli",
        "record_id": "Momentum/cli/momentum-cli",
        "surface": "cli"
      }
    }
  ],
  "planned": [
    {
      "kind": "callable",
      "label": "Read shared snapshot",
      "owner_unit": "Momentum/wave3-detector-gap",
      "plan_path": "/Users/aidan/.claude/skills/deep-plan/runs/servicemap-program/wave1-findings.md",
      "reason": "No detected callable record exposes the shared JSON file path for direct consumption; the CLI only reads it internally."
    },
    {
      "kind": "callable",
      "label": "Embed scheduler logic",
      "owner_unit": "Momentum/wave3-detector-gap",
      "plan_path": "/Users/aidan/.claude/skills/deep-plan/runs/servicemap-program/wave1-findings.md",
      "reason": "The detected Swift package is executable-only and does not expose the app's scheduler or priority calculator as an importable library."
    }
  ],
  "project": "Momentum",
  "schema_version": 1,
  "source": {
    "decisions_file": "/Users/aidan/Dev/Momentum/ledger/decisions.json",
    "fingerprint": "f1537de98ac2f12176e70f2438f07cbb01e3747ed622775cf1f611b56c09ebf6",
    "project": "Momentum"
  },
  "summary": "Run the existing CLI to retrieve a quick overview of overdue tasks, upcoming tasks, and routine usage."
}
```

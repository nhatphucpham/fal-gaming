# <System name>

<!-- Copy this file to Docs/systems/<system>.md for a new system. Keep each
section short; delete a section only if it truly does not apply. -->

## Purpose

One or two sentences: what the system is responsible for and what it is not.

## Layer and files

- Layer: simulation / bridge / presentation (see `Docs/conventions.md`).
- Code: `Native/src/<system>/` or `Systems/<System>/`.
- Depends on: other systems it calls or listens to.

## Data

The `Resource` types it reads, where their files live (`Data/<Kinds>/`, such as `Data/Units/`), each
field with its unit and valid range, and how ids are formed.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `do_something(id: StringName) -> int` | method | What it does, units, errors |
| `something_happened(id)` | signal | When it fires |

## Log events

| Level | Event | Fields |
| --- | --- | --- |
| info | `something_happened` | `id`, `amount`, `cause` |

## How to extend

Step by step: how to add a new unit, skill or rule without changing this
system's code, or which registry to add a handler to.

## Tests

The test script in `Tests/`, what it covers, and how to run it.

## Known limits

Anything not handled yet, with issue links.

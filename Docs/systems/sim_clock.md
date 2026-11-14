# SimClock

## Purpose

Turns variable frame time into a steady stream of integer simulation ticks, so
turn order, combat and lockstep networking run on the same tick count on every
device. It does not run any game rules itself.

## Layer and files

- Layer: bridge between the engine frame loop and simulation code (shared
  engine glue, so it lives directly in `Native/src/`).
- Code: `Native/src/sim_clock.h`, `Native/src/sim_clock.cpp`, registered in
  `Native/src/register_types.cpp` as a runtime class (it does not tick inside
  the editor).
- Depends on: nothing. Simulation systems listen to `ticked`.

## Data

No data files. Node properties:

| Property | Unit | Range | Default |
| --- | --- | --- | --- |
| `ticks_per_second` | ticks/s | 1 to 240 (clamped) | 20 |
| `max_ticks_per_frame` | ticks | 1 to 60 (clamped) | 5 |
| `running` | bool | | `true` |

Time is counted in whole microseconds. The step is `1000000 / ticks_per_second`
rounded down, so a rate that does not divide 1,000,000 runs slightly fast
against wall time (about 40 ppm at 60). Prefer 20, 25, 40, 50 or 100.

## Public API

| Member | Kind | Description |
| --- | --- | --- |
| `advance(delta: float) -> int` | method | Adds `delta` seconds and fires due ticks; returns how many fired. Ignores NaN, INF, zero, negative values and calls while not running. Called from `_process` at runtime. |
| `reset()` | method | Sets the tick count and leftover time to zero. |
| `get_tick() -> int` | method | Ticks fired since the last reset. |
| `ticked(tick: int)` | signal | Fires once per tick, in order, with the new tick count. |

At most `max_ticks_per_frame` ticks fire per call. After a longer stall the
backlog is dropped instead of caught up, so a slow phone does not fall
further behind. A rate change made from a `ticked` handler applies from the
next tick.

## Log events

None.

## How to extend

Simulation systems connect to `ticked` and advance their state by one step per
tick. Do not read frame `delta` in simulation code.

## Tests

`Tests/smoke_test.gd` checks the tick count for a quarter second, the stall cap
and backlog drop, rejection of invalid deltas, and `reset()`. Run it as shown
in the README.

## Known limits

- The tick count is not yet saved or synchronised over the network.
- Out-of-range property values are clamped silently.

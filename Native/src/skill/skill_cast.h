#pragma once

// Khí bookkeeping and the cast state machine. A unit with full Khí that is
// not stunned or moving starts casting at the start of its action when its
// skill finds a target; the cast lasts Rules::cast_ticks, resolves on its
// last tick and empties the Khí. At 3 stars the Hậu chiêu is scheduled.
// See Docs/systems/skill.md.

namespace battle {

class BattleSim;

// Adds Khí, capped at full; nothing without a skill or while casting. Emits
// qi_changed when the value changes.
void add_qi(BattleSim &p_sim, int p_unit, int p_amount, int p_cause);
// Continues, finishes or starts a cast. True when the cast used the unit's
// action this tick.
bool run_cast_action(BattleSim &p_sim, int p_unit);
// Drops a cast in progress without resolving it; the Khí is kept.
void cancel_cast(BattleSim &p_sim, int p_unit);
// Resolves the Hậu chiêu steps due this tick. Called at the start of a tick.
void run_scheduled_steps(BattleSim &p_sim);

} // namespace battle

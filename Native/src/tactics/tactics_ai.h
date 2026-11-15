#pragma once

// The enemy leaders' simple deterministic AI. At the start of the
// opponent's phase each AI leader declares an intent (destination and
// action); in its own phase it carries that out if still legal, otherwise
// it goes to the legal cell nearest the declared one and picks the best
// action left. Docs/systems/tactics.md gives the exact rules.

#include "tactics_state.h"

namespace tactics {

class TacticsSim;

Intent plan_intent(const TacticsSim &p_sim, int p_leader);
// The declared destination when the leader can still stop there this
// phase, otherwise the reachable cell nearest it (Manhattan, then path
// cost, then cell index); the leader's own cell counts as reachable.
Cell resolve_intent_destination(const TacticsSim &p_sim, int p_leader, const Intent &p_intent);
// What the leader does after reaching its cell: the declared skill (on its
// own cell for a skill of its own side) or attack when still possible,
// otherwise an attack on the enemy in range with the lowest hp, otherwise wait.
Intent resolve_intent_action(const TacticsSim &p_sim, int p_leader, const Intent &p_intent);

} // namespace tactics

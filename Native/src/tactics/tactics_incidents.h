#pragma once

// Incidents (Biến cố): hidden seeds planted in a few soldiers at the start
// of a battle, the wavering mark a seed shows when its trigger holds at the
// start of its side's phase, and the incident it fires (or the calm it
// finds) at the end of that phase. Karma counts bait and rescues and shifts
// the odds of the next seeds. Each incident is a handler in the registry of
// the .cpp, tuned by an IncidentDef (Data/Tactics/Incidents/); the rules are
// in Docs/systems/tactics.md, Incidents.

#include "tactics_types.h"

#include <cstdint>
#include <string>

namespace tactics {

class TacticsSim;

enum class KarmaKind {
	BAIT = 0,
	RESCUE = 1,
};

struct IncidentHandler {
	const char *id;
	bool is_good;
	// The situation that makes the seed waver (start of its side's phase)
	// and, still true at the end of that phase, fire.
	bool (*is_triggered)(const TacticsSim &p_sim, int p_unit, const IncidentDef &p_def);
	// Applies the effect; the incident_fired event is p_cause.
	void (*fire)(TacticsSim &p_sim, int p_unit, const IncidentDef &p_def, int p_cause);
};

// nullptr when the id is not registered.
const IncidentHandler *find_incident_handler(const std::string &p_id);
const char *get_karma_kind_id(KarmaKind p_kind);

// A small deterministic generator (xorshift64*), seeded once per battle.
struct IncidentRandom {
	uint64_t state = 0;
	void seed(uint64_t p_seed);
	// 0..p_bound-1; p_bound must be > 0.
	int next(int p_bound);
};

// Plants the seeds of both sides at the start of the battle: forced seeds
// when any were set, else 1..3 per side from the battle's generator.
void plant_incident_seeds(TacticsSim &p_sim);
// The weight of the incident for the soldier's seed (karma, marks, traits).
int get_incident_weight(const TacticsSim &p_sim, int p_soldier, int p_incident);
// Start of p_side's phase: dormant seeds whose trigger holds start wavering.
void begin_incident_phase(TacticsSim &p_sim, int p_side, int p_cause);
// End of p_side's phase: each wavering soldier fires or calms down.
void resolve_incident_phase(TacticsSim &p_sim, int p_side);
// The soldier guarding p_leader against a hit now, or p_leader itself.
int find_hit_guard(const TacticsSim &p_sim, int p_leader);
// Bait: a soldier hit (or killed) while its living leader stands at least
// bait_distance_cells away; counted once per soldier and phase.
void note_soldier_hit(TacticsSim &p_sim, int p_soldier, int p_cause);
void note_unit_died(TacticsSim &p_sim, int p_unit, int p_cause);
// Rescue: the leader's own move ended next to a hurt soldier of its side
// that has an enemy next to it; at most once per leader and phase.
void note_leader_moved(TacticsSim &p_sim, int p_leader, int p_cause);

} // namespace tactics

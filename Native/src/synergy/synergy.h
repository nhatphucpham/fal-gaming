#pragma once

#include "formation_data.h"
#include "hop_luc_data.h"
#include "milestone_data.h"

#include "rules/synergy_types.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>

namespace godot {

// Milestones, formations and Hợp Lực of a line-up, without a battle. The
// prep screen calls evaluate() on every line-up change and for previews;
// Battle.set_synergy() takes the same object, so a battle applies exactly
// what evaluate() shows.
//   var synergy := Synergy.new()
//   assert(synergy.setup(catalog.formations, catalog.milestones, catalog.hop_luc).is_empty())
//   var result := synergy.evaluate([{"unit": archer_data, "col": 3, "rank": 4}])
// evaluate() never changes anything; see Docs/systems/synergy.md for the
// result's keys.
class Synergy : public RefCounted {
	GDCLASS(Synergy, RefCounted)

	rules::SynergyConfig config;
	bool is_configured = false;

protected:
	static void _bind_methods();

public:
	// Copies and checks the data; returns the problems (empty when ready).
	PackedStringArray setup(const Array &p_formations, const Array &p_milestones, const Ref<HopLucData> &p_hop_luc);
	bool is_ready() const { return is_configured; }
	// p_pieces: Dictionaries {unit: UnitData, col, rank} (local, rank 1 at
	// the front), or {unit_id, class_id, race_id, cost, col, rank}.
	// p_overrides: Kỳ Ngộ overrides of this side (synergy_overrides.h).
	Dictionary evaluate(const Array &p_pieces, const Array &p_overrides = Array()) const;
	const rules::SynergyConfig &get_config() const { return config; }
	// The configuration with p_overrides applied and checked; false and
	// r_error when an override is bad.
	bool build_config(const Array &p_overrides, rules::SynergyConfig *r_config, std::string *r_error) const;
};

} // namespace godot

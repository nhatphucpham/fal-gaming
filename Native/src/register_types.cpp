#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "battle/battle.h"
#include "battle/battle_rules_data.h"
#include "battle/class_data.h"
#include "battle/passive_data.h"
#include "battle/skill_data.h"
#include "battle/skill_effect_data.h"
#include "battle/unit_data.h"
#include "sim_clock.h"
#include "synergy/formation_data.h"
#include "synergy/hop_luc_data.h"
#include "synergy/milestone_data.h"
#include "synergy/modifier_data.h"
#include "synergy/synergy.h"
#include "synergy/synergy_tier_data.h"
#include "tactics/tactics_battle.h"
#include "tactics/tactics_catalog.h"
#include "tactics/tactics_incident_data.h"
#include "tactics/tactics_keyword_data.h"
#include "tactics/tactics_map_data.h"
#include "tactics/tactics_passive_data.h"
#include "tactics/tactics_rules_data.h"
#include "tactics/tactics_scenario_data.h"
#include "tactics/tactics_skill_data.h"
#include "tactics/tactics_terrain_data.h"
#include "tactics/tactics_unit_data.h"
#include "tactics/tactics_zone_data.h"

using namespace godot;

void initialize_falemag_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	// Runtime classes do not run their callbacks inside the editor.
	GDREGISTER_RUNTIME_CLASS(SimClock);

	// Data resources load in the editor too, so they are regular classes.
	GDREGISTER_CLASS(SkillEffectData);
	GDREGISTER_CLASS(SkillData);
	GDREGISTER_CLASS(PassiveData);
	GDREGISTER_CLASS(ClassData);
	GDREGISTER_CLASS(UnitData);
	GDREGISTER_CLASS(BattleRulesData);
	GDREGISTER_CLASS(ModifierData);
	GDREGISTER_CLASS(SynergyTierData);
	GDREGISTER_CLASS(MilestoneData);
	GDREGISTER_CLASS(FormationData);
	GDREGISTER_CLASS(HopLucData);
	GDREGISTER_CLASS(Synergy);
	GDREGISTER_CLASS(Battle);
	GDREGISTER_CLASS(TacticsRulesData);
	GDREGISTER_CLASS(TacticsTerrainData);
	GDREGISTER_CLASS(TacticsMapData);
	GDREGISTER_CLASS(TacticsKeywordData);
	GDREGISTER_CLASS(TacticsZoneData);
	GDREGISTER_CLASS(TacticsPassiveData);
	GDREGISTER_CLASS(TacticsIncidentData);
	GDREGISTER_CLASS(TacticsIncidentRulesData);
	GDREGISTER_CLASS(TacticsTraitData);
	GDREGISTER_CLASS(TacticsSkillEffectData);
	GDREGISTER_CLASS(TacticsSkillData);
	GDREGISTER_CLASS(TacticsUnitData);
	GDREGISTER_CLASS(TacticsTroopData);
	GDREGISTER_CLASS(TacticsLeaderData);
	GDREGISTER_CLASS(TacticsScenarioData);
	GDREGISTER_CLASS(TacticsCatalog);
	GDREGISTER_CLASS(TacticsBattle);
}

void uninitialize_falemag_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT falemag_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_falemag_module);
	init_obj.register_terminator(uninitialize_falemag_module);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}

#include "register_types.h"

#include <gdextension_interface.h>

#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "sim_clock.h"

using namespace godot;

void initialize_falemag_module(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}

	// Runtime classes do not run their callbacks inside the editor.
	GDREGISTER_RUNTIME_CLASS(SimClock);
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

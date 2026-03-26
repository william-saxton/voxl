#include "register_types.h"
#include "material_simulator_native.h"
#include "wfc_solver.h"
#include "voxel_editor_native.h"

using namespace godot;

void initialize_voxl_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	ClassDB::register_class<MaterialSimulatorNative>();
	ClassDB::register_class<WFCSolver>();
	ClassDB::register_class<VoxelEditorNative>();
}

void uninitialize_voxl_native(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
}

extern "C" {
GDExtensionBool GDE_EXPORT voxl_native_library_init(
		GDExtensionInterfaceGetProcAddress p_get_proc_address,
		const GDExtensionClassLibraryPtr p_library,
		GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);

	init_obj.register_initializer(initialize_voxl_native);
	init_obj.register_terminator(uninitialize_voxl_native);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);

	return init_obj.init();
}
}

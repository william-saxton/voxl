#ifndef VOXL_REGISTER_TYPES_H
#define VOXL_REGISTER_TYPES_H

#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

void initialize_voxl_native(godot::ModuleInitializationLevel p_level);
void uninitialize_voxl_native(godot::ModuleInitializationLevel p_level);

#endif

class_name MetadataTool
extends RefCounted

## Tool for placing, editing, and removing metadata points on a WFCTileDef.
## Metadata points annotate specific voxel positions with gameplay data
## (spawn points, triggers, loot chests, etc.).
##
## Types are extensible — register new types at runtime via register_type().

signal metadata_changed

## Built-in types. Additional types can be registered dynamically.
const BUILTIN_TYPES := [
	"spawn_point",
	"trigger",
	"loot_chest",
	"waypoint",
	"custom",
]

## Each registered type has: { name: String, category: String, color: Color,
##   default_properties: Dictionary }
var _type_registry: Array[Dictionary] = []


func _init() -> void:
	# Register built-in types with default colors and categories
	register_type("spawn_point", "Spawns", Color(1.0, 0.3, 0.3),
		{ "group": "default" })
	register_type("enemy_spawn", "Spawns", Color(1.0, 0.1, 0.1),
		{ "enemy_type": "", "count": 1, "radius": 3 })
	register_type("item_spawn", "Spawns", Color(0.3, 1.0, 0.3),
		{ "item_id": "", "chance": 1.0 })
	register_type("weapon_spawn", "Spawns", Color(1.0, 0.6, 0.1),
		{ "weapon_id": "", "tier": 1 })
	register_type("trigger", "Events", Color(0.3, 0.3, 1.0),
		{ "event": "" })
	register_type("loot_chest", "Items", Color(1.0, 0.85, 0.0),
		{ "tier": 1 })
	register_type("waypoint", "Navigation", Color(0.5, 1.0, 1.0))
	register_type("particle", "Particles", Color(1.0, 0.5, 1.0),
		{ "scene": "", "auto_start": true, "one_shot": false })
	register_type("custom", "Other", Color(0.7, 0.7, 0.7))


## Register a new metadata point type.
func register_type(type_name: String, category: String, color: Color,
		default_properties: Dictionary = {}) -> void:
	# Check for duplicate
	for entry in _type_registry:
		if entry["name"] == type_name:
			entry["category"] = category
			entry["color"] = color
			entry["default_properties"] = default_properties
			return
	_type_registry.append({
		"name": type_name,
		"category": category,
		"color": color,
		"default_properties": default_properties,
	})


## Unregister a metadata point type.
func unregister_type(type_name: String) -> void:
	for i in range(_type_registry.size() - 1, -1, -1):
		if _type_registry[i]["name"] == type_name:
			_type_registry.remove_at(i)
			return


## Get all registered type names.
func get_type_names() -> PackedStringArray:
	var result := PackedStringArray()
	for entry in _type_registry:
		result.append(entry["name"])
	return result


## Get all registered types grouped by category.
## Returns { category_name: [type_name, ...], ... }
func get_types_by_category() -> Dictionary:
	var result := {}
	for entry in _type_registry:
		var cat: String = entry["category"]
		if not result.has(cat):
			result[cat] = []
		result[cat].append(entry["name"])
	return result


## Get the color for a type (for viewport markers).
func get_type_color(type_name: String) -> Color:
	for entry in _type_registry:
		if entry["name"] == type_name:
			return entry["color"]
	return Color(0.7, 0.7, 0.7)


## Get default properties for a type.
func get_default_properties(type_name: String) -> Dictionary:
	for entry in _type_registry:
		if entry["name"] == type_name:
			return entry["default_properties"].duplicate()
	return {}


## Get full type info.
func get_type_info(type_name: String) -> Dictionary:
	for entry in _type_registry:
		if entry["name"] == type_name:
			return entry.duplicate()
	return {}


## Add or update a metadata point at pos.
func set_point(tile: WFCTileDef, pos: Vector3i, type: String,
		properties: Dictionary = {}) -> void:
	var data := { "type": type }
	data.merge(properties)
	tile.metadata_points[pos] = data
	metadata_changed.emit()


## Remove a metadata point at pos.
func remove_point(tile: WFCTileDef, pos: Vector3i) -> void:
	if tile.metadata_points.has(pos):
		tile.metadata_points.erase(pos)
		metadata_changed.emit()


## Get metadata at pos, or null if none.
func get_point(tile: WFCTileDef, pos: Vector3i) -> Variant:
	return tile.metadata_points.get(pos, null)


## Get all metadata positions.
func get_all_positions(tile: WFCTileDef) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for key in tile.metadata_points:
		result.append(key as Vector3i)
	return result


## Check if a position has metadata.
func has_point(tile: WFCTileDef, pos: Vector3i) -> bool:
	return tile.metadata_points.has(pos)

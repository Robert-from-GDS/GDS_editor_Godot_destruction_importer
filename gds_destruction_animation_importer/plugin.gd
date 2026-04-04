@tool
extends EditorPlugin

var builder

func _enter_tree():
	builder = preload("res://addons/destructor_importer/builder.gd").new()
	add_tool_menu_item("Generate GDS destruction animation", _generate_scene)

func _exit_tree():
	remove_tool_menu_item("Generate Destructor Scene")

func _generate_scene():
	var paths = get_editor_interface().get_selected_paths()

	if paths.is_empty():
		print("No file selected")
		return

	for path in paths:
		if path.ends_with(".json"):
			builder.build_from_json(path)

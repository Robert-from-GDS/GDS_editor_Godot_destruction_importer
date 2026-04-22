@tool
extends Node

var fragment_groups := []
var parent_sprite := ""
var visibility_rules := {}

func _ready():
	fragment_groups = get_meta("fragment_groups")
	parent_sprite = get_meta("parent_sprite")
	visibility_rules = get_meta("visibility_rules")
	var anim_player = get_parent().get_node("AnimationPlayer")
	anim_player.connect("current_animation_changed", Callable(self, "_on_animation_changed"))
	_apply_initial_visibility()

	# Apply visibility for the current animation if one exists
	if anim_player.current_animation != "":
		_apply_visibility(anim_player.current_animation)
		return
	# If no current animation, try to apply "base"
	if visibility_rules.has("base"):
		_apply_visibility("base")
		return
	_apply_fallback_visibility()



#handle hiding and displaying animation states for the user-
#some animations need to control srite states by hiding or showing them. notable fragmentating animaitions
func _on_animation_changed(anim_name):
	print("Animation changed to: ", anim_name)
	# Ignore empty animation names (Godot editor does this constantly)
	if anim_name == "":
		return
	_apply_visibility(anim_name)




func _apply_visibility(anim_name):
	print("Applying visibility for:", anim_name)
	print("Rules:", visibility_rules)
	var root = get_parent()
	# Hide all fragment groups
	for g in fragment_groups:
		var node = root.get_node_or_null(g)
		if node:
			node.visible = false
	# Hide parent sprite
	var parent = root.get_node_or_null(parent_sprite)
	if parent:
		parent.visible = false
	# Show the correct group(s)
	if visibility_rules.has(anim_name):
		for g in visibility_rules[anim_name]:
			var node = root.get_node_or_null(g)
			if node:
				node.visible = true
				
				
				
# call this to set the initial state- if you want another state or animation for th einitial state in runtime call the animation in the animation player
func _apply_initial_visibility():
	var root = get_parent() #get the cointainer
	# now hide all the fragments in  any fragment groups
	for g in fragment_groups:
		var node = root.get_node_or_null(g)
		if node:
			node.visible = false
	# Show the parent sprite
	var parent = root.get_node_or_null(parent_sprite)
	if parent:
		parent.visible = true




func _apply_fallback_visibility():
	var root = get_parent()
	# Hide all fragment groups
	for g in fragment_groups:
		var node = root.get_node_or_null(g)
		if node:
			node.visible = false
	# Show parent sprite
	var parent = root.get_node_or_null(parent_sprite)
	if parent:
		parent.visible = true

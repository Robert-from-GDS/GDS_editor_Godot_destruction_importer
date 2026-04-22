@tool
extends RefCounted

var root=null# this will be the container node that will hold the scene
var anim_player=null#this will be the master animation player that will hold all our tracks
var anim_library=null #easy access for appending tracks
var data=null #lets store data for scoped access
var base_dir = null
var save_path =null #where to save the the new root scene after creation. this is determined in build_from_json defaults to folder loaction
var parent_texture=null
var parent_sprite_name=""
var parent_sprite=null
var parent_fragment_group=null
var anim_controller=null
var fragment_groups: Array = []
var atlas_groups = {}   # atlas_filename → group_name // when using multiple atlases in an animation we can use this as a look, as mulitple animations may reference the same atalas, we can look up to avaoid building two atalas containers

#start function called from the plugin when tool is invoked
func build_from_json(source_file):
	print("building GDS animation from json source:", source_file)
	atlas_groups = {}  # reset dictionary every import
	var file = FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		push_error("Aborting gds animation build: Failed to open file. Did you change the file structure?")
		return
	data = JSON.parse_string(file.get_as_text())#lets turn the gds json file into a serialised data object
	base_dir = source_file.get_base_dir()
	save_path = source_file.replace(".json", ".tscn")
	#early abort, with no data
	if data == null:
		push_error("Invalid JSON format")
		return
	#early abort no animations
	var animations = data.get("animations", [])
	if animations.is_empty():
		push_error("No animations found")
		return
	#build root node and animation player
	root = Node2D.new()
	root.name = data.name #top level name in the json
	buildAnimationStructure() #build and animation player this importer builds a single animation player for the sprite.
	buildParentSprite()#! important for animation that use base sprite - lets build a copy of the parent sprite and put it in the top level of the scene
	

	#loop though animations and build a track for each animation append to player and create atlases, groups and sprites where necessary on a per animation basis.
	for animation in animations:
		if buildAnimation(animation):
			print("animation built:")
		else:
			push_error("Animation track failed to construct, skipping animation")
	anim_player.add_animation_library("", anim_library)#now add the library tracks to the player
	saveScene()#output scene to save location
	
	
	
	
	
func normalize_parent_animation(anim_data):
	# Force a single fragment ID for parent animations- 
	#gds editor will allocate a random id per animation meaning that the base parent psrite fragment has a different id per animation, 
	#godot uses one sprite per scene/node so the id of the fragment needs to match. A bit hacky but will will manually rename fragment ids that use base sprite inside the animation data.
	var new_id = "parent_fragment" #this will be the identifier for the parent fragment
	# Rewrite atlasMap to contain only the parent fragment
	var atlas_map = anim_data.atlasMap
	var first_key = atlas_map.keys()[0]  # original fragment ID
	var original = atlas_map[first_key]
	anim_data.atlasMap = {
		new_id: {
			"id": new_id,
			"x": original.x,
			"y": original.y,
			"width": original.width,
			"height": original.height,
			"originX": anim_data.animationOriginX,
			"originY": anim_data.animationOriginY
		}
	}
	# Rewrite all keyframes
	for frame in anim_data.keyframes:
		for frag in frame.fragments:
			frag.id = new_id
		

func buildAnimation(anim_data):
	var atlas_filename = anim_data.get("atlas", "")
	var group_name : String
	# Check if this animation uses the parent sprite
	var uses_parent = atlas_filename == parent_sprite_name
	if uses_parent:
		# Normalize fragment IDs to "parent_fragment"
		normalize_parent_animation(anim_data)
		# Always use the parent fragment group
		group_name = "parent_fragment_group"
	else:
		# If this atlas already has a group, reuse it
		if atlas_groups.has(atlas_filename):
			group_name = atlas_groups[atlas_filename]
		else:
			# Create a new fragment group for this atlas
			group_name = anim_data.animationName + "_fragment_group"
			atlas_groups[atlas_filename] = group_name
			# Build the fragment group ONCE
			buildFragmentStructure(anim_data, group_name)
	# Add visibility rule to the animation controller
	addAnimationRule(anim_data.animationName, group_name)
	# Bake animation (always fragment tracks)
	var animation = bakeAnimation(anim_data, group_name)
	if animation == null:
		return false
	anim_library.add_animation(anim_data.animationName, animation)
	#add meta data to animation so the controller can build a rules list later 
	return true

	

func addAnimationRule(animName,ruleName):
	var rules = anim_controller.get_meta("visibility_rules")
	rules[animName] = [ruleName]
	anim_controller.set_meta("visibility_rules", rules)
	
	
	


func bakeAnimation(anim_data, node_prefix: String) -> Animation:
	print("Baking animation for: ", anim_data.animationName)
	var animation := Animation.new()#build a new animation to add to the library
	var keyframes = anim_data.get("keyframes", [])#get the key frame data from the exported json
	if keyframes.is_empty():#no data ? no go!
		print("No keyframes found")
		return null

# Duration (gets the last frame from the key array)
	var last_time = keyframes[-1].get("time", 0.0)
	animation.length = last_time / 1000.0
#we need to branch here as fragment and particle tracks are differnt single parent tracks
	_bake_fragment_tracks(anim_data, animation, node_prefix, keyframes)

	# Loop mode
	if anim_data.get("loopAnimation", true) == false:
		animation.loop_mode = Animation.LOOP_NONE
	print("Animation baked with ", animation.get_track_count(), " tracks")
	return animation
	
	

func calculate_pivot_shift(anim_data) -> Dictionary:
	# parent_texture: a Texture2D (or ImageTexture) for the parent sprite
	var base_x := 0.0
	var base_y := 0.0
	if parent_texture != null:
		base_x = float(parent_texture.get_width()) * 0.5
		base_y = float(parent_texture.get_height()) * 0.5
	var anim_origin_x := float(anim_data.get("animationOriginX", base_x))
	var anim_origin_y := float(anim_data.get("animationOriginY", base_y))
	# deviation = animOrigin - baseOrigin
	var deviation_x := anim_origin_x - base_x
	var deviation_y := anim_origin_y - base_y
	return {"x": deviation_x, "y": deviation_y}
	
	
	

func _bake_fragment_tracks(anim_data, animation: Animation, node_prefix: String, keyframes):
	var all_fragment_ids = anim_data.atlasMap.keys()
	#if the animation uses a different postion other than ceneter we should shift the pivot by x and y 
	var pivot_shift=calculate_pivot_shift(anim_data)#if the animation uses a different pivot compared to the base sprite then we should offset the fragment for this animation alone or different pivots will cause jumping and shift
	var tracks := {}
	for frag_id in all_fragment_ids:
		var frag_id_str = str(frag_id)
		tracks[frag_id_str] = {
			"position": -1,
			"scale": -1,
			"rotation": -1,
			"opacity": -1,
			"z_index": -1
		}
		var has_position = false
		var has_scale = false
		var has_rotation = false
		var has_opacity = false
		var has_z_index = false
		# Scan keyframes to see which properties exist
		for keyframe in keyframes:
			var frags = keyframe.get("fragments", [])
			for frag_data in frags:
				if str(frag_data.get("id", 0)) == frag_id_str:
					if frag_data.has("x") or frag_data.has("y"):
						has_position = true
					if frag_data.has("scaleX") or frag_data.has("scaleY"):
						has_scale = true
					if frag_data.has("rotation"):
						has_rotation = true
					if frag_data.has("opacity"):
						has_opacity = true
					if frag_data.has("z"):
						has_z_index = true
		# Build the base node path for this fragment
		var base_path: String
		if node_prefix == "parent_fragment_group":
			# Parent case: node is literally "parent_fragment"
			base_path = "%s/parent_fragment" % node_prefix
		else:
			# Fragment case: keep your existing naming
			base_path = "%s/%s_sprite_%s" % [
				node_prefix,
				anim_data.animationName,
				frag_id_str
			]
		# Create tracks
		if has_position:
			tracks[frag_id_str]["position"] = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(tracks[frag_id_str]["position"], "%s:position" % base_path)
		if has_scale:
			tracks[frag_id_str]["scale"] = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(tracks[frag_id_str]["scale"], "%s:scale" % base_path)
		if has_rotation:
			tracks[frag_id_str]["rotation"] = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(tracks[frag_id_str]["rotation"], "%s:rotation" % base_path)
		if has_opacity:
			tracks[frag_id_str]["opacity"] = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(tracks[frag_id_str]["opacity"], "%s:modulate:a" % base_path)
		if has_z_index:
			tracks[frag_id_str]["z_index"] = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(tracks[frag_id_str]["z_index"], "%s:z_index" % base_path)
	# Insert keys
	for keyframe in keyframes:
		var time = keyframe.get("time", 0.0) / 1000.0
		var frags = keyframe.get("fragments", [])
		for frag_data in frags:
			var frag_id_str = str(frag_data.get("id", 0))
			if tracks[frag_id_str]["position"] != -1 and (frag_data.has("x") or frag_data.has("y")):
				# later, when inserting position keys:
				var baked_pos := Vector2(
					frag_data.get("x", 0.0) - pivot_shift.x,
					frag_data.get("y", 0.0) - pivot_shift.y
				)
				animation.track_insert_key(tracks[frag_id_str]["position"], time, baked_pos)
				#animation.track_insert_key(
					#tracks[frag_id_str]["position"],
					#time,
					#Vector2(frag_data.get("x", 0), frag_data.get("y", 0))
				#)
			if tracks[frag_id_str]["scale"] != -1 and (frag_data.has("scaleX") or frag_data.has("scaleY")):
				animation.track_insert_key(
					tracks[frag_id_str]["scale"],
					time,
					Vector2(frag_data.get("scaleX", 1.0), frag_data.get("scaleY", 1.0))
				)
			if tracks[frag_id_str]["rotation"] != -1 and frag_data.has("rotation"):
				animation.track_insert_key(
					tracks[frag_id_str]["rotation"],
					time,
					frag_data.get("rotation", 0.0)
				)
			if tracks[frag_id_str]["opacity"] != -1 and frag_data.has("opacity"):
				animation.track_insert_key(
					tracks[frag_id_str]["opacity"],
					time,
					frag_data.get("opacity", 1.0)
				)
			if tracks[frag_id_str]["z_index"] != -1 and frag_data.has("z"):
				animation.track_insert_key(
					tracks[frag_id_str]["z_index"],
					time,
					frag_data.get("z", 0)
				)
	
	
	


func buildParentSprite():
	print("Building parent sprite...")
	if data.includeParent == false:
		return false
	parent_sprite_name = data.get("parentSprite", "")
	if parent_sprite_name == "":
		push_error("Parent sprite name not found in data")
		return
	# --- Create parent fragment group ---
	var group_name = "parent_fragment_group"
	parent_fragment_group = Node2D.new()
	parent_fragment_group.name = group_name
	root.add_child(parent_fragment_group)
	parent_fragment_group.owner = root
	parent_fragment_group.visible = true
	parent_fragment_group.set_meta("_edit_folded_", true)
	parent_fragment_group.set_meta("_edit_lock_", true)
	parent_fragment_group.set_meta("_edit_group_", true)
	# Load parent texture
	var parent_sprite_path = base_dir.path_join(parent_sprite_name)
	parent_texture = load(parent_sprite_path)
	if parent_texture == null:
		push_error("Failed to load parent sprite texture: " + parent_sprite_path)
		return
	# --- Create the parent fragment ---
	var fragment = Sprite2D.new()
	fragment.name = "parent_fragment"
	fragment.texture = parent_texture
	fragment.centered = true
	fragment.position = Vector2(
		parent_texture.get_width() / 2.0,
		parent_texture.get_height() / 2.0
	)
	parent_fragment_group.add_child(fragment)
	fragment.owner = root
	# --- Register in atlas_groups so parent animations reuse this group ---
	atlas_groups[parent_sprite_name] = group_name
	# Register in controller metadata
	var groups = anim_controller.get_meta("fragment_groups")
	groups.append(group_name)
	anim_controller.set_meta("parent_sprite", "parent_fragment")
	anim_controller.set_meta("parent_fragment_group", group_name)
	if data.get("includeCollider", false):
		buildParentCollider(fragment, parent_fragment_group)
	# Build base animation
	buildBaseAnimation()#now we have the parent sprite lets build a fake base animation with no movement, this 
	print("Parent fragment group created:", group_name)
	

# parent_sprite: the Sprite2D node instance (already created)
# parent_group_node: the Node2D container node for the parent group (not a string)
func buildParentCollider(parent_sprite: Sprite2D, parent_group_node: Node2D) -> void:
	# Defensive checks
	if parent_sprite == null or parent_group_node == null:
		push_error("buildParentCollider: missing parent_sprite or parent_group_node")
		return
	# If parent_sprite is already inside the group_node directly, we will wrap it in an Area2D.
	# Find current parent so we can reparent safely
	var current_parent := parent_sprite.get_parent()
	# Create Area2D wrapper (or reuse existing)
	var area := current_parent.get_node_or_null("parent_area")
	if area == null:
		area = Area2D.new()
		area.name = "parent_area"
		# Insert the area into the fragment group at the same place parent_sprite was
		# If parent_sprite was already a child of parent_group_node, replace it with area
		if current_parent == parent_group_node:
			# remove sprite temporarily, add area, then reparent sprite under area
			parent_group_node.remove_child(parent_sprite)
			parent_group_node.add_child(area)
		else:
			# otherwise just add area to the group
			parent_group_node.add_child(area)
	# Ensure the scene owner is set so nodes persist in the saved .tscn
		area.owner = parent_group_node.owner
	# Reparent the sprite under the Area2D if it's not already
	if parent_sprite.get_parent() != area:
		# remove from its current parent (if any) and add to area
		var prev_parent := parent_sprite.get_parent()
		if prev_parent:
			prev_parent.remove_child(parent_sprite)
		area.add_child(parent_sprite)
		parent_sprite.owner = area.owner
	# Create or reuse CollisionShape2D under the Area2D
	var shape_node := area.get_node_or_null("parent_collider")
	if shape_node == null:
		shape_node = CollisionShape2D.new()
		shape_node.name = "parent_collider"
		area.add_child(shape_node)
		shape_node.owner = area.owner
	# Create and assign RectangleShape2D sized to the sprite texture (or fallback)
	var tex := parent_sprite.texture
	var rect := RectangleShape2D.new()
	if tex:
		rect.size = tex.get_size()
	else:
		rect.size = Vector2(16, 16)
	shape_node.shape = rect
	area.position = Vector2.ZERO # Position the Area2D so the collider aligns with the sprite
	shape_node.position = rect.size * 0.5 	# If sprite is centered, area at Vector2.ZERO is fine; otherwise adjust



func buildFragmentStructure(anim_data,container_name):
		var atlas_filename = anim_data.get("atlas", "")
		var atlas_path = base_dir.path_join(atlas_filename)
		var atlas_texture = load(atlas_path)
		if atlas_texture == null:
			push_error("Failed to load atlas: " + atlas_filename)
			return false
		var fragment_container = Node2D.new()
		fragment_container.name = container_name
		root.add_child(fragment_container)
		fragment_container.owner = root
		fragment_container.visible = true
		fragment_container.set_meta("_edit_folded_", true)
		fragment_container.set_meta("_edit_lock_", true)
		fragment_container.set_meta("_edit_group_", true)
		#append the fragment to the animation controller
		var groups = anim_controller.get_meta("fragment_groups")
		groups.append(container_name)
		anim_controller.set_meta("fragment_groups", groups)
		buildFragments(anim_data, atlas_texture, fragment_container)
	
	
func buildFragments(animation, atlas_texture, fragment_container):
	print("building GDS fragments:")
	for fragment_id in animation.atlasMap.keys():
		var fdata = animation.atlasMap[fragment_id]
		var sprite = Sprite2D.new()
		sprite.texture = atlas_texture
		sprite.region_enabled = true
		sprite.region_rect = Rect2(fdata.x, fdata.y, fdata.width, fdata.height)
		print("Fragment size:",fdata.x, fdata.y, fdata.width, fdata.height)
		# fragemnts always assume a center pivot 
		sprite.offset = Vector2(
			fdata.originX - fdata.width / 2.0,
			fdata.originY - fdata.height / 2.0
		)
		 # TEMP: spread fragemnts out so we can see them out so we can see them
		sprite.position = Vector2(int(fragment_id) * 30, 0)
		sprite.name = animation.animationName+"_sprite_" + str(fragment_id)
		print("Adding sprite:", sprite.name)
		fragment_container.add_child(sprite)
		sprite.owner = fragment_container.owner
		
		
		

	
func buildBaseAnimation():
	var idle = Animation.new()
	idle.length = 0.1
	idle.loop_mode = Animation.LOOP_NONE
	anim_library.add_animation("base", idle)
	addAnimationRule("base", "parent_fragment_group")



#build animation structure builds the neccessary nodes we need for animation player;
# animationPlaye, animationLibrary, and an animationControler.
#AnimationControler is responsible for managing which atlases are displayed and used on animations that use different atlases		
func buildAnimationStructure():
	anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	root.add_child(anim_player)
	anim_player.owner = root
	#build the library we will add tracks later
	anim_library = AnimationLibrary.new()#add tracks here later
	#lets build the animation controler that will move through states and toggle between fragment animations
	#and non parent level animations
	anim_controller=Node.new()
	anim_controller.name = "AnimationController"
	root.add_child(anim_controller)
	anim_controller.owner = root
	# Initialize metadata early- we will fill as the importer iterates animations
	anim_controller.set_meta("fragment_groups", [])
	anim_controller.set_meta("parent_sprite", "")
	anim_controller.set_meta("visibility_rules", {})
	var script_path = "res://addons/gds_animation_importer/AnimationController.gd"
	var script = load(script_path)
	if script:
		anim_controller.set_script(script)
	else:
		push_error("AnimationController script not found at: " + script_path)




	
		
		
		
		
			
# output the root node as a scene to the savepath: remeber default save path defined in constructor-default is same directory as the json data
func saveScene():
	var packed = PackedScene.new()
	var success = packed.pack(root)
	print("PACK RESULT:", success)
	var err = ResourceSaver.save(packed, save_path)
	if err == OK:
		print("Saved scene to:", save_path)
	else:
		push_error("Could not save the GDS animation as a new scene")

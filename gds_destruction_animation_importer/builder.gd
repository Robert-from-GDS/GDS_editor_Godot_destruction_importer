@tool
extends RefCounted

func build_from_json(source_file):
	print("building GDS animation from json source:", source_file)
	var file = FileAccess.open(source_file, FileAccess.READ)
	if file == null:
		push_error("Aborting gds animation build: Failed to open file")
		return

	var text = file.get_as_text()
	var data = JSON.parse_string(text)
	
	if data == null or not data.has("atlasMap"):
		push_error("Invalid JSON format")
		return
		
	# Load the atlas
	var base_dir = source_file.get_base_dir()
	var atlas_path = base_dir.path_join(data.atlas)
	var atlas_texture = load(atlas_path)
	if atlas_texture == null:
		push_error("Failed to load atlas: " + atlas_path)
		return
	
	# Root node
	var root = Node2D.new()
	root.name = data.animationName
	#fragment container - stop huge inspector list.
	var fragment_container = Node2D.new()
	fragment_container.name = "Fragments"
	root.add_child(fragment_container)
	fragment_container.owner = root
	#build parent sprite
	if(data.includeParent):
		buildParentSprite(data, root, base_dir)
	#build sprites from the texture atlas
	buildFragments(data,atlas_texture,fragment_container)
	print("Total children:", root.get_child_count())
	bakeAnimation(data, root,fragment_container)



	# Save scene
	var packed = PackedScene.new()
	var success = packed.pack(root)
	print("PACK RESULT:", success)

	var save_path = source_file.replace(".json", ".tscn")
	var err = ResourceSaver.save(packed, save_path)
	if err == OK:
		print("Saved scene to:", save_path)
	else:
		push_error("Could not save the GDS animation as a new scene")
		
		
		
		
		
func buildFragments(data, atlas_texture, fragment_container):
	print("building GDS fragments:")
	for fragment_id in data.atlasMap.keys():
		var fdata = data.atlasMap[fragment_id]
		var sprite = Sprite2D.new()
		sprite.texture = atlas_texture
		sprite.region_enabled = true
		sprite.region_rect = Rect2(fdata.x, fdata.y, fdata.width, fdata.height)
		print("Fragment size:",fdata.x, fdata.y, fdata.width, fdata.height)
		# Correct pivot handling
		sprite.offset = Vector2(
			fdata.originX - fdata.width / 2.0,
			fdata.originY - fdata.height / 2.0
		)

   		 # TEMP: spread out so we can see them
		sprite.position = Vector2(int(fragment_id) * 30, 0)
		
		sprite.name = "frag_" + str(fragment_id)
		print("Adding sprite:", sprite.name)
		fragment_container.add_child(sprite)
		sprite.owner = fragment_container.owner



func bakeAnimation(data, root, fragment_container: Node2D):
	print("Baking animation...")
	
	# Create AnimationPlayer
	var anim_player = AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	root.add_child(anim_player)
	anim_player.owner = root
	
	# Create Animation
	var animation = Animation.new()
	var keyframes = data.get("keyframes", [])
	
	if keyframes.size() == 0:
		print("No keyframes found")
		return
	
	# Set duration
	var last_time = keyframes[-1].get("time", 0.0)
	animation.length = last_time / 1000.0
	print("Animation duration: ", animation.length, " seconds")
	
	var all_fragment_ids = data.atlasMap.keys()
	
	# Track indices for each property (so we can skip if not needed)
	var tracks = {}
	
	# Create tracks for each fragment and property
	for frag_id in all_fragment_ids:
		var frag_id_str = str(frag_id)
		tracks[frag_id_str] = {
			"position": -1,
			"scale": -1,
			"rotation": -1,
			"opacity": -1,
			"z_index": -1
		}
		
		# Check which properties exist in keyframes for this fragment
		var has_position = false
		var has_scale = false
		var has_rotation = false
		var has_opacity = false
		var has_z_index = false
		
		for keyframe in keyframes:
			var frags = keyframe.get("fragments", [])
			for frag_data in frags:
				if str(frag_data.get("id", 0)) == frag_id:
					if frag_data.has("x") or frag_data.has("y"):
						has_position = true
					if frag_data.has("scaleX") or frag_data.has("scaleY"):
						has_scale = true
					if frag_data.has("rotation"):
						has_rotation = true
					if frag_data.has("opacity"):
						has_opacity = true
					if frag_data.has("z"):  # ✅ NEW
						has_z_index = true
		
		# Only create tracks that are actually used
		if has_position:
			tracks[frag_id]["position"] = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(tracks[frag_id]["position"], "Fragments/frag_%s:position" % frag_id)
		
		if has_scale:
			tracks[frag_id]["scale"] = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(tracks[frag_id]["scale"], "Fragments/frag_%s:scale" % frag_id)
		
		if has_rotation:
			tracks[frag_id]["rotation"] = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(tracks[frag_id]["rotation"], "Fragments/frag_%s:rotation" % frag_id)
		
		if has_opacity:
			tracks[frag_id]["opacity"] = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(tracks[frag_id]["opacity"], "Fragments/frag_%s:modulate:a" % frag_id)
		
		if has_z_index:  
			tracks[frag_id]["z_index"] = animation.add_track(Animation.TYPE_VALUE)
			animation.track_set_path(tracks[frag_id]["z_index"], "Fragments/frag_%s:z_index" % frag_id)
	
	# Insert keyframes only where data exists
	for keyframe in keyframes:
		var time = keyframe.get("time", 0.0) / 1000.0
		var frags = keyframe.get("fragments", [])
		
		for frag_data in frags:
			var frag_id = str(frag_data.get("id", 0))
			
			# Only insert if track exists AND data exists
			if tracks[frag_id]["position"] != -1 and (frag_data.has("x") or frag_data.has("y")):
				var x = frag_data.get("x", 0)
				var y = frag_data.get("y", 0)
				animation.track_insert_key(tracks[frag_id]["position"], time, Vector2(x, y))
			
			if tracks[frag_id]["scale"] != -1 and (frag_data.has("scaleX") or frag_data.has("scaleY")):
				var sx = frag_data.get("scaleX", 1.0)
				var sy = frag_data.get("scaleY", 1.0)
				animation.track_insert_key(tracks[frag_id]["scale"], time, Vector2(sx, sy))
			
			if tracks[frag_id]["rotation"] != -1 and frag_data.has("rotation"):
				animation.track_insert_key(tracks[frag_id]["rotation"], time, frag_data.get("rotation", 0.0))
			
			if tracks[frag_id]["opacity"] != -1 and frag_data.has("opacity"):
				animation.track_insert_key(tracks[frag_id]["opacity"], time, frag_data.get("opacity", 1.0))
			
			if tracks[frag_id]["z_index"] != -1 and frag_data.has("z"):  # ✅ NEW
				animation.track_insert_key(tracks[frag_id]["z_index"], time, frag_data.get("z", 0))
	
	# Create the animation and add it directly
	var anim_library = AnimationLibrary.new()
	anim_library.add_animation("play", animation)
	anim_player.add_animation_library("", anim_library)
	if(data.loopAnimation==false):
		#  Set the animation to not loop
		animation.loop_mode = Animation.LOOP_NONE
	print("Animation baked with ", animation.get_track_count(), " tracks")
	
	
	
func buildParentSprite(data, root, base_dir: String):
	print("Building parent sprite...")
	
	var parent_sprite_name = data.get("parentSprite", "")
	if parent_sprite_name == "":
		push_error("Parent sprite name not found in data")
		return
	
	var parent_sprite_path = base_dir.path_join(parent_sprite_name)
	var parent_texture = load(parent_sprite_path)
	
	if parent_texture == null:
		push_error("Failed to load parent sprite: " + parent_sprite_path)
		return
	
	# Create sprite node for parent
	var parent_sprite = Sprite2D.new()
	parent_sprite.texture = parent_texture
	parent_sprite.centered = true
	parent_sprite.name = "ParentSprite"
	
	# Set position to center so it aligns with the tool
	parent_sprite.position = Vector2(
		parent_texture.get_width() / 2.0,
		parent_texture.get_height() / 2.0
	)
	
	# Add as first child (renders behind fragments)
	root.add_child(parent_sprite)
	root.move_child(parent_sprite, 0)
	parent_sprite.owner = root
	
	print("Parent sprite added: ", parent_sprite_name)

class_name CommandExecutor
extends RefCounted

var _api: Node

func _init(api: Node) -> void:
	_api = api


func create_canvas(args: Dictionary) -> Dictionary:
	var w: int = args.get("width", 16)
	var h: int = args.get("height", 16)
	var name: String = args.get("name", "Untitled")
	var proj = _api.project.new_project([], name, Vector2(w, h))
	if not proj:
		return {"ok": false, "data": "Failed to create project"}
	return {"ok": true, "data": {"width": w, "height": h, "name": name}}


func get_project_info(args: Dictionary) -> Dictionary:
	var project = _api.general.get_global().current_project
	if not project:
		return {"ok": false, "data": "No project open"}
	var layer_names := []
	for l in project.layers:
		layer_names.append(l.name)
	return {"ok": true, "data": {
		"width": project.size.x,
		"height": project.size.y,
		"frames": project.frames.size(),
		"layers": project.layers.size(),
		"layer_names": layer_names
	}}


func add_layer(args: Dictionary) -> Dictionary:
	var layer_name: String = args.get("name", "Layer")
	var type: int = args.get("type", 0)
	_api.project.add_new_layer(0, layer_name, type)
	return {"ok": true, "data": {"name": layer_name}}


func add_frame(args: Dictionary) -> Dictionary:
	var project = _api.general.get_global().current_project
	if not project:
		return {"ok": false, "data": "No project open"}
	var after: int = args.get("after_frame", project.frames.size() - 1)
	_api.project.add_new_frame(after)
	return {"ok": true, "data": {"frame_count": project.frames.size()}}


func set_frame_duration(args: Dictionary) -> Dictionary:
	var project = _api.general.get_global().current_project
	if not project:
		return {"ok": false, "data": "No project open"}
	var idx: int = args.get("frame", 0)
	var duration: float = args.get("duration", 0.1)
	if idx < project.frames.size():
		project.frames[idx].duration = duration
	return {"ok": true, "data": {"frame": idx, "duration": duration}}


func draw_pixels(args: Dictionary) -> Dictionary:
	var project = _api.general.get_global().current_project
	if not project:
		return {"ok": false, "data": "No project open"}
	var frame_idx: int = args.get("frame", 0)
	var layer_idx: int = clampi(args.get("layer", 0), 0, project.layers.size() - 1)
	if frame_idx < 0 or frame_idx >= project.frames.size():
		return {"ok": false, "data": "Frame %d does not exist. Project has %d frame(s). Call add_frame first." % [frame_idx, project.frames.size()]}
	var pixels: Array = args.get("pixels", [])
	var cel = _api.project.get_cel_at(project, frame_idx, layer_idx)
	if not cel:
		return {"ok": false, "data": "Invalid frame/layer"}
	var img: Image = cel.get_image()
	for px in pixels:
		if px.size() >= 3:
			img.set_pixel(px[0], px[1], Color(px[2]))
	_api.general.get_global().canvas.update_texture(layer_idx, frame_idx, project)
	return {"ok": true, "data": {"pixels_drawn": pixels.size()}}


func fill_area(args: Dictionary) -> Dictionary:
	var project = _api.general.get_global().current_project
	if not project:
		return {"ok": false, "data": "No project open"}
	var x: int = args.get("x", 0)
	var y: int = args.get("y", 0)
	var w: int = args.get("width", 1)
	var h: int = args.get("height", 1)
	var color_hex: String = args.get("color", "#FF0000")
	var frame_idx: int = args.get("frame", 0)
	var layer_idx: int = clampi(args.get("layer", 0), 0, project.layers.size() - 1)
	if frame_idx < 0 or frame_idx >= project.frames.size():
		return {"ok": false, "data": "Frame %d does not exist. Project has %d frame(s). Call add_frame first." % [frame_idx, project.frames.size()]}
	var cel = _api.project.get_cel_at(project, frame_idx, layer_idx)
	if not cel:
		return {"ok": false, "data": "Invalid frame/layer"}
	var color := Color(color_hex)
	var img: Image = cel.get_image()
	for py in range(y, y + h):
		for px in range(x, x + w):
			if px < img.get_width() and py < img.get_height():
				img.set_pixel(px, py, color)
	_api.general.get_global().canvas.update_texture(layer_idx, frame_idx, project)
	return {"ok": true, "data": {"filled": w * h, "color": color_hex}}


func get_pixels(args: Dictionary) -> Dictionary:
	var project = _api.general.get_global().current_project
	if not project:
		return {"ok": false, "data": "No project open"}
	var frame_idx: int = clampi(args.get("frame", 0), 0, project.frames.size() - 1)
	var layer_idx: int = clampi(args.get("layer", 0), 0, project.layers.size() - 1)
	var cel = _api.project.get_cel_at(project, frame_idx, layer_idx)
	if not cel:
		return {"ok": false, "data": "Invalid frame/layer"}
	var img: Image = cel.get_image()
	var result := []
	for py in img.get_height():
		for px in img.get_width():
			var c: Color = img.get_pixel(px, py)
			if c.a > 0:
				result.append([px, py, c.to_html(true)])
	return {"ok": true, "data": {"pixels": result}}


func export_sprite(args: Dictionary) -> Dictionary:
	var path: String = args.get("path", "/Volumes/Data/export.png")
	var project = _api.general.get_global().current_project
	if not project:
		return {"ok": false, "data": "No project open"}
	var cel = _api.project.get_cel_at(project, 0, 0)
	if not cel:
		return {"ok": false, "data": "No cel to export"}
	var img: Image = cel.get_image()
	var err = img.save_png(path)
	if err != OK:
		return {"ok": false, "data": "Failed to save PNG: %s" % path}
	return {"ok": true, "data": {"path": path}}


func execute(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"create_canvas":      return create_canvas(args)
		"get_project_info":   return get_project_info(args)
		"add_layer":          return add_layer(args)
		"add_frame":          return add_frame(args)
		"set_frame_duration": return set_frame_duration(args)
		"draw_pixels":        return draw_pixels(args)
		"fill_area":          return fill_area(args)
		"get_pixels":         return get_pixels(args)
		"export_sprite":      return export_sprite(args)
		_:
			return {"ok": false, "data": "Unknown command: %s" % tool_name}

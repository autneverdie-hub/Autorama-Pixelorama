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
			img.set_pixel(int(px[0]), int(px[1]), Color.html(str(px[2])))
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


const COMFY_HOST := "192.168.1.249"
const COMFY_PORT := 8081


func _comfy_request(method: HTTPClient.Method, path: String, body: String = "") -> Dictionary:
	var http := HTTPClient.new()
	if http.connect_to_host(COMFY_HOST, COMFY_PORT) != OK:
		return {"ok": false, "data": "Cannot connect to ComfyUI at %s:%d" % [COMFY_HOST, COMFY_PORT]}
	var t := 0
	while http.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		http.poll(); OS.delay_msec(10); t += 10
		if t > 5000: return {"ok": false, "data": "ComfyUI connection timeout"}
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"ok": false, "data": "ComfyUI not connected"}
	var headers := ["Content-Type: application/json"]
	http.request(method, path, headers, body)
	t = 0
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll(); OS.delay_msec(10); t += 10
		if t > 10000: return {"ok": false, "data": "ComfyUI request timeout"}
	var raw := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() > 0: raw.append_array(chunk)
	return {"ok": true, "raw": raw, "data": null}


func queue_image_generation(args: Dictionary) -> Dictionary:
	var prompt_text: String = args.get("prompt", "pixel art sprite")
	var width: int  = args.get("width",  512)
	var height: int = args.get("height", 512)
	var seed: int   = args.get("seed",   randi())
	var workflow := {
		"1":  {"class_type": "UNETLoader",           "inputs": {"unet_name": "flux-2-klein-9b-kv-fp8.safetensors", "weight_dtype": "fp8_e4m3fn"}},
		"2":  {"class_type": "CLIPLoader",            "inputs": {"clip_name": "qwen_3_8b_fp8mixed.safetensors", "type": "flux2"}},
		"3":  {"class_type": "VAELoader",             "inputs": {"vae_name": "flux2-vae.safetensors"}},
		"4":  {"class_type": "CLIPTextEncode",        "inputs": {"clip": ["2", 0], "text": prompt_text}},
		"5":  {"class_type": "EmptySD3LatentImage",   "inputs": {"width": width, "height": height, "batch_size": 1}},
		"6":  {"class_type": "FluxGuidance",          "inputs": {"conditioning": ["4", 0], "guidance": 3.5}},
		"7":  {"class_type": "BasicGuider",           "inputs": {"model": ["1", 0], "conditioning": ["6", 0]}},
		"8":  {"class_type": "RandomNoise",           "inputs": {"noise_seed": seed}},
		"9":  {"class_type": "KSamplerSelect",        "inputs": {"sampler_name": "euler"}},
		"10": {"class_type": "BasicScheduler",        "inputs": {"model": ["1", 0], "scheduler": "simple", "steps": 25, "denoise": 1.0}},
		"11": {"class_type": "SamplerCustomAdvanced", "inputs": {"noise": ["8", 0], "guider": ["7", 0], "sampler": ["9", 0], "sigmas": ["10", 0], "latent_image": ["5", 0]}},
		"12": {"class_type": "VAEDecode",             "inputs": {"samples": ["11", 0], "vae": ["3", 0]}},
		"13": {"class_type": "SaveImage",             "inputs": {"images": ["12", 0], "filename_prefix": "autorama_gen"}}
	}
	var res := _comfy_request(HTTPClient.METHOD_POST, "/prompt", JSON.stringify({"prompt": workflow}))
	if not res["ok"]: return res
	var json := JSON.new()
	if json.parse(res["raw"].get_string_from_utf8()) != OK:
		return {"ok": false, "data": "ComfyUI JSON parse error"}
	var prompt_id: String = json.get_data().get("prompt_id", "")
	return {"ok": true, "data": {"prompt_id": prompt_id, "message": "Generation queued (~20-40s). Call check_image_status(prompt_id) to poll."}}


func check_image_status(args: Dictionary) -> Dictionary:
	var prompt_id: String = args.get("prompt_id", "")
	var res := _comfy_request(HTTPClient.METHOD_GET, "/history/" + prompt_id)
	if not res["ok"]: return res
	var json := JSON.new()
	if json.parse(res["raw"].get_string_from_utf8()) != OK:
		return {"ok": false, "data": "JSON parse error"}
	var history: Dictionary = json.get_data()
	if history.is_empty():
		return {"ok": true, "data": {"status": "processing"}}
	var item: Dictionary = history.get(prompt_id, {})
	var status_str: String = item.get("status", {}).get("status_str", "unknown")
	if status_str == "success":
		for _node in item.get("outputs", {}).values():
			if _node.has("images"):
				return {"ok": true, "data": {"status": "done", "filename": _node["images"][0]["filename"]}}
	elif status_str == "error":
		return {"ok": false, "data": "Generation failed in ComfyUI"}
	return {"ok": true, "data": {"status": "processing"}}


func import_image(args: Dictionary) -> Dictionary:
	var filename: String = args.get("filename", "")
	var frame_idx: int   = args.get("frame", 0)
	var layer_idx: int   = args.get("layer", 0)
	var project = _api.general.get_global().current_project
	if not project: return {"ok": false, "data": "No project open"}
	# Download PNG from ComfyUI
	var res := _comfy_request(HTTPClient.METHOD_GET, "/view?filename=%s&type=output" % filename)
	if not res["ok"]: return res
	var raw: PackedByteArray = res["raw"]
	if raw.size() < 100: return {"ok": false, "data": "Downloaded file too small"}
	# Save to temp
	var tmp_path := "/tmp/autorama_%s" % filename
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if not f: return {"ok": false, "data": "Cannot write temp file"}
	f.store_buffer(raw); f.close()
	# Load image
	var img := Image.new()
	if img.load(tmp_path) != OK:
		return {"ok": false, "data": "Failed to load PNG"}
	# Resize to canvas if needed
	var cw: int = project.size.x
	var ch: int = project.size.y
	if img.get_width() != cw or img.get_height() != ch:
		img.resize(cw, ch, Image.INTERPOLATE_NEAREST)
	# Import into cel
	frame_idx = clampi(frame_idx, 0, project.frames.size() - 1)
	layer_idx = clampi(layer_idx, 0, project.layers.size() - 1)
	_api.project.set_pixelcel_image(img, frame_idx, layer_idx)
	return {"ok": true, "data": {"imported": filename, "size": "%dx%d" % [cw, ch]}}


func execute(tool_name: String, args: Dictionary) -> Dictionary:
	match tool_name:
		"create_canvas":           return create_canvas(args)
		"get_project_info":        return get_project_info(args)
		"add_layer":               return add_layer(args)
		"add_frame":               return add_frame(args)
		"set_frame_duration":      return set_frame_duration(args)
		"draw_pixels":             return draw_pixels(args)
		"fill_area":               return fill_area(args)
		"get_pixels":              return get_pixels(args)
		"export_sprite":           return export_sprite(args)
		"queue_image_generation":  return queue_image_generation(args)
		"check_image_status":      return check_image_status(args)
		"import_image":            return import_image(args)
		_:
			return {"ok": false, "data": "Unknown command: %s" % tool_name}

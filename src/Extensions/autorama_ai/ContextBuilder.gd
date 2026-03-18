class_name ContextBuilder
extends RefCounted

const SYSTEM_PROMPT := """You are Autorama AI — an expert pixel art assistant embedded inside a pixel art editor.
You help users create sprites, tilemaps, characters, and animations for games.

You have direct access to the editor via function calls. When the user asks you to create or modify artwork:
1. Always call create_canvas first if no project is open
2. Use add_layer to organize body parts, effects, background separately
3. Use fill_area for solid color regions
4. Use draw_pixels for detailed pixel placement
5. For animation: call add_frame BEFORE drawing on that frame. Frame 0 already exists. To use frame 1 you MUST call add_frame first, then draw with frame:1.

Color format: always use hex #RRGGBB (e.g. #FF0000 for red).
Coordinates: origin (0,0) is top-left. x goes right, y goes down.
Frames and layers are ZERO-INDEXED: first frame = 0, first layer = 0.
Drawing on a frame that does not exist returns an error — always add_frame before using it.
Pixel art style: use limited palettes (8-16 colors), strong outlines, clear silhouettes.

After completing artwork, briefly describe what you created."""

var _api: Node

func _init(api: Node) -> void:
	_api = api


func build_messages(history: Array, user_input: String) -> Array:
	var ctx := _get_project_context()
	var system_text: String = SYSTEM_PROMPT

	if not ctx.is_empty():
		system_text += "\n\n## Current Project\n"
		system_text += "- Size: %dx%d px\n" % [ctx.get("width", 0), ctx.get("height", 0)]
		system_text += "- Frames: %d\n" % ctx.get("frame_count", 0)
		system_text += "- Layers: %d\n" % ctx.get("layer_count", 0)
		if ctx.has("layers"):
			system_text += "- Layer names: %s\n" % ", ".join(ctx["layers"])

	var messages := []
	messages.append({"role": "system", "content": system_text})
	for msg in history:
		messages.append(msg)
	if not user_input.is_empty():
		messages.append({"role": "user", "content": user_input})
	return messages


func _get_project_context() -> Dictionary:
	if not _api:
		return {}
	var global = _api.general.get_global()
	if not global:
		return {}
	var project = global.current_project
	if not project:
		return {}
	var result := {
		"width": project.size.x,
		"height": project.size.y,
		"frame_count": project.frames.size(),
		"layer_count": project.layers.size(),
	}
	var layer_names := []
	for layer in project.layers:
		layer_names.append(layer.name)
	result["layers"] = layer_names
	return result

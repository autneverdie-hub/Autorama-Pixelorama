class_name VLLMClient
extends RefCounted

const DEFAULT_HOST := "http://127.0.0.1:11434"
const DEFAULT_MODEL := "qwen3.5:397b-cloud"
const ENDPOINT := "/v1/chat/completions"

var host: String
var model: String
var _http: HTTPRequest

func _init(p_host := DEFAULT_HOST, p_model := DEFAULT_MODEL) -> void:
	host = p_host
	model = p_model

func setup(parent_node: Node) -> void:
	_http = HTTPRequest.new()
	parent_node.add_child(_http)


func get_tool_definitions() -> Array:
	return [
		_tool("create_canvas", "สร้าง sprite canvas ใหม่", {
			"width":  {"type": "integer"},
			"height": {"type": "integer"},
			"name":   {"type": "string"}
		}, ["width", "height"]),
		_tool("add_layer", "เพิ่ม layer ใหม่", {
			"name": {"type": "string"},
			"type": {"type": "integer", "description": "0=pixel"}
		}, []),
		_tool("add_frame", "เพิ่ม frame สำหรับ animation", {
			"after_frame": {"type": "integer"}
		}, []),
		_tool("set_frame_duration", "กำหนดความเร็ว animation", {
			"frame":    {"type": "integer"},
			"duration": {"type": "number"}
		}, ["frame", "duration"]),
		_tool("draw_pixels", "วาด pixels หลายจุด", {
			"pixels": {"type": "array", "description": "array ของ [x, y, '#RRGGBB']", "items": {"type": "array"}},
			"frame":  {"type": "integer"},
			"layer":  {"type": "integer"}
		}, ["pixels"]),
		_tool("fill_area", "fill สีในพื้นที่สี่เหลี่ยม", {
			"x":      {"type": "integer"},
			"y":      {"type": "integer"},
			"width":  {"type": "integer"},
			"height": {"type": "integer"},
			"color":  {"type": "string", "description": "hex เช่น #FF0000"},
			"frame":  {"type": "integer"},
			"layer":  {"type": "integer"}
		}, ["x", "y", "width", "height", "color"]),
		_tool("get_pixels", "อ่าน pixels ใน frame/layer", {
			"frame": {"type": "integer"},
			"layer": {"type": "integer"}
		}, []),
		_tool("get_project_info", "ดูข้อมูล project ปัจจุบัน", {}, []),
		_tool("export_sprite", "export sprite เป็น PNG", {
			"path": {"type": "string"}
		}, ["path"]),
	]


func chat(messages: Array, on_tool_calls: Callable, on_text: Callable) -> void:
	var body := JSON.stringify({
		"model": model,
		"messages": messages,
		"tools": get_tool_definitions(),
		"tool_choice": "auto",
		"max_tokens": 2048
	})
	print("[Autorama] Sending request, messages count: ", messages.size())
	var headers := ["Content-Type: application/json"]
	_http.request_completed.connect(_on_response.bind(on_tool_calls, on_text), CONNECT_ONE_SHOT)
	var err = _http.request(host + ENDPOINT, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		on_text.call("❌ HTTP Error: %d" % err)


func _on_response(result: int, status: int, _headers: PackedStringArray,
		body: PackedByteArray, on_tool_calls: Callable, on_text: Callable) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or status != 200:
		var err_body := body.get_string_from_utf8()
		print("[Autorama] ERROR %d: %s" % [status, err_body])
		on_text.call("❌ vLLM error: HTTP %d\n%s" % [status, err_body.left(300)])
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		on_text.call("❌ JSON parse error")
		return
	var data: Dictionary = json.get_data()
	var msg: Dictionary = data["choices"][0]["message"]
	var finish_reason: String = data["choices"][0]["finish_reason"]
	if finish_reason == "tool_calls" and msg.get("tool_calls"):
		var tool_calls := []
		for tc in msg["tool_calls"]:
			var args_json = JSON.new()
			args_json.parse(tc["function"]["arguments"])
			tool_calls.append({
				"id":   tc["id"],
				"name": tc["function"]["name"],
				"args": args_json.get_data()
			})
		on_tool_calls.call(tool_calls)
	else:
		on_text.call(msg.get("content", ""))


func _tool(name: String, desc: String, props: Dictionary, required: Array) -> Dictionary:
	return {
		"type": "function",
		"function": {
			"name": name,
			"description": desc,
			"parameters": {"type": "object", "properties": props, "required": required}
		}
	}

func build_tool_result(tool_id: String, result: Dictionary) -> Dictionary:
	return {
		"role": "tool",
		"tool_call_id": tool_id,
		"content": JSON.stringify(result)
	}

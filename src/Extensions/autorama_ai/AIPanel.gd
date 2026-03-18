extends Control

var _client
var _executor
var _context
var _history: Array = []

@onready var _chat_log: RichTextLabel = $VBox/ChatLog
@onready var _input: LineEdit = $VBox/InputRow/Input
@onready var _send_btn: Button = $VBox/InputRow/SendBtn
@onready var _status: Label = $VBox/Status
@onready var _clear_btn: Button = $VBox/TopRow/ClearBtn
@onready var _host_input: LineEdit = $VBox/TopRow/HostInput
@onready var _model_input: LineEdit = $VBox/TopRow/ModelInput


func _ready() -> void:
	var api := get_node_or_null("/root/ExtensionsApi")
	_executor = CommandExecutor.new(api)
	_context  = ContextBuilder.new(api)
	_client   = VLLMClient.new()
	_client.setup(self)

	_send_btn.pressed.connect(_on_send)
	_input.text_submitted.connect(func(_t): _on_send())
	_clear_btn.pressed.connect(_clear_history)
	_host_input.text_changed.connect(func(t): _client.host = t)
	_model_input.text_changed.connect(func(t): _client.model = t)

	_host_input.text = VLLMClient.DEFAULT_HOST
	_model_input.text = VLLMClient.DEFAULT_MODEL
	_set_status("Ready")
	_append_log("system", "Autorama AI ready. Describe what you want to create!")


func _on_send() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	_input.text = ""
	_input.editable = false
	_send_btn.disabled = true
	_append_log("user", text)
	_set_status("Thinking...")
	var messages = _context.build_messages(_history, text)
	_history.append({"role": "user", "content": text})
	_client.chat(messages, _on_tool_calls, _on_text_response)


func _clear_history() -> void:
	_history.clear()
	_chat_log.clear()
	_append_log("system", "History cleared.")


func _on_tool_calls(tool_calls: Array) -> void:
	_set_status("Executing %d command(s)..." % tool_calls.size())
	var tool_results := []
	for tc in tool_calls:
		_append_log("ai_action", "▶ %s(%s)" % [tc["name"], _format_args(tc["args"])])
		var result = _executor.execute(tc["name"], tc["args"])
		tool_results.append(_client.build_tool_result(tc["id"], result))
		if result["ok"]:
			_append_log("ai_result", "✅ %s" % JSON.stringify(result["data"]))
		else:
			_append_log("ai_result", "❌ %s" % result["data"])

	var assistant_msg := {
		"role": "assistant",
		"tool_calls": tool_calls.map(func(tc): return {
			"id": tc["id"],
			"type": "function",
			"function": {"name": tc["name"], "arguments": JSON.stringify(tc["args"])}
		})
	}
	_history.append(assistant_msg)
	for tr in tool_results:
		_history.append(tr)

	var messages = _context.build_messages([], "")
	messages.pop_back()
	for msg in _history:
		messages.append(msg)
	_set_status("Getting response...")
	_client.chat(messages, _on_tool_calls, _on_text_response)


func _on_text_response(text: String) -> void:
	_append_log("ai", text)
	_history.append({"role": "assistant", "content": text})
	_set_status("Ready")
	_input.editable = true
	_send_btn.disabled = false


func _append_log(role: String, text: String) -> void:
	var color := ""
	var prefix := ""
	match role:
		"user":      color = "#7EC8E3"; prefix = "You: "
		"ai":        color = "#B5EAD7"; prefix = "AI: "
		"ai_action": color = "#FFD700"; prefix = ""
		"ai_result": color = "#AAAAAA"; prefix = "  "
		"system":    color = "#888888"; prefix = "• "
	_chat_log.append_text("[color=%s]%s%s[/color]\n" % [color, prefix, text])
	_chat_log.scroll_to_line(_chat_log.get_line_count())


func _set_status(text: String) -> void:
	if _status:
		_status.text = text


func _format_args(args: Dictionary) -> String:
	var parts := []
	for k in args:
		var v = args[k]
		if v is Array and v.size() > 3:
			parts.append("%s:[%d items]" % [k, v.size()])
		else:
			parts.append("%s:%s" % [k, str(v)])
	return ", ".join(parts)

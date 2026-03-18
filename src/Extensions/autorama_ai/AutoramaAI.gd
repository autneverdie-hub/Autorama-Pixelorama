extends Node

var _api: Node
var _panel_instance: Control
var _menu_item_id: int = -1
var _api_server


func _ready() -> void:
	_api = get_node_or_null("/root/ExtensionsApi")
	if not _api:
		push_error("Autorama AI: ExtensionsApi not found")
		return

	var panel_scene := load("res://src/Extensions/autorama_ai/AIPanel.tscn")
	if not panel_scene:
		push_error("Autorama AI: AIPanel.tscn not found")
		return

	_panel_instance = panel_scene.instantiate()
	_panel_instance.name = "Autorama AI"
	_api.panel.add_node_as_tab(_panel_instance)

	_menu_item_id = _api.menu.add_menu_item(
		_api.menu.HELP,
		"Autorama AI Panel",
		_toggle_panel
	)
	# Start HTTP API server for MCP bridge
	var executor = CommandExecutor.new(_api)
	_api_server = APIServer.new()
	_api_server.name = "APIServer"
	_api_server.setup(executor)
	add_child(_api_server)
	_api_server.start()

	print("Autorama AI loaded ✅")


func _toggle_panel() -> void:
	if _panel_instance:
		_panel_instance.visible = not _panel_instance.visible


func _exit_tree() -> void:
	if _api and _menu_item_id >= 0:
		_api.menu.remove_menu_item(_api.menu.HELP, _menu_item_id)
	if _panel_instance and is_instance_valid(_panel_instance):
		_api.panel.remove_node_from_tab(_panel_instance)
		_panel_instance.queue_free()
	if _api_server and is_instance_valid(_api_server):
		_api_server.stop()
		_api_server.queue_free()

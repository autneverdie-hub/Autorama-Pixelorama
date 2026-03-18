class_name APIServer
extends Node

const PORT := 7777
const MAX_READ_FRAMES := 300  # ~5s at 60fps

var _server := TCPServer.new()
var _executor  # CommandExecutor
var _peer: StreamPeerTCP = null
var _buf: String = ""
var _wait_frames: int = 0


func setup(executor) -> void:
	_executor = executor


func start() -> bool:
	var err := _server.listen(PORT)
	if err != OK:
		push_error("[APIServer] Failed to listen on port %d (err %d)" % [PORT, err])
		return false
	print("[APIServer] Listening on http://127.0.0.1:%d" % PORT)
	return true


func stop() -> void:
	if _peer:
		_peer.disconnect_from_host()
		_peer = null
	_server.stop()


func _process(_delta: float) -> void:
	if _peer == null and _server.is_connection_available():
		_peer = _server.take_connection()
		_buf = ""
		_wait_frames = 0

	if _peer == null:
		return

	var status := _peer.get_status()
	if status == StreamPeerTCP.STATUS_NONE or status == StreamPeerTCP.STATUS_ERROR:
		_peer = null
		_buf = ""
		return

	# Accumulate bytes
	var available := _peer.get_available_bytes()
	if available > 0:
		var read_result := _peer.get_data(available)
		if read_result[0] == OK:
			_buf += (read_result[1] as PackedByteArray).get_string_from_utf8()
		_wait_frames = 0
	else:
		_wait_frames += 1
		if _wait_frames > MAX_READ_FRAMES:
			_send_error(_peer, 408, "Request Timeout")
			_peer.disconnect_from_host()
			_peer = null
			_buf = ""
			return

	var header_end := _buf.find("\r\n\r\n")
	if header_end == -1:
		return

	var headers_section := _buf.left(header_end)
	var body_start := header_end + 4

	# Parse Content-Length
	var content_length := 0
	for line in headers_section.split("\r\n"):
		if line.to_lower().begins_with("content-length:"):
			content_length = line.split(":")[1].strip_edges().to_int()
			break

	# Handle OPTIONS preflight
	if headers_section.split("\r\n")[0].begins_with("OPTIONS"):
		_send_cors_preflight(_peer)
		_peer.disconnect_from_host()
		_peer = null
		_buf = ""
		return

	# Wait for full body
	if _buf.length() - body_start < content_length:
		return

	var body_str := _buf.substr(body_start, content_length)

	var json := JSON.new()
	if json.parse(body_str) != OK:
		_send_error(_peer, 400, "Invalid JSON")
		_peer.disconnect_from_host()
		_peer = null
		_buf = ""
		return

	var payload: Dictionary = json.get_data()
	var tool_name: String = payload.get("tool", "")
	var args: Dictionary = payload.get("args", {})

	var result: Dictionary
	if _executor:
		result = _executor.execute(tool_name, args)
	else:
		result = {"ok": false, "data": "Executor not initialized"}

	_send_json(_peer, result)
	_peer.disconnect_from_host()
	_peer = null
	_buf = ""


func _send_json(peer: StreamPeerTCP, data: Dictionary) -> void:
	var body := JSON.stringify(data)
	var body_bytes := body.to_utf8_buffer()
	var response := (
		"HTTP/1.1 200 OK\r\n"
		+ "Content-Type: application/json\r\n"
		+ "Content-Length: %d\r\n" % body_bytes.size()
		+ "Access-Control-Allow-Origin: *\r\n"
		+ "Connection: close\r\n"
		+ "\r\n"
	)
	peer.put_data(response.to_utf8_buffer())
	peer.put_data(body_bytes)


func _send_error(peer: StreamPeerTCP, code: int, message: String) -> void:
	var body := JSON.stringify({"ok": false, "data": message})
	var body_bytes := body.to_utf8_buffer()
	var status_text := "Bad Request" if code == 400 else "Timeout"
	var response := (
		"HTTP/1.1 %d %s\r\n" % [code, status_text]
		+ "Content-Type: application/json\r\n"
		+ "Content-Length: %d\r\n" % body_bytes.size()
		+ "Connection: close\r\n"
		+ "\r\n"
	)
	peer.put_data(response.to_utf8_buffer())
	peer.put_data(body_bytes)


func _send_cors_preflight(peer: StreamPeerTCP) -> void:
	var response := (
		"HTTP/1.1 204 No Content\r\n"
		+ "Access-Control-Allow-Origin: *\r\n"
		+ "Access-Control-Allow-Methods: POST, OPTIONS\r\n"
		+ "Access-Control-Allow-Headers: Content-Type\r\n"
		+ "Connection: close\r\n"
		+ "\r\n"
	)
	peer.put_data(response.to_utf8_buffer())

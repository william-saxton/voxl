class_name S3Client
extends Node
## Minimal async S3 HTTP client for unauthenticated MinIO access.
## Uses Godot's HTTPRequest nodes for non-blocking operations.
## Each request carries its own callback, so concurrent requests never collide.

signal request_failed(error: String)

const MAX_CONCURRENT := 3

var endpoint: String = ""  ## e.g. "http://192.168.1.50:9000"

var _active_count: int = 0
var _queue: Array[Dictionary] = []


# ---------------------------------------------------------------------------
# Public API — each method takes an optional per-request callback Callable.
# The callback receives a single Dictionary argument with the result.
# ---------------------------------------------------------------------------

## List objects in a bucket. Result:
##   { "objects": [{ "key": String, "etag": String, "size": int, "last_modified": String }] }
func list_objects(bucket: String, callback: Callable = Callable(),
		prefix: String = "") -> void:
	var path := "/%s?list-type=2" % bucket
	if not prefix.is_empty():
		path += "&prefix=%s" % prefix.uri_encode()
	_enqueue("GET", path, PackedByteArray(), "", "_on_list_objects", "", callback)


## Download an object. Result:
##   { "key": String, "etag": String, "body": PackedByteArray }
func get_object(bucket: String, key: String,
		callback: Callable = Callable()) -> void:
	var path := "/%s/%s" % [bucket, key]
	_enqueue("GET", path, PackedByteArray(), key, "_on_get_object", "", callback)


## Upload an object. Result:
##   { "key": String, "etag": String }
func put_object(bucket: String, key: String, data: PackedByteArray,
		content_type: String = "application/octet-stream",
		callback: Callable = Callable()) -> void:
	var path := "/%s/%s" % [bucket, key]
	_enqueue("PUT", path, data, key, "_on_put_object", content_type, callback)


## Check if an object exists and get its ETag. Result:
##   { "key": String, "etag": String, "size": int }
func head_object(bucket: String, key: String,
		callback: Callable = Callable()) -> void:
	var path := "/%s/%s" % [bucket, key]
	_enqueue("HEAD", path, PackedByteArray(), key, "_on_head_object", "", callback)


## Delete an object. Result:
##   { "key": String, "deleted": true }
func delete_object(bucket: String, key: String,
		callback: Callable = Callable()) -> void:
	var path := "/%s/%s" % [bucket, key]
	_enqueue("DELETE", path, PackedByteArray(), key, "_on_delete_object", "", callback)


## Simple connectivity check. Result:
##   { "reachable": bool }
func check_health(callback: Callable = Callable()) -> void:
	_enqueue("GET", "/minio/health/live", PackedByteArray(), "", "_on_health_check", "", callback)


# ---------------------------------------------------------------------------
# Request queue
# ---------------------------------------------------------------------------

func _enqueue(method: String, path: String, body: PackedByteArray,
		context_key: String, handler: String, content_type: String,
		callback: Callable) -> void:
	var entry := {
		"method": method,
		"path": path,
		"body": body,
		"context_key": context_key,
		"handler": handler,
		"content_type": content_type,
		"callback": callback,
	}
	if _active_count < MAX_CONCURRENT:
		_dispatch(entry)
	else:
		_queue.append(entry)


func _dispatch(entry: Dictionary) -> void:
	_active_count += 1
	var http := HTTPRequest.new()
	http.use_threads = true
	add_child(http)

	var url: String = endpoint.rstrip("/") + str(entry["path"])

	var headers: PackedStringArray = []
	if not (entry["content_type"] as String).is_empty():
		headers.append("Content-Type: %s" % entry["content_type"])

	var method: int
	match entry["method"]:
		"GET":    method = HTTPClient.METHOD_GET
		"PUT":    method = HTTPClient.METHOD_PUT
		"HEAD":   method = HTTPClient.METHOD_HEAD
		"DELETE": method = HTTPClient.METHOD_DELETE
		_:        method = HTTPClient.METHOD_GET

	http.request_completed.connect(
		_on_http_done.bind(http, entry["handler"], entry["context_key"], entry["callback"])
	)

	var body_str := ""
	if not (entry["body"] as PackedByteArray).is_empty():
		body_str = (entry["body"] as PackedByteArray).get_string_from_utf8()

	var err := http.request(url, headers, method, body_str)
	if err != OK:
		_active_count -= 1
		http.queue_free()
		request_failed.emit("HTTP request failed with error %d for %s" % [err, url])
		_flush_queue()


func _on_http_done(result: int, response_code: int, headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest, handler: String,
		context_key: String, callback: Callable) -> void:
	http.queue_free()
	_active_count -= 1

	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("HTTP result %d (response %d) for %s" % [result, response_code, context_key])
		_flush_queue()
		return

	if response_code >= 400:
		var err_body := body.get_string_from_utf8()
		request_failed.emit("HTTP %d for %s: %s" % [response_code, context_key, err_body.left(256)])
		_flush_queue()
		return

	# Extract ETag from response headers
	var etag := ""
	for h in headers:
		if h.to_lower().begins_with("etag:"):
			etag = h.substr(h.find(":") + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
			break

	# Build result via the handler, then deliver to callback
	var parsed: Dictionary = call(handler, response_code, headers, body, context_key, etag)
	if callback.is_valid():
		callback.call(parsed)
	_flush_queue()


func _flush_queue() -> void:
	while _active_count < MAX_CONCURRENT and not _queue.is_empty():
		_dispatch(_queue.pop_front())


# ---------------------------------------------------------------------------
# Response handlers — each returns a Dictionary (no longer emits signals)
# ---------------------------------------------------------------------------

func _on_list_objects(_code: int, _headers: PackedStringArray,
		body: PackedByteArray, _key: String, _etag: String) -> Dictionary:
	var xml_str := body.get_string_from_utf8()
	var objects := _parse_list_objects_xml(xml_str)
	return { "objects": objects }


func _on_get_object(_code: int, _headers: PackedStringArray,
		body: PackedByteArray, key: String, etag: String) -> Dictionary:
	return { "key": key, "etag": etag, "body": body }


func _on_put_object(_code: int, _headers: PackedStringArray,
		_body: PackedByteArray, key: String, etag: String) -> Dictionary:
	return { "key": key, "etag": etag }


func _on_head_object(_code: int, headers: PackedStringArray,
		_body: PackedByteArray, key: String, etag: String) -> Dictionary:
	var size := 0
	for h in headers:
		if h.to_lower().begins_with("content-length:"):
			size = h.substr(h.find(":") + 1).strip_edges().to_int()
			break
	return { "key": key, "etag": etag, "size": size }


func _on_delete_object(_code: int, _headers: PackedStringArray,
		_body: PackedByteArray, key: String, _etag: String) -> Dictionary:
	return { "key": key, "deleted": true }


func _on_health_check(code: int, _headers: PackedStringArray,
		_body: PackedByteArray, _key: String, _etag: String) -> Dictionary:
	return { "reachable": code == 200 }


# ---------------------------------------------------------------------------
# XML parsing for ListObjectsV2
# ---------------------------------------------------------------------------

func _parse_list_objects_xml(xml_str: String) -> Array[Dictionary]:
	var objects: Array[Dictionary] = []
	var parser := XMLParser.new()
	var err := parser.open_buffer(xml_str.to_utf8_buffer())
	if err != OK:
		return objects

	var current_object: Dictionary = {}
	var current_tag := ""
	var in_contents := false

	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				current_tag = parser.get_node_name()
				if current_tag == "Contents":
					in_contents = true
					current_object = { "key": "", "etag": "", "size": 0, "last_modified": "" }
			XMLParser.NODE_TEXT:
				if in_contents:
					var text := parser.get_node_data().strip_edges()
					match current_tag:
						"Key":
							current_object["key"] = text
						"ETag":
							current_object["etag"] = text.trim_prefix("\"").trim_suffix("\"")
						"Size":
							current_object["size"] = text.to_int()
						"LastModified":
							current_object["last_modified"] = text
			XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name() == "Contents":
					in_contents = false
					objects.append(current_object)
				current_tag = ""

	return objects

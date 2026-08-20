extends Node
## Net — listen-server multiplayer (Godot High-Level Multiplayer API + ENet).
##
## Architecture (MVP):
##  * Host is authoritative: clients send *requests*, host validates and
##    applies, then broadcasts deltas (never the whole world, except on join).
##  * Listen server: host == player. Dedicated server: run the same project
##    headless with the `--server` flag (Main skips player/UI and auto-hosts).
##
## Bandwidth: block/furniture changes are single-cell deltas; player state is
## 10 Hz unreliable_ordered. [C#-CANDIDATE] snapshot/delta compression later.

signal hosted
signal joined
signal disconnected_from_host
signal peer_joined(id: int)
signal peer_left(id: int)
signal world_synced(data: Dictionary)
signal furniture_place(data: Dictionary)
signal furniture_remove(inst_id: int)
signal remote_state(id: int, pos: Vector3, rot: float, skin: String, moving: bool)
signal remote_skin(id: int, skin: String)

const PORT := 7000
const MAX_CLIENTS := 8

var is_host := false
var is_client := false
## True while applying a host/remote authoritative edit (sync or broadcast).
## Game uses this to avoid mis-attributing remote builds to the local player.
var applying_remote := false
## Peer id whose request is currently being applied by the host (0 = none).
var remote_actor_id := 0

func is_offline() -> bool:
	return not is_host and not is_client

func is_hosting() -> bool:
	return is_host

func is_client_side() -> bool:
	return is_client

func get_my_id() -> int:
	return multiplayer.get_unique_id()

func host_game() -> bool:
	if is_host:
		return true
	var peer := ENetMultiplayerPeer.new()
	# Owner-tunable cap (ServerConfig online.max_players), defaults to MAX_CLIENTS.
	var cap := MAX_CLIENTS
	if ServerConfig != null:
		cap = ServerConfig.max_players()
	var err := peer.create_server(PORT, cap)
	if err != OK:
		push_error("Net: cannot host on port %d: %s" % [PORT, error_string(err)])
		return false
	_connect_peer(peer)
	is_host = true
	is_client = false
	emit_signal("hosted")
	return true

func join_game(ip: String) -> bool:
	if not is_offline():
		return false
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		push_error("Net: cannot join %s:%d — %s" % [ip, PORT, error_string(err)])
		return false
	multiplayer.connected_to_server.connect(_on_connected_to_server, true)
	multiplayer.connection_failed.connect(_on_connection_failed, true)
	_connect_peer(peer)
	return true

func _connect_peer(peer: ENetMultiplayerPeer) -> void:
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func _on_connected_to_server() -> void:
	is_client = true
	is_host = false
	emit_signal("joined")
	request_world_sync.rpc_id(1)

func _on_connection_failed() -> void:
	_cleanup()
	emit_signal("disconnected_from_host")

func _on_peer_connected(id: int) -> void:
	if is_host:
		# Late joiner: push the world state to this peer.
		var data := _world_sync_data()
		send_world_sync.rpc_id(id, data)
	emit_signal("peer_joined", id)

func _on_peer_disconnected(id: int) -> void:
	if is_client and id == 1:
		_cleanup()
		emit_signal("disconnected_from_host")
		return
	emit_signal("peer_left", id)

func _cleanup() -> void:
	is_host = false
	is_client = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer = null

func _world_sync_data() -> Dictionary:
	var furn: Node = get_tree().get_first_node_in_group("furniture_system")
	return {
		"seed": World.seed,
		"placed": World.get_placed_list(),
		"broken": World.get_broken_list(),
		"furniture": furn.get_data() if furn != null else [],
	}

# --- world sync -------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func request_world_sync() -> void:
	if not is_host:
		return
	var sender := multiplayer.get_remote_sender_id()
	send_world_sync.rpc_id(sender, _world_sync_data())

@rpc("any_peer", "call_remote", "reliable")
func send_world_sync(data: Dictionary) -> void:
	emit_signal("world_synced", data)

# --- block changes (host authoritative) --------------------------------------

## Called by the HOST after it applied a local edit: broadcasts to all others.
func broadcast_block_change(pos: Vector3i, mat: int) -> void:
	if not is_host:
		return
	apply_block_change.rpc(pos, mat)

@rpc("any_peer", "call_remote", "reliable")
func request_block_change(pos: Vector3i, mat: int) -> void:
	if not is_host:
		return
	# Attribute this edit to the requesting peer (land claim / maturity).
	remote_actor_id = multiplayer.get_remote_sender_id()
	if World.set_block(pos, mat):
		broadcast_block_change(pos, mat)
	remote_actor_id = 0

@rpc("any_peer", "call_remote", "reliable")
func apply_block_change(pos: Vector3i, mat: int) -> void:
	applying_remote = true
	World.set_block(pos, mat)  # clients recompute structural state locally
	applying_remote = false

# --- furniture ----------------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func request_furniture_place(data: Dictionary) -> void:
	if not is_host:
		return
	rpc_furniture_place.rpc(data)

@rpc("any_peer", "call_remote", "reliable")
func request_furniture_remove(inst_id: int) -> void:
	if not is_host:
		return
	rpc_furniture_remove.rpc(inst_id)

@rpc("any_peer", "call_local", "reliable")
func rpc_furniture_place(data: Dictionary) -> void:
	emit_signal("furniture_place", data)

@rpc("any_peer", "call_local", "reliable")
func rpc_furniture_remove(inst_id: int) -> void:
	emit_signal("furniture_remove", inst_id)

# --- player state / skins ------------------------------------------------------

@rpc("any_peer", "call_local", "unreliable_ordered")
func player_state(id: int, pos: Vector3, rot: float, skin: String, moving: bool) -> void:
	emit_signal("remote_state", id, pos, rot, skin, moving)

@rpc("any_peer", "call_local", "reliable")
func skin_sync(skin: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = get_my_id()
	emit_signal("remote_skin", id, skin)

func broadcast_skin(skin: String) -> void:
	skin_sync.rpc(skin)

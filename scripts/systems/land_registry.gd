class_name LandRegistry
extends Node
## LandRegistry — land claims + abandonment/inheritance (Sections 1.3, 1.4).
##
## Tracks who claims which regions and when each player was last active.
## A long-absent player's land becomes "adoptable": another player can adopt
## it (transferring ownership, keeping the existing structures) instead of the
## land rotting forever. Symbolic building (emblems placed on someone else's
## land) notifies the owner via a signal.

signal land_claimed(player: String, region: Vector2i)
signal land_adopted(from: String, to: String, region: Vector2i)
signal owner_notified(owner: String, text: String)

## Seconds of inactivity before a player's land becomes adoptable.
var abandon_after := 60 * 60 * 24 * 7.0  # 7 days (tunable by the server owner)

## player -> { last_seen: float, regions: {Vector2i: true} }
var players: Dictionary = {}

const REGION := 8  # blocks per claim region side

func _region_key(p: Vector3) -> Vector2i:
	return Vector2i(int(p.x) / REGION, int(p.z) / REGION)

func touch(player: String) -> void:
	_ensure(player)
	players[player]["last_seen"] = Time.get_ticks_msec() / 1000.0

func _ensure(player: String) -> void:
	if not players.has(player):
		players[player] = {"last_seen": Time.get_ticks_msec() / 1000.0, "regions": {}}

## Claim a region (auto-claimed when a player builds there).
func claim(player: String, region: Vector2i) -> void:
	_ensure(player)
	if not players[player]["regions"].has(region):
		players[player]["regions"][region] = true
		emit_signal("land_claimed", player, region)

## Claim the region containing a world position (used when a player builds).
func claim_at(player: String, pos: Vector3) -> void:
	claim(player, _region_key(pos))

func owner_of_region(region: Vector2i) -> String:
	for p in players:
		if players[p]["regions"].get(region, false) == true:
			return p
	return ""

func owner_at(pos: Vector3) -> String:
	return owner_of_region(_region_key(pos))

func is_abandoned(player: String) -> bool:
	if not players.has(player):
		return false
	var last: float = players[player]["last_seen"]
	return (Time.get_ticks_msec() / 1000.0) - last > abandon_after

## Adopt all of `from_player`'s regions into `to_player` (inheritance).
## Only possible if `from_player` is abandoned. Returns # regions transferred.
func adopt(from_player: String, to_player: String) -> int:
	if not is_abandoned(from_player):
		return 0
	_ensure(to_player)
	var count := 0
	var regions: Array = players[from_player]["regions"].keys()
	for region in regions:
		players[to_player]["regions"][region] = true
		players[from_player]["regions"].erase(region)
		count += 1
		emit_signal("land_adopted", from_player, to_player, region)
	return count

## Notify a land owner (e.g. an emblem was placed on their land).
func notify_owner(owner: String, text: String) -> void:
	if owner != "":
		emit_signal("owner_notified", owner, text)

## Place a symbolic emblem on someone's land -> notify the owner (Section 1.4).
func place_emblem(by_player: String, pos: Vector3, emblem: String) -> void:
	touch(by_player)
	var owner := owner_at(pos)
	if owner != "" and owner != by_player:
		notify_owner(owner, "%s placed a %s on your land" % [by_player, emblem])

# --- persistence -----------------------------------------------------------------

func get_data() -> Dictionary:
	var players_out: Dictionary = {}
	for p in players:
		var regions_out: Array = []
		for r in players[p]["regions"]:
			regions_out.append([r.x, r.y])
		players_out[p] = {"last_seen": players[p]["last_seen"], "regions": regions_out}
	return {"players": players_out}

func load_data(data: Dictionary) -> void:
	players.clear()
	var p_in: Dictionary = data.get("players", {})
	for p in p_in:
		var regions: Dictionary = {}
		for r in p_in[p].get("regions", []):
			regions[Vector2i(int(r[0]), int(r[1]))] = true
		players[p] = {"last_seen": float(p_in[p].get("last_seen", 0.0)), "regions": regions}

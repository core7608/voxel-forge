class_name City
extends Resource
## City — a player-declared settlement with identity, government, roles and a
## captured castle (Section 3.2). Managed by the CityManager singleton, which
## talks to the rest of the game via signals (not direct coupling).

@export var name: String = "New Town"
## Flag: up to 3 horizontal colour bands + a symbol id from the flag library.
@export var flag_colors: Array = [Color(0.8, 0.2, 0.2), Color(0.9, 0.9, 0.9)]
@export var flag_symbol: String = "star"
## Social identity theme (affects flavour / future bonuses).
@export var theme: String = "mixed"  # "commercial" | "military" | "agricultural" | "mixed"
## Government form.
@export var government: String = "monarchy"  # "monarchy" | "council" | "democracy"
@export var founder: String = ""
## Council members (used by "council" government).
@export var council: Array = []
## Residents = players with a land claim inside the city (used by "democracy").
@export var residents: Array = []
## Roles: player_name -> role id.
@export var roles: Dictionary = {}
## City economics.
@export var treasury: int = 0
@export_range(0.0, 1.0) var tax_rate: float = 0.1
@export var max_building_height: int = 20
@export var open_city: bool = true  # accepts new residents without approval
## Index of the captured castle structure (-1 = none).
@export var castle_index: int = -1
## World centre of the city (flag pole location).
@export var center: Vector3 = Vector3.ZERO

func add_resident(name: String) -> void:
	if not residents.has(name):
		residents.append(name)

func remove_resident(name: String) -> void:
	residents.erase(name)

func role_of(name: String) -> String:
	return str(roles.get(name, "citizen"))

func set_role(name: String, role: String) -> void:
	roles[name] = role

## Who votes, by government form.
func voters() -> Array:
	match government:
		"monarchy":
			return [founder] if founder != "" else []
		"council":
			return council.duplicate()
		"democracy":
			return residents.duplicate()
		_:
			return [founder] if founder != "" else []

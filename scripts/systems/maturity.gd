class_name Maturity
extends Node
## Maturity — cumulative world-maturity indicators (Section 1.6).
##
## There is no "victory screen". Instead the world shows cumulative maturity:
## how many permanent settlers, the age of the oldest building, and how many
## governments have formed. A living-sandbox continuation signal, not an end.

signal maturity_updated()

var first_build_time: float = -1.0  # seconds; -1 = nothing built yet
var settlers: Dictionary = {}       # player_name -> first build time
var governments_formed := 0

func record_build(player: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if first_build_time < 0.0:
		first_build_time = now
	if not settlers.has(player):
		settlers[player] = now

func record_government() -> void:
	governments_formed += 1
	emit_signal("maturity_updated")

## Age of the oldest building in seconds (0 if none).
func oldest_build_age(now: float = -1.0) -> float:
	if first_build_time < 0.0:
		return 0.0
	if now < 0.0:
		now = Time.get_ticks_msec() / 1000.0
	return maxf(0.0, now - first_build_time)

func permanent_settlers() -> int:
	return settlers.size()

## A short human-readable maturity summary.
func summary() -> String:
	if first_build_time < 0.0:
		return "This land is still wild."
	var days := oldest_build_age() / 86400.0
	return "Settled %.1f days ago · %d settlers · %d governments" % [
		days, permanent_settlers(), governments_formed]

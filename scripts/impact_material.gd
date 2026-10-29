class_name ImpactMaterial
extends Resource

enum Kind { CERAMIC, GLASS, WOOD, PLASTIC, METAL, ELECTRONIC }

@export var kind: Kind = Kind.WOOD
@export var brittle: bool = false
# Joule-like gameplay thresholds, not an attempt to model real fracture energy.
@export_range(0.1, 2000.0) var damage_threshold: float = 120.0
@export_range(0.1, 2000.0) var break_threshold: float = 240.0
@export_range(0.0, 5.0) var minimum_closing_speed: float = 1.0
# One-time fragment response; durable staged props still do not spawn debris.
@export_range(0.0, 4.0) var fragment_scatter_speed: float = 1.8
@export_range(0.0, 7.0) var fragment_scatter_spin: float = 3.5
@export_range(0.0, 0.3) var fragment_bounce: float = 0.1


static func severity(own_mass: float, other_mass: float, closing_speed: float) -> float:
	# Zero other mass denotes an immovable collider. Ignore tangential sliding.
	var effective_mass := own_mass
	if other_mass > 0.0:
		effective_mass = own_mass * other_mass / (own_mass + other_mass)
	return 0.5 * effective_mass * pow(maxf(closing_speed, 0.0), 2.0)

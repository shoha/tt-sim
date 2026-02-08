extends Node

## Global constants shared across the project.
## Registered as an autoload so values are accessible everywhere.

# =============================================================================
# LO-FI SHADER DEFAULTS
# =============================================================================
# Default parameters for the lo-fi post-processing shader.
# Used by GameMap and the LevelEditor lighting preview.

const LOFI_DEFAULTS := {
	"pixelation": 0.003,
	"saturation": 0.85,
	"color_tint": Color(1.02, 1.0, 0.96),
	"vignette_strength": 0.3,
	"vignette_radius": 0.8,
	"grain_intensity": 0.025,
	"grain_speed": 0.2,
	"grain_scale": 0.12,
	"color_levels": 32.0,
	"dither_strength": 0.5,
}

# =============================================================================
# NETWORK
# =============================================================================

## How often token transforms are sent over the network during manipulation (seconds).
const NETWORK_TRANSFORM_UPDATE_INTERVAL: float = 0.1

extends Node

## Global constants shared across the project.
## Registered as an autoload so values are accessible everywhere.

# =============================================================================
# CANVAS LAYER ORDERING
# =============================================================================
# Centralized CanvasLayer numbers. Higher layers render on top and receive
# input first. Use these constants when creating CanvasLayers in code.
# .tscn files must use literal numbers — keep them in sync with this table.
#
# When adding a new layer:
#   1. Pick a number that reflects its priority relative to existing layers
#   2. Add it here with a comment describing the scene region it occupies
#   3. Check for position overlaps with other layers (see screen regions below)
#
# Screen regions occupied:
#   Left edge:     LAYER_GAMEPLAY_MENU (PlayerListDrawer — networked games only)
#   Bottom-left:   LAYER_GAMEPLAY_MENU (MapScalePanel)
#   Bottom-right:  LAYER_GAMEPLAY_MENU (BottomButtons), LAYER_APP_MENU (BottomButtons)
#   Bottom-center: LAYER_INPUT_HINTS, LAYER_TOAST, LAYER_DIALOG (download queue)
#   Centered:      LAYER_SETTINGS, LAYER_DIALOG (modals)
#   Full-screen:   LAYER_LOADING, LAYER_TRANSITION (transient)

const LAYER_WORLD_VIEWPORT := -1  ## 3D scene rendering (SubViewportContainer)
const LAYER_APP_MENU := 2  ## Always-visible app chrome (Level Editor button) — bottom-right
const LAYER_GAMEPLAY_MENU := 2  ## In-game UI (tokens, save, scale slider) — bottom-left & bottom-right
const LAYER_LOBBY := 5  ## Host/client lobby (centered, full-screen backdrop)
const LAYER_PAUSE := 10  ## Pause overlay (centered, full-screen backdrop)
const LAYER_INPUT_HINTS := 80  ## Contextual keyboard hints — bottom-center
const LAYER_TOAST := 90  ## Toast notifications — bottom-center
const LAYER_SETTINGS := 95  ## Settings menu (centered, full-screen backdrop)
const LAYER_DIALOG := 100  ## Modals: confirmation, update, add-pack; download queue — bottom-center
const LAYER_LOADING := 105  ## Loading screen (full-screen, hidden when idle)
const LAYER_TRANSITION := 110  ## Scene transition fade (full-screen, hidden when idle)

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
# UI ANIMATION
# =============================================================================
# Standard durations used across all UI fade/slide animations.
# "In" is slightly slower than "out" so openings feel deliberate and
# closings feel snappy.

const ANIM_FADE_IN_DURATION: float = 0.2
const ANIM_FADE_OUT_DURATION: float = 0.15

# =============================================================================
# UI COLORS (mirrors theme values for programmatic use)
# =============================================================================

const COLOR_WARNING := Color("#ffd25f")  # ProgrammaticTheme.color_warning
const COLOR_TOAST_BG := Color(0.17, 0.12, 0.17, 0.95)  # ~color_surface1 at 95% alpha

# =============================================================================
# ASSET LOADING
# =============================================================================

## Default download/resolve priority (lower = higher priority).
const ASSET_PRIORITY_DEFAULT: int = 100

## Higher priority for visible/important assets.
const ASSET_PRIORITY_HIGH: int = 50

# =============================================================================
# NETWORK
# =============================================================================

## How often token transforms are sent over the network during manipulation (seconds).
const NETWORK_TRANSFORM_UPDATE_INTERVAL: float = 0.1

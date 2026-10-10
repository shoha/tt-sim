class_name ThemeColors
extends RefCounted

## The one colour role table (docs/UI_TASTE.md C1), Painted Table tokens. Two layers:
##
## - Tokens are the raw palette below (PAPER, INK, PERSIMMON, GLASS, CHALK, EMBER ...),
##   sizes and ratios from the 2026-10-09 theme recommendation. Only the theme scripts and
##   3D tints read tokens directly.
## - Roles are what UI code asks for: TEXT, TEXT_SOFT, ACCENT, STATE ... Each theme leaf
##   maps every role to its own token (PAPER_ROLES for anything that stops play,
##   GLASS_ROLES for anything shown while play continues) and writes the map into the
##   theme as colour items of theme type TYPE. Code reads a role through the control it
##   colours, `ThemeColors.of(control, ThemeColors.TEXT_SOFT)`, and so gets ink_soft under
##   paper and chalk_soft under glass. Prefer a theme variation (Caption, BodyState,
##   Primary ...) over reading a role; read a role only to draw or tint by hand.
##
## A control outside the tree resolves against the project theme (paper), so code that
## colours by hand reads its role when drawing or on NOTIFICATION_THEME_CHANGED, never in
## _init.
##
## themes/painted_theme_base.gd reads this file when the ProgrammaticTheme addon regenerates
## the themes, so moving or renaming it breaks theme regeneration quietly: the committed
## .tres files simply stop updating.

## The theme type both leaves carry the role colours on.
const TYPE := &"ThemeColors"

const PAPER_THEME_PATH := "res://themes/generated/paper_theme.tres"
const GLASS_THEME_PATH := "res://themes/generated/glass_theme.tres"

# -- Paper tokens (menus, dialogs, pause, confirms) --
const PAPER := Color("#FAF3E3")
const PAPER_RAISED := Color("#FFFBF2")
const PAPER_INSET := Color("#F0E5CC")
## Between paper and paper_inset: a raised control's hover, which only deepens (C6).
const PAPER_HOVER := Color("#F5ECD7")
## Decorative pencil borders only (1.78:1 on paper); it never carries meaning.
const PAPER_EDGE := Color("#CDB68C")
## The pencil edge pressed harder: an unfilled slider or switch track, 3:1 on every paper
## surface it sits on (C6), where the edge itself would vanish.
const PAPER_TRACK := Color("#978160")
const INK := Color("#2B2335")
const INK_SOFT := Color("#5C5066")
const PERSIMMON := Color("#B4452A")
const PERSIMMON_HOVER := Color("#BC4426")
const PERSIMMON_PRESS := Color("#983621")
const LAKE := Color("#2A6880")
const LAKE_HOVER := Color("#2E7089")
const LAKE_PRESS := Color("#22566B")
## Fills only the confirming button of a danger dialog.
const MADDER := Color("#A12F3A")
## Success text and icons; never a fill.
const MOSS := Color("#46723A")
## The warning chip.
const OCHRE := Color("#E0A23A")

# -- Glass tokens (HUD, drawers, hints, context menu, toasts) --
const GLASS := Color("#1E1A28", 0.86)
const GLASS_RAISED := Color("#332C40", 0.92)
## The top rim and dividers on glass.
const GLASS_RIM := Color("#FAF3E3", 0.14)
const CHALK := Color("#FAF3E3")
const CHALK_SOFT := Color("#CFC5D6")
## An unfilled track on glass: 3:1 on glass over a white or a black board.
const GLASS_TRACK := Color("#958DA0")
## The glass primary fill (ink text on it) and inline action.
const EMBER := Color("#F08C5C")
## Ember deepened at the same hue: ink on these stays above 4.5:1 (5.5 and 4.6).
const EMBER_HOVER := Color("#E8814F")
const EMBER_PRESS := Color("#D9733F")
const LAKE_LIGHT := Color("#7CC6DD")
const LAKE_LIGHT_HOVER := Color("#6DBAD2")
const LAKE_LIGHT_PRESS := Color("#5CA9C2")
const MOSS_LIGHT := Color("#A6D58A")
const MADDER_LIGHT := Color("#FF928C")
const OCHRE_LIGHT := Color("#F5C766")

# -- Shared --
## The morning sky (backdrop wash) until painted backdrops land.
const SKY_TOP := Color("#A8D2E8")
const SKY_LOW := Color("#F4DDB4")
## The stop-play scrim (C4), used with blur.
const SCRIM := Color("#2B2140", 0.30)
## Shadows are ink-tinted: the warm brown of the first recommendation read as a beige lip
## over the sky.
const SHADOW_REST := Color("#2B2335", 0.16)
const SHADOW_LIFTED := Color("#2B2335", 0.22)
## Under glass: a plum near-black rather than pure black (C4).
const SHADOW_GLASS := Color("#0E0B14", 0.25)

# -- Role names --
const SURFACE := &"surface"
const SURFACE_RAISED := &"surface_raised"
const SURFACE_INSET := &"surface_inset"
## Hover and press wash a raised control deeper, never lighter (C6), on paper and on glass.
const SURFACE_HOVER := &"surface_hover"
const SURFACE_PRESS := &"surface_press"
const EDGE := &"edge"
## An unfilled slider or switch track: unlike EDGE it carries meaning, so it holds 3:1.
const TRACK := &"track"
const TEXT := &"text"
const TEXT_SOFT := &"text_soft"
## Warm means do: the primary action's fill and the unsaved dot. Never focus (FOCUS).
const ACCENT := &"accent"
const ACCENT_HOVER := &"accent_hover"
const ACCENT_PRESS := &"accent_press"
const ON_ACCENT := &"on_accent"
## Cool means is: on-states, the rail indicator, a value changed from default, and on glass
## the text and lines of state (the selected ring). Small glyphs (checks, switches) fill
## with it; a large selected surface fills with SELECTED instead.
const STATE := &"state"
const STATE_HOVER := &"state_hover"
const STATE_PRESS := &"state_press"
const ON_STATE := &"on_state"
## A selected tile or list row. Lake on both leaves: on glass lake_light as a fill outshone
## the board (a 0.49 luminance tile over a board peaking at 0.40), so glass fills deep lake
## with chalk text and draws its STATE ring around it.
const SELECTED := &"selected"
const SELECTED_HOVER := &"selected_hover"
const ON_SELECTED := &"on_selected"
const SUCCESS := &"success"
## The warning chip's fill (ink text on it); on glass it also reads as text.
const WARNING := &"warning"
## Destructive text and icons; DANGER_FILL is the danger-confirm button only.
const DANGER := &"danger"
const DANGER_FILL := &"danger_fill"
const ON_DANGER := &"on_danger"
## The keyboard focus ring. Focus is a state, so it is lake (about 6:1 on paper) or
## lake_light on glass, never a control's fill hue: a persimmon ring read as a validation
## error and as a second primary.
const FOCUS := &"focus"
const SHADOW := &"shadow"
## A solid backdrop that replaces the table rather than dims it (the lobbies).
const BACKDROP := &"backdrop"

const PAPER_ROLES := {
	SURFACE: PAPER,
	SURFACE_RAISED: PAPER_RAISED,
	SURFACE_INSET: PAPER_INSET,
	SURFACE_HOVER: PAPER_HOVER,
	SURFACE_PRESS: PAPER_INSET,
	EDGE: PAPER_EDGE,
	TRACK: PAPER_TRACK,
	TEXT: INK,
	TEXT_SOFT: INK_SOFT,
	ACCENT: PERSIMMON,
	ACCENT_HOVER: PERSIMMON_HOVER,
	ACCENT_PRESS: PERSIMMON_PRESS,
	ON_ACCENT: PAPER,
	STATE: LAKE,
	STATE_HOVER: LAKE_HOVER,
	STATE_PRESS: LAKE_PRESS,
	ON_STATE: PAPER,
	SELECTED: LAKE,
	SELECTED_HOVER: LAKE_HOVER,
	ON_SELECTED: PAPER,
	SUCCESS: MOSS,
	WARNING: OCHRE,
	DANGER: MADDER,
	DANGER_FILL: MADDER,
	ON_DANGER: PAPER,
	FOCUS: LAKE,
	SHADOW: SHADOW_REST,
	BACKDROP: SKY_TOP,
}

const GLASS_ROLES := {
	SURFACE: GLASS,
	SURFACE_RAISED: GLASS_RAISED,
	SURFACE_INSET: GLASS_RAISED,
	SURFACE_HOVER: Color("#2A2436", 0.94),
	SURFACE_PRESS: Color("#211C2C", 0.96),
	EDGE: GLASS_RIM,
	TRACK: GLASS_TRACK,
	TEXT: CHALK,
	TEXT_SOFT: CHALK_SOFT,
	ACCENT: EMBER,
	ACCENT_HOVER: EMBER_HOVER,
	ACCENT_PRESS: EMBER_PRESS,
	ON_ACCENT: INK,
	STATE: LAKE_LIGHT,
	STATE_HOVER: LAKE_LIGHT_HOVER,
	STATE_PRESS: LAKE_LIGHT_PRESS,
	ON_STATE: INK,
	SELECTED: LAKE,
	SELECTED_HOVER: LAKE_HOVER,
	ON_SELECTED: CHALK,
	SUCCESS: MOSS_LIGHT,
	WARNING: OCHRE_LIGHT,
	DANGER: MADDER_LIGHT,
	DANGER_FILL: MADDER,
	ON_DANGER: CHALK,
	FOCUS: LAKE_LIGHT,
	SHADOW: SHADOW_GLASS,
	BACKDROP: Color("#1E1A28"),
}


## The colour `role` (one of the role names above) resolves to for `control`: the glass
## token under a glass root, the paper token elsewhere.
static func of(control: Control, role: StringName) -> Color:
	assert(PAPER_ROLES.has(role), "ThemeColors: unknown role %s" % role)
	return control.get_theme_color(role, TYPE)


## The theme every UI root shown while play continues sets on itself (UI_TASTE.md C8).
static func glass_theme() -> Theme:
	return load(GLASS_THEME_PATH) as Theme


## The project default theme, for anything that stops play.
static func paper_theme() -> Theme:
	return load(PAPER_THEME_PATH) as Theme

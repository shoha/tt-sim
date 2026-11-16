class_name SettingsSpec
extends RefCounted

## The Settings menu's information architecture as data: which tab each row sits in, under which
## group heading, and the one plain sentence under it. SettingsLayout reads this when the menu
## opens and builds the groups around the rows settings_menu.tscn declares.
##
## To add a row (a card that brings a new setting):
## 1. Declare the row in settings_menu.tscn as the existing rows are: an HBoxContainer with a
##    Label first and the control after it (a unique name on the control, the one the code reads).
##    It can sit anywhere under its tab's Content.
## 2. Add `{"row": "<the row's node name>", "desc": "<one plain sentence>"}` to the group that
##    fits, below. A row can name `"desc_node"` instead of `"desc"` to adopt an existing Label as
##    its sentence (text the code updates), and `"derived": true` when its control only shows
##    other rows' values (the Quality preset), so a group reset leaves it to refresh itself.
##    `"attach": true` puts a row the code shows and hides (the Quality note) flush under the row
##    above it, in that row's block.
## 3. Read and write the control in SettingsMenu._write_values / _show_saved_values, and give it a
##    default in _show_defaults: the per-group Reset and the unsaved-changes mark read those.
## A row the table does not list is still shown: SettingsLayout.adopt_strays puts it in a "More"
## group at the end of its tab, so a missed line never loses a setting.
##
## A group's "reset" is on by default (a Reset button on its heading puts its rows back to their
## defaults); "blurb" is a line under the heading; "foldout" names an existing Foldout the group's
## rows stay inside (Graphics' Advanced), which then stands as the group.

## Tab order and icons live in SettingsMenu.SECTIONS; each tab here lists its groups in order.
const TABS := {
	"Audio":
	[
		{
			"title": "Volume",
			"rows":
			[
				{
					"row": "MasterVolume",
					"desc": "How loud everything is. The sliders below sit under this one.",
				},
				{"row": "MusicVolume", "desc": "Background music."},
				{
					"row": "SFXVolume",
					"desc": "Tokens being picked up, moved and dropped, and the table itself.",
				},
				{"row": "UIVolume", "desc": "Clicks, ticks and the sounds menus make as they open."},
			],
		},
	],
	"Graphics":
	[
		{
			"title": "Look and quality",
			"rows":
			[
				{
					"row": "Quality",
					"derived": true,
					"desc":
					"One choice for shadows, ambient occlusion and render scale, picked for your graphics card.",
				},
				{"row": "QualityNoteRow", "attach": true},
				{
					"row": "Look",
					"desc": "How the board is lit and coloured on your screen. Other players keep their own.",
				},
				{
					"row": "TokenShading",
					"desc": "Painted matches tokens to the board; Original keeps each model's own shading.",
				},
				{"row": "LofiFilter", "desc": "A soft, low-resolution pixel look over the 3D view."},
			],
		},
		{
			"title": "Display",
			"rows":
			[
				{"row": "Fullscreen", "desc": "Fill the whole screen. F11 switches it at any time."},
				{
					"row": "VSync",
					"desc": "Match your screen's refresh rate so it never tears. Off has the least delay.",
				},
				{
					"row": "RenderScale",
					"desc": "How many pixels the board draws. Lower is faster on a slow card; menus stay sharp.",
				},
			],
		},
		{
			"title": "View and camera",
			"rows":
			[
				{
					"row": "TokenGhost",
					"desc": "Show a see-through outline of a token hidden behind trees, rocks or walls.",
				},
				{
					"row": "TokenPins",
					"desc": "Always keeps a pin over every token; Top-down only shows it from a high view.",
				},
				{
					"row": "EyeSmoothing",
					"desc": "Smooth edges when walking the table at eye level. Turn off if that runs slowly.",
				},
			],
		},
		{
			"title": "Effects",
			"rows":
			[
				{
					"row": "ShadowQuality",
					"desc": "How soft shadow edges are. Higher looks smoother and costs more.",
				},
				{
					"row": "ShadowCascades",
					"desc": "How the sun's shadows are split by distance. Blended is smoothest, Single fastest.",
				},
				{
					"row": "Antialiasing",
					"desc": "Smooths jagged edges on foliage. x4 is smoothest and uses more graphics memory.",
				},
				{
					"row": "FoliageEdges",
					"desc": "Smooth feathers leaf and grass edges; Fast keeps them crisp and draws faster.",
				},
			],
		},
		{
			"title": "Water",
			"rows":
			[
				{
					"row": "WaterQuality",
					"desc": "Ripple detail and see-through refraction in water. Lower is faster.",
				},
			],
		},
		{
			"title": "Performance",
			"rows":
			[
				{
					"row": "GroundDetail",
					"desc": "How much of the ground is drawn once and reused. Fewer levels use less memory.",
				},
				{
					"row": "IdleThrottle",
					"desc": "Slow the game while its window is in the background, to save power and heat.",
				},
			],
		},
		{
			"title": "Advanced",
			"foldout": "Advanced",
			"rows":
			[
				{
					"row": "SSAO",
					"desc": "Soft shading in corners and crevices. Uses more of the graphics card.",
				},
				{
					"row": "SSR",
					"desc": "Nearby things reflect in shiny surfaces such as water. Uses more graphics power.",
				},
				{
					"row": "SDFGI",
					"desc": "Light bounces between surfaces for richer lighting. Uses much more graphics power.",
				},
				{
					"row": "RendererMethod",
					"desc": "Which graphics backend runs the game. Default suits most; a change needs a restart.",
				},
			],
		},
	],
	"Accessibility":
	[
		{
			"title": "Size and text",
			"rows":
			[
				{
					"row": "InterfaceSize",
					"desc":
					"How large menus and text are. Auto keeps text readable on this screen. Changes at once.",
				},
			],
		},
		{
			"title": "Motion",
			"rows":
			[
				{
					"row": "ReduceMotion",
					"desc":
					"Menus fade instead of sliding. Follows your system's setting too. Changes at once.",
				},
				{
					"row": "WindMotion",
					"desc": "How much plants, cloth and weather sway in the wind. At 0 everything holds still.",
				},
			],
		},
	],
	"Grid":
	[
		{
			"title": "Grid overlay",
			"blurb": "How the grid draws over the map.",
			"rows":
			[
				{
					"row": "CellTintOpacity",
					"desc": "How strongly each cell is shaded. At 0 only the lines show.",
				},
				{"row": "LineThickness", "desc": "How heavy the grid lines are."},
				{
					"row": "FadeDistance",
					"desc": "How far from the middle of the view the grid reaches before it fades.",
				},
			],
		},
	],
	"Controls":
	[
		{
			"title": "Input",
			"rows":
			[
				{
					"row": "InputDevice",
					"desc": "Which key names the hints show. Auto follows the device you used last.",
				},
			],
		},
		{"title": "Shortcuts", "reset": false, "rows": [{"row": "ControlsList"}]},
	],
	"Network":
	[
		{
			"title": "Asset sharing",
			"rows":
			[
				{
					"row": "P2PEnabled",
					"desc": "When a map needs an asset with no download link, fetch it straight from the host.",
				},
			],
		},
		{
			"title": "Storage",
			"reset": false,
			"rows": [{"row": "ClearCache", "desc_node": "CacheInfo"}],
		},
	],
	"Updates":
	[
		{
			"title": "This version",
			"reset": false,
			"rows": [{"row": "VersionInfo"}],
		},
		{
			"title": "Updates",
			"rows":
			[
				{
					"row": "Prereleases",
					"desc": "Test builds arrive early and may be unstable. Leave off unless you want to try them.",
				},
				{"row": "CheckUpdates", "desc_node": "UpdateStatus"},
			],
		},
	],
	"About":
	[
		{
			"title": "Version and credits",
			"reset": false,
			"rows":
			[
				{"row": "AboutVersion"},
				{"row": "AboutCopyright", "note": true},
				{"row": "Licences", "desc_node": "LicencesInfo"},
				{"row": "CoreCredit", "note": true},
			],
		},
	],
}

## Controls whose change saves and applies at once (not by Apply): Interface size, Reduce motion,
## the prerelease channel and the input device. Their defaults are not part of _show_defaults.
const LIVE_DEFAULTS := {
	"InterfaceSizeOption": InterfaceSize.AUTO,
	"ReduceMotionCheck": false,
	"PrereleasesCheck": false,
	"InputDeviceOption": 0,
}

## Controls whose change does not touch the board until Apply: a window mode, a renderer, a
## resize or a shader reload is not something to flick through live.
const APPLY_ONLY := [
	"FullscreenCheck",
	"VSyncCheck",
	"RenderScaleOption",
	"AntialiasingOption",
	"FoliageEdgesOption",
	"ShadowCascadesOption",
	"GroundDetailOption",
	"IdleThrottleCheck",
	"EyeSmoothingCheck",
	"LookOption",
	"RendererMethodOption",
	"P2PEnabledCheck",
]

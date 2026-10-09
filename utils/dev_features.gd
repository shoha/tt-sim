class_name DevFeatures
## Features still in development: on in a run of the editor binary (the Godot editor, and
## the CLI test and render-job runs, which use the same binary), off in exported builds,
## so testers never see them. Tests flip a flag to check the off state.

## Player avatars: the title screen's Avatars button, the asset browser's Avatar tab and
## Edit Avatar on a token's menu. Held back from releases until the look is ready for
## testers (user, 2026-10-08). Saved levels and synced games carrying avatar tokens still
## load and draw them.
static var avatars: bool = OS.has_feature("editor")

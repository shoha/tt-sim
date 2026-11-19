class_name SunShadowQuality
extends RefCounted

## The sun's soft-shadow filter tier (RenderingServer.directional_soft_shadow_filter_set_quality,
## Settings > Graphics > Shadow quality), set only when it changes. Every caller in the game goes
## through set_quality(); a test fails on a direct call anywhere else.
##
## Why. In Godot 4.7 the engine's setter re-specializes every 3D shader even when the tier is the
## one already set: RendererSceneRenderRD::directional_soft_shadow_filter_set_quality calls
## _update_shader_quality_settings() unconditionally, and that clears the pipelines of every 3D
## shader (PipelineHashMapRD::clear_pipelines) on the calling thread. Each map load re-applied the
## saved tier (DebugRenderToggles.refresh), so it threw away the pipelines PainterWarmup had just
## compiled for the new world and raced its worker threads: clear_pipelines waits on the shader's
## pending compile tasks without taking their ids out of its table, so a warm-up worker's
## mesh_create_from_surfaces then waited on a task the pool had already released, "Invalid Task
## ID" (worker_thread_pool.cpp:408) at painter_warmup.gd's _work (or, the other way round, at the
## refresh). Card painter-errors-fix, docs/systems/painter.md "Warm-up".

const SETTING := "rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"

## The tier last set through set_quality(); -1 until the first call, when it is the project
## setting's (the engine reads it at startup).
static var _current := -1


## Sets the sun's soft-shadow tier to [param quality] (a RenderingServer.ShadowQuality) unless it
## is already that. Returns whether it called the engine.
static func set_quality(quality: int) -> bool:
	if quality == current():
		return false
	_current = quality
	RenderingServer.directional_soft_shadow_filter_set_quality(quality)
	return true


## The tier in force: the last one set_quality() set, else the project setting's.
static func current() -> int:
	if _current < 0:
		_current = int(ProjectSettings.get_setting(SETTING, RenderingServer.SHADOW_QUALITY_SOFT_LOW))
	return _current


## Forgets the last tier, so current() reads the project setting again (the test-state reset).
static func reset() -> void:
	_current = -1

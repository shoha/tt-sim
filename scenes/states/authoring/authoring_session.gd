class_name AuthoringSession
extends RefCounted

## Unsaved-change tracking for one authoring session, as revision counters rather than a
## flag: every edit bumps `revision`, a save records the revision it wrote, and so does an
## autosave. Dirty is "the revision on disk is not the current one", which a later undo
## back to the saved state does not fake (an undo is an edit too). Pure.

signal dirty_changed(dirty: bool)

var revision: int = 0
var saved_revision: int = 0
var autosaved_revision: int = 0


## A session over a document that has never been saved (a new map): dirty from the start.
static func unsaved() -> AuthoringSession:
	var session := AuthoringSession.new()
	session.revision = 1
	return session


## Records one edit (a brush stroke, a rename, an undo).
func mark_edited() -> void:
	var was_dirty := is_dirty()
	revision += 1
	if not was_dirty:
		dirty_changed.emit(true)


## The current revision is on disk (a manual save); the autosave is superseded too.
func mark_saved() -> void:
	var was_dirty := is_dirty()
	saved_revision = revision
	autosaved_revision = revision
	if was_dirty:
		dirty_changed.emit(false)


func mark_autosaved() -> void:
	autosaved_revision = revision


func is_dirty() -> bool:
	return revision != saved_revision


## True when there are unsaved edits the autosave does not hold yet.
func needs_autosave() -> bool:
	return is_dirty() and autosaved_revision != revision

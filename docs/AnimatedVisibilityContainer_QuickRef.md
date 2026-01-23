# Animated Visibility Container - Quick Reference

## Basic Pattern
```gdscript
extends AnimatedVisibilityContainer

func show_ui():
    animate_in()

func hide_ui():
    animate_out()
```

## With Button Toggle
```gdscript
extends AnimatedVisibilityContainer

func _on_button_toggled(is_on: bool):
    toggle_animated(is_on)
```

## With Cleanup
```gdscript
extends AnimatedVisibilityContainer

func _on_before_animate_out():
    # Clear inputs, reset state, etc.
    $InputField.clear()
```

## Custom Animation via Inspector
Just add an `AnimatedVisibilityContainer` node and tweak:
- Fade duration
- Scale values
- Easing/transition types

## Custom Animation via Code
```gdscript
extends AnimatedVisibilityContainer

func _ready():
    fade_in_duration = 0.5
    scale_in_from = Vector2(0.5, 0.5)
    trans_in_type = Tween.TRANS_ELASTIC
    super._ready()
```

That's it! See `AnimatedVisibilityContainer.md` for full documentation.

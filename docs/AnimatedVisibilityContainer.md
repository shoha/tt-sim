# Animated Visibility Container System

A reusable base class for adding smooth show/hide animations to UI elements in Godot.

## Quick Start

### Basic Usage

1. **Extend the base class** in your UI script:
```gdscript
extends AnimatedVisibilityContainer

func _on_button_pressed():
    toggle_animated(true)  # Show with animation
```

2. **Or customize via exports** in the Godot Inspector:
- `fade_in_duration` - How long the fade-in takes (default: 0.3s)
- `fade_out_duration` - How long the fade-out takes (default: 0.2s)
- `scale_in_from` - Starting scale when appearing (default: Vector2(0.8, 0.8))
- `scale_out_to` - Ending scale when disappearing (default: Vector2(0.9, 0.9))
- `ease_in_type` - Easing function for appearing (default: EASE_OUT)
- `ease_out_type` - Easing function for disappearing (default: EASE_IN)
- `trans_in_type` - Transition type for appearing (default: TRANS_BACK)
- `trans_out_type` - Transition type for disappearing (default: TRANS_CUBIC)
- `start_hidden` - Whether to start invisible (default: true)

## API Reference

### Methods

#### `animate_in() -> void`
Smoothly shows the container with animation.

#### `animate_out() -> void`
Smoothly hides the container with animation.

#### `toggle_animated(show_container: bool) -> void`
Shows or hides based on the boolean parameter.

#### `is_animating() -> bool`
Returns true if an animation is currently playing.

### Override Callbacks

Override these in your child class for custom behavior:

#### `_on_ready() -> void`
Called after base class initialization.

#### `_on_before_animate_in() -> void`
Called just before the fade-in animation starts.

#### `_on_after_animate_in() -> void`
Called when the fade-in animation completes.

#### `_on_before_animate_out() -> void`
Called just before the fade-out animation starts. Great for cleanup!

#### `_on_after_animate_out() -> void`
Called when the fade-out animation completes.

## Examples

### Example 1: Simple Dialog Box
```gdscript
extends AnimatedVisibilityContainer

func show_dialog(message: String):
    $Label.text = message
    animate_in()

func _on_close_button_pressed():
    animate_out()
```

### Example 2: Custom Animation Settings
```gdscript
extends AnimatedVisibilityContainer

func _ready():
    # Customize animation in code
    fade_in_duration = 0.5
    scale_in_from = Vector2(0.5, 0.5)
    trans_in_type = Tween.TRANS_ELASTIC
    super._ready()  # Don't forget to call parent!
```

### Example 3: Menu with Cleanup
```gdscript
extends AnimatedVisibilityContainer

func _on_before_animate_out():
    # Clear form fields before hiding
    $NameInput.clear()
    $DescriptionInput.clear()
    
func _on_after_animate_in():
    # Focus first input after showing
    $NameInput.grab_focus()
```

### Example 4: Slide-in Panel (Customize in Inspector)
In your scene, add an AnimatedVisibilityContainer and set:
- `scale_in_from`: (1.0, 0.0) - slides from bottom
- `trans_in_type`: TRANS_CUBIC
- `fade_in_duration`: 0.4

### Example 5: Popup Notification
```gdscript
extends AnimatedVisibilityContainer

func show_notification(text: String, duration: float = 2.0):
    $Label.text = text
    animate_in()
    await get_tree().create_timer(duration).timeout
    animate_out()
```

## Animation Presets

Here are some suggested preset combinations:

### Bouncy Popup (default)
- `trans_in_type`: TRANS_BACK
- `scale_in_from`: (0.8, 0.8)
- Good for: Dialogs, popups

### Smooth Fade
- `trans_in_type`: TRANS_CUBIC
- `scale_in_from`: (1.0, 1.0)
- Good for: Overlays, tooltips

### Slide Up
- `trans_in_type`: TRANS_CUBIC
- `scale_in_from`: (1.0, 0.0)
- Good for: Bottom sheets, mobile-style panels

### Elastic Bounce
- `trans_in_type`: TRANS_ELASTIC
- `scale_in_from`: (0.5, 0.5)
- Good for: Achievements, notifications

### Quick Pop
- `trans_in_type`: TRANS_SPRING
- `fade_in_duration`: 0.2
- Good for: Context menus, quick actions

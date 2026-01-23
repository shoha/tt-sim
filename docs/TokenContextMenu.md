# Token Context Menu System

A right-click context menu system for board tokens that provides quick access to common token actions.

## Features

- **Health Management**: Deal damage or heal tokens with quick buttons or custom amounts
- **Visibility Toggle**: Show/hide tokens from players
- **Smooth Animations**: Uses the AnimatedVisibilityContainer system for polished appearance
- **Real-time Updates**: Health display updates as you make changes
- **Click-outside to Close**: Automatically closes when clicking outside the menu
- **Smart Positioning**: Automatically adjusts position to stay within viewport bounds

## Usage

### For Players/GMs

1. **Right-click** any token on the board to open the context menu
2. Use the quick action buttons:
   - `-1`, `-5`, `-10`, `-20` to deal preset damage amounts
   - Custom damage field for specific amounts
   - `+5`, `+10` for healing
   - `Full` to restore to max health
3. Click **Toggle Visibility** to show/hide the token
4. Click **Close** or click outside to dismiss the menu

### Visual Feedback

- **Hidden tokens** appear semi-transparent (50% opacity, desaturated)
- **Visible tokens** appear at full brightness
- Health updates are reflected immediately in the menu

## Implementation

### Architecture

```
GameMap (manages context menu instance)
  └── TokenContextMenu (UI overlay)
        ↓ (signals)
  BoardToken (receives actions)
    └── TokenController (detects right-click)
```

### Key Components

#### 1. TokenContextMenu (`token_context_menu.gd`)
The UI component that displays the menu and emits action signals.

**Signals:**
- `damage_requested(amount: int)` - When damage should be dealt
- `heal_requested(amount: int)` - When healing should be applied
- `visibility_toggled()` - When visibility should change
- `menu_closed()` - When menu is closed

**Methods:**
- `open_for_token(token: BoardToken, at_position: Vector2)` - Open menu for a specific token
- `close_menu()` - Close the menu with animation
- `_position_menu_in_viewport(cursor_position: Vector2)` - Smart positioning to avoid viewport edges

#### 2. TokenController (`token_controller.gd`)
Detects right-click input and requests menu.

**New Signal:**
- `context_menu_requested(token: BoardToken, position: Vector2)`

#### 3. BoardToken (`board_token.gd`)
Handles the actual game logic for actions.

**Updated Methods:**
- `toggle_visibility()` - Now includes visual feedback
- `_update_visibility_visuals()` - Applies transparency to hidden tokens

#### 4. GameMap (`game_map.gd`)
Coordinates between tokens and the context menu.

**New Methods:**
- `_setup_context_menu()` - Creates menu instance
- `_on_token_context_menu_requested()` - Opens menu at position
- `_on_context_menu_damage_requested()` - Applies damage
- `_on_context_menu_heal_requested()` - Applies healing
- `_on_context_menu_visibility_toggled()` - Toggles visibility

## Customization

### Adding New Actions

To add a new action to the context menu:

1. **Add UI element** to `token_context_menu.tscn`
2. **Create signal** in `token_context_menu.gd`:
```gdscript
signal new_action_requested(param: Type)
```

3. **Add handler** in `token_context_menu.gd`:
```gdscript
func _on_new_action_button_pressed():
    new_action_requested.emit(some_value)
```

4. **Connect in GameMap** `_setup_context_menu()`:
```gdscript
_context_menu.new_action_requested.connect(_on_context_menu_new_action)
```

5. **Implement logic** in `GameMap` or `BoardToken`:
```gdscript
func _on_context_menu_new_action(param):
    if _context_menu and _context_menu.target_token:
        _context_menu.target_token.do_new_action(param)
```

### Customizing Quick Damage Amounts

Edit the `quick_damage_amounts` export in `TokenContextMenu`:

```gdscript
@export var quick_damage_amounts: Array[int] = [1, 5, 10, 20, 50]
```

Or modify the buttons directly in `token_context_menu.tscn`.

### Changing Menu Appearance

The context menu extends `AnimatedVisibilityContainer`, so you can customize:
- Animation duration
- Scale effects
- Easing functions

Modify in `_ready()` of `token_context_menu.gd`:
```gdscript
func _ready():
    fade_in_duration = 0.2
    scale_in_from = Vector2(0.95, 0.95)
    super._ready()
```

## Example: Adding Status Effects

Here's how you'd add a "Burn" status effect action:

1. Add button to menu:
```gdscript
# In token_context_menu.tscn VBoxContainer
[node name="ApplyBurnButton" type="Button" parent="MenuPanel/VBoxContainer"]
text = "Apply Burn"
```

2. Add signal and handler:
```gdscript
# In token_context_menu.gd
signal status_effect_requested(effect: String)

func _on_apply_burn_pressed():
    status_effect_requested.emit("Burn")
```

3. Wire it up in GameMap:
```gdscript
func _setup_context_menu():
    # ... existing code ...
    _context_menu.status_effect_requested.connect(_on_status_effect_requested)

func _on_status_effect_requested(effect: String):
    if _context_menu and _context_menu.target_token:
        _context_menu.target_token.add_status_effect(effect)
```

## Technical Notes

- The context menu is positioned at the mouse cursor position with smart viewport-aware adjustment
- **Smart Positioning Algorithm**:
  1. Initially positions menu with 10px offset from cursor (bottom-right)
  2. If menu would extend beyond right edge → flips to left of cursor
  3. If menu would extend beyond bottom edge → flips to above cursor
  4. Clamps position to ensure menu never goes offscreen (left/top edges)
  5. This ensures all controls remain accessible regardless of cursor position
- Uses `_unhandled_input` to detect clicks outside the menu
- Properly integrated with the AnimatedVisibilityContainer base class
- All state changes emit appropriate signals for future extensions (like networking)

## Future Enhancements

Possible additions:
- Status effect management UI
- Token notes/description
- Initiative tracking
- Condition markers
- Rotation presets
- Scale presets
- Token duplication
- Delete token option

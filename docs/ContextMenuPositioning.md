# Context Menu Positioning - Technical Details

## Smart Positioning Algorithm

The context menu uses a multi-step algorithm to ensure it always stays within viewport bounds.

### Step-by-Step Process

```
1. Cursor Position Detected
   └─► Right-click at position (X, Y)

2. Initial Positioning
   └─► Target = Cursor + Offset (10, 10)
       Default: Bottom-right of cursor

3. Boundary Checks
   ├─► Check Right Edge
   │   If (Target.X + MenuWidth) > ViewportWidth
   │   └─► Flip: Target.X = Cursor.X - MenuWidth - 10
   │
   ├─► Check Bottom Edge
   │   If (Target.Y + MenuHeight) > ViewportHeight
   │   └─► Flip: Target.Y = Cursor.Y - MenuHeight - 10
   │
   ├─► Check Left Edge
   │   If Target.X < 0
   │   └─► Clamp: Target.X = 0
   │
   └─► Check Top Edge
       If Target.Y < 0
       └─► Clamp: Target.Y = 0

4. Final Position
   └─► Menu placed at adjusted Target position
```

## Visual Examples

### Example 1: Normal Position (Middle of Screen)
```
┌─────────────────────────────────────┐
│ Viewport                            │
│                                     │
│            ✕ Cursor                 │
│            ┌─────────┐              │
│            │ Menu    │              │
│            │ - Dmg   │              │
│            │ - Heal  │              │
│            └─────────┘              │
│                                     │
└─────────────────────────────────────┘

Position: Cursor + (10, 10)
Result: Default bottom-right placement
```

### Example 2: Near Right Edge
```
┌─────────────────────────────────────┐
│ Viewport                            │
│                                     │
│                         ✕ Cursor    │
│                ┌─────────┐          │
│                │ Menu    │          │
│                │ - Dmg   │          │
│                │ - Heal  │          │
│                └─────────┘          │
│                                     │
└─────────────────────────────────────┘

Detected: Would extend past right edge
Adjusted: Flipped to left of cursor
Result: Cursor - (MenuWidth + 10, -10)
```

### Example 3: Near Bottom Edge
```
┌─────────────────────────────────────┐
│ Viewport                            │
│                                     │
│                                     │
│                                     │
│                                     │
│                                     │
│            ┌─────────┐              │
│            │ Menu    │              │
│            │ - Dmg   │              │
│            │ - Heal  │              │
│            └─────────┘              │
│            ✕ Cursor                 │
└─────────────────────────────────────┘

Detected: Would extend past bottom edge
Adjusted: Flipped to above cursor
Result: Cursor - (-10, MenuHeight + 10)
```

### Example 4: Bottom-Right Corner
```
┌─────────────────────────────────────┐
│ Viewport                            │
│                                     │
│                                     │
│                                     │
│                                     │
│                                     │
│                ┌─────────┐          │
│                │ Menu    │          │
│                │ - Dmg   │          │
│                │ - Heal  │          │
│                └─────────┘          │
│                         ✕ Cursor    │
└─────────────────────────────────────┘

Detected: Would extend past both edges
Adjusted: Flipped both left AND up
Result: Cursor - (MenuWidth + 10, MenuHeight + 10)
```

### Example 5: Extreme Corner (Clamping)
```
┌─────────────────────────────────────┐
│✕Cursor                              │
│┌─────────┐                          │
││ Menu    │                          │
││ - Dmg   │                          │
││ - Heal  │                          │
│└─────────┘                          │
│                                     │
│                                     │
│                                     │
└─────────────────────────────────────┘

Detected: Flipping would place menu offscreen
Adjusted: Clamped to (0, 0)
Result: Top-left corner of viewport
```

## Code Implementation

```gdscript
func _position_menu_in_viewport(cursor_position: Vector2) -> void:
    var menu_panel = get_node_or_null("MenuPanel")
    if not menu_panel:
        global_position = cursor_position
        return
    
    # Get viewport size
    var viewport_size = get_viewport().get_visible_rect().size
    var menu_size = menu_panel.size
    
    # Add small offset from cursor to avoid blocking it
    var offset = Vector2(10, 10)
    var target_position = cursor_position + offset
    
    # Check if menu would go off the right edge
    if target_position.x + menu_size.x > viewport_size.x:
        # Position to the left of cursor instead
        target_position.x = cursor_position.x - menu_size.x - offset.x
    
    # Check if menu would go off the bottom edge
    if target_position.y + menu_size.y > viewport_size.y:
        # Position above cursor instead
        target_position.y = cursor_position.y - menu_size.y - offset.y
    
    # Ensure menu doesn't go off the left edge
    if target_position.x < 0:
        target_position.x = 0
    
    # Ensure menu doesn't go off the top edge
    if target_position.y < 0:
        target_position.y = 0
    
    global_position = target_position
```

## Key Design Decisions

### 1. Offset from Cursor
- **10px offset** prevents menu from obscuring cursor
- Allows user to still see what they clicked on
- Small enough to feel connected to the cursor

### 2. Flip Priority
- **Right edge** checked first (most common in LTR interfaces)
- **Bottom edge** checked second
- Both can flip independently

### 3. Clamping as Safety Net
- Prevents edge case where flipping still results in offscreen menu
- Ensures menu is always fully visible
- Only used when flipping isn't sufficient

### 4. Await Process Frame
- `await get_tree().process_frame` ensures menu size is calculated
- Prevents positioning based on stale or zero size
- Critical for accurate boundary detection

## Performance Considerations

- **Single-frame delay**: Menu appears one frame after right-click
  - Negligible (16ms @ 60fps)
  - Necessary for accurate size calculation
  - User won't notice due to animation timing

- **Calculation cost**: Very low
  - Simple arithmetic comparisons
  - No complex collision detection
  - Runs once per menu open

## Edge Cases Handled

1. ✅ **Very small viewport**: Menu clamped to (0, 0)
2. ✅ **Menu larger than viewport**: Still attempts best fit
3. ✅ **Cursor at exact corner**: Properly flips and clamps
4. ✅ **Rapid menu opening**: Each instance calculates independently
5. ✅ **Resized viewport**: Uses current viewport size each time

## Future Enhancements

Potential improvements:
- [ ] Preferred positioning direction setting
- [ ] Custom offset per menu type
- [ ] Multi-monitor awareness
- [ ] Anchor point customization (top-left, center, etc.)
- [ ] Padding from viewport edges
- [ ] Smooth repositioning if viewport resizes while open

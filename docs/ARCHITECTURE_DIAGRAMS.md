# System Architecture Diagrams

## Token Context Menu - Component Interaction

```
┌─────────────────────────────────────────────────────────────┐
│                         GameMap                             │
│  - Manages global context menu instance                    │
│  - Routes signals between tokens and menu                   │
└────────────┬────────────────────────────────┬───────────────┘
             │                                │
             │ Receives:                      │ Sends:
             │ context_menu_requested         │ damage/heal/visibility
             │                                │
┌────────────▼──────────────┐    ┌───────────▼──────────────┐
│    TokenController         │    │  TokenContextMenu        │
│  - Detects right-click    │    │  - UI overlay            │
│  - Emits signal           │    │  - Animation handler      │
└────────────┬──────────────┘    └───────────┬──────────────┘
             │                                │
             │ Part of                        │ Extends
             │                                │
┌────────────▼──────────────┐    ┌───────────▼──────────────┐
│      BoardToken           │    │ AnimatedVisibility       │
│  - Entity data            │    │ Container                │
│  - Health/visibility      │    │  - Base animation class  │
│  - Visual feedback        │    │  - Tween management      │
└───────────────────────────┘    └──────────────────────────┘
```

## Animation System - Inheritance Hierarchy

```
                    Control (Godot)
                         │
                         │ extends
                         ▼
         ┌───────────────────────────────┐
         │ AnimatedVisibilityContainer   │
         │                               │
         │  Properties:                  │
         │  - fade_in_duration           │
         │  - scale_in_from              │
         │  - ease_in_type               │
         │  - etc.                       │
         │                               │
         │  Methods:                     │
         │  - animate_in()               │
         │  - animate_out()              │
         │  - toggle_animated()          │
         │                               │
         │  Callbacks:                   │
         │  - _on_before_animate_in()    │
         │  - _on_after_animate_in()     │
         │  - _on_before_animate_out()   │
         │  - _on_after_animate_out()    │
         └───┬───────────────┬───────────┘
             │               │
    extends  │               │ extends
             ▼               ▼
  ┌──────────────────┐  ┌─────────────────────┐
  │ PokemonList      │  │ TokenContextMenu    │
  │ Container        │  │                     │
  │                  │  │  - Quick actions    │
  │  - Filter clear  │  │  - Health display   │
  │    on close      │  │  - Click outside    │
  └──────────────────┘  └─────────────────────┘
```

## Event Flow - Right Click to Action

```
1. User Input
   └─► Right-click on token
       │
       ▼
2. Input Detection
   └─► TokenController._unhandled_input()
       │ Checks: MOUSE_BUTTON_RIGHT + _mouse_over
       ▼
3. Signal Emission
   └─► context_menu_requested.emit(board_token, position)
       │
       ▼
4. Menu Management
   └─► GameMap._on_token_context_menu_requested()
       │ Stores target token reference
       ▼
5. UI Display
   └─► TokenContextMenu.open_for_token()
       │ Updates health display
       │ Positions at cursor
       ▼
6. Animation
   └─► AnimatedVisibilityContainer.animate_in()
       │ Fade from 0 to 1
       │ Scale from 0.9 to 1.0
       ▼
7. User Selection
   └─► Click damage/heal/visibility button
       │
       ▼
8. Action Signal
   └─► TokenContextMenu emits:
       │ - damage_requested(amount)
       │ - heal_requested(amount)
       │ - visibility_toggled()
       │
       ▼
9. Signal Routing
   └─► GameMap receives and routes to:
       │ - _on_context_menu_damage_requested()
       │ - _on_context_menu_heal_requested()
       │ - _on_context_menu_visibility_toggled()
       │
       ▼
10. Action Execution
    └─► BoardToken.take_damage() / heal() / toggle_visibility()
        │
        ▼
11. Visual Feedback
    └─► _update_visibility_visuals()
        │ Changes modulate/transparency
        ▼
12. UI Update
    └─► Menu refreshes health display
        │ Shows new HP values
        ▼
13. Close (optional)
    └─► User clicks outside or Close button
        │
        ▼
14. Animation Out
    └─► AnimatedVisibilityContainer.animate_out()
        │ Fade to 0
        │ Scale to 0.9
        │ Hide on complete
```

## Component Responsibilities

```
┌────────────────────────────────────────────────────────┐
│ Component               │ Responsibility               │
├────────────────────────────────────────────────────────┤
│ AnimatedVisibility      │ • Smooth animations          │
│ Container               │ • Configurable timing        │
│                         │ • Lifecycle callbacks        │
├────────────────────────────────────────────────────────┤
│ TokenContextMenu        │ • UI layout & buttons        │
│                         │ • User input handling        │
│                         │ • Health display updates     │
│                         │ • Signal emission            │
├────────────────────────────────────────────────────────┤
│ TokenController         │ • Mouse hover detection      │
│                         │ • Right-click detection      │
│                         │ • Signal emission            │
├────────────────────────────────────────────────────────┤
│ BoardToken              │ • Entity state (HP, etc.)    │
│                         │ • Action execution           │
│                         │ • Visual feedback            │
│                         │ • Signal emission            │
├────────────────────────────────────────────────────────┤
│ GameMap                 │ • Menu instance management   │
│                         │ • Signal routing             │
│                         │ • Token-menu coordination    │
└────────────────────────────────────────────────────────┘
```

## Signal Flow Diagram

```
       TokenController                    GameMap
              │                              │
              │  context_menu_requested      │
              ├──────────────────────────────►
              │  (token, position)           │
                                             │
                                             │ open_for_token()
                                             ▼
                                      TokenContextMenu
                                             │
              ┌──────────────────────────────┤
              │  damage_requested            │
              ◄──────────────────────────────┤
              │  heal_requested              │
              ◄──────────────────────────────┤
              │  visibility_toggled          │
              ◄──────────────────────────────┘
              │
              │ take_damage() / heal() / toggle_visibility()
              ▼
         BoardToken
              │
              │  health_changed
              │  token_visibility_changed
              ├───────────────► (Other systems can listen)
```

## File Organization

```
tt-sim/
├── scenes/
│   ├── templates/
│   │   ├── board_token.gd          [Entity data & logic]
│   │   ├── board_token.tscn
│   │   ├── token_controller.gd     [Input handling]
│   │   └── game_map.gd             [Coordination]
│   │
│   └── ui/
│       ├── animated_visibility_container.gd  [Base class]
│       ├── token_context_menu.gd             [Menu logic]
│       ├── token_context_menu.tscn           [Menu UI]
│       ├── pokemon_list_container.gd         [Example usage]
│       └── example_settings_menu.gd          [Example usage]
│
└── docs/
    ├── AnimatedVisibilityContainer.md        [API docs]
    ├── AnimatedVisibilityContainer_QuickRef.md
    ├── TokenContextMenu.md                   [Implementation]
    ├── TokenContextMenu_QuickRef.md          [User guide]
    ├── PROJECT_UPDATES.md                    [Summary]
    └── ARCHITECTURE_DIAGRAMS.md              [This file]
```

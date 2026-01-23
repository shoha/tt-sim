# Token Context Menu - Quick Reference

## How to Use

### Opening the Menu
**Right-click** on any board token to open the context menu.

### Quick Actions

#### Damage
- Click `-1`, `-5`, `-10`, or `-20` for preset damage amounts
- Or enter a custom amount and click **Apply**

#### Healing
- Click `+5` or `+10` for quick healing
- Click **Full** to restore to maximum health

#### Visibility
- Click **Toggle Visibility** to show/hide the token
- Hidden tokens appear semi-transparent

#### Close
- Click **Close** button
- Or click anywhere outside the menu
- Or press ESC (if implemented)

## Visual Feedback

- **Menu**: Smoothly animates in/out
- **Menu Position**: Automatically adjusts to stay within viewport (never renders offscreen)
- **Health Display**: Updates in real-time as you make changes
- **Hidden Tokens**: Shown as semi-transparent (50% opacity, desaturated)
- **Visible Tokens**: Full brightness and color

## Keyboard Shortcuts

*None currently - all actions via mouse*

## Tips

- The menu shows current HP vs max HP at the top
- Multiple actions can be performed before closing
- Custom damage accepts any positive integer
- Healing cannot exceed max health
- Changes are immediate - no confirmation needed

## Troubleshooting

**Menu doesn't appear:**
- Make sure you're right-clicking directly on a token
- Check that the token has collision enabled

**Actions don't work:**
- Verify the token is properly initialized
- Check console for error messages

## For Developers

See `TokenContextMenu.md` for full implementation details and customization options.

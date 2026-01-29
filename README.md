# Cooldown Companion

A World of Warcraft addon that allows you to create custom action bar style panels to track spell and item cooldowns with various styling options.

## Features

- **Custom Groups**: Create unlimited groups of tracked spells/items
- **Flexible Anchoring**: Anchor groups to any frame identifiable with `/fstack`
- **Cooldown Animations**: Standard radial swipe cooldown display
- **Glow Effects**: Multiple glow options (Pixel, Action, Proc) with customizable colors
- **Clean Styling**: 1-pixel border style by default with extensive customization
- **Draggable**: Unlock frames to drag and position anywhere

## Installation

1. Download and extract to your `World of Warcraft/_retail_/Interface/AddOns/` folder
2. The addon includes Ace3 libraries in the `Libs` folder
3. (Optional) For enhanced glow effects, install [LibCustomGlow](https://www.curseforge.com/wow/addons/libcustomglow)

## Slash Commands

- `/cdc` or `/cooldowncompanion` - Open configuration panel
- `/cdc lock` - Lock all frames in place
- `/cdc unlock` - Unlock frames for repositioning
- `/cdc reset` - Reset profile to defaults

## Usage

### Creating a Group

1. Open config with `/cdc`
2. Go to the **General** tab
3. Enter a name and click **Create Group**

### Adding Spells/Items

1. Go to the **Groups** tab
2. Select your group from the dropdown
3. Enter a spell name or ID and click **Add Spell**
4. For items, enter an item name or ID and click **Add Item**

### Anchoring to a Frame

1. Use `/fstack` in-game to find the frame name you want to anchor to
2. In the **Groups** tab, under **Anchoring**, enter the frame name
3. Adjust anchor points and offsets as needed

### Styling

1. Go to the **Style** tab
2. Select a group to customize
3. Adjust:
   - Button size (20-64 pixels)
   - Button spacing (0-10 pixels)
   - Border size (0-5 pixels)
   - Border and background colors
   - Orientation (horizontal/vertical)
   - Buttons per row
   - Show/hide cooldown text

### Button-Specific Options

1. In the **Groups** tab, select a button from the list
2. Configure:
   - **Show Glow**: Always display a glow effect
   - **Glow Type**: Pixel, Action, or Proc style
   - **Glow Color**: Custom RGBA color

## Default Styling

- Button Size: 36px
- Button Spacing: 2px
- Border Size: 1px (clean, minimal look)
- Border Color: Black
- Background: Semi-transparent black

## Tips

- Use the drag handle (visible when unlocked) to reposition groups
- Groups can be enabled/disabled individually
- Each group maintains its own style settings
- Profile support allows different setups per character

## Known Limitations

- **WoW 12.0 Secret Value API**: Due to Blizzard's security changes, buff/debuff tracking is not available. Only spell and item cooldowns can be tracked.
- Item names may not resolve immediately if not cached; use item IDs for reliability
- Anchoring requires exact frame names as shown in `/fstack`
- LibCustomGlow is recommended for the best glow effects

## Changelog

### 1.1.0
- Renamed to Cooldown Companion
- Updated for WoW 12.0 (Midnight)
- Removed buff/debuff tracking due to secret value API restrictions
- Fixed cooldown tracking to work with secret value API
- Added periodic ticker for reliable combat cooldown updates

### 1.0.0
- Initial release
- Core tracking functionality
- AceConfig-based configuration
- Multiple glow options
- Flexible anchoring system

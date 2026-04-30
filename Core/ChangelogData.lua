--[[
    CooldownCompanion - Core/ChangelogData.lua
    Repo-authored release notes bundled with the addon. Paste these same notes into the GitHub release body when publishing.
]]

local ADDON_NAME, ST = ...

ST._changelogData = {
    order = {
        "1.13.6",
        "1.13.5",
        "1.13.4",
        "1.13.3",
        "1.13.2",
        "1.13.1",
        "1.13",
        "1.12.5",
        "1.12.4",
        "1.12.3",
        "1.12.2",
        "1.12.1",
        "1.12",
        "1.11",
        "1.10.28",
        "1.10.27",
        "1.10.26",
        "1.10.25",
    },
    entries = {
        ["1.13.6"] = {
            markdown = [[
## New Features

- **Copy panel styles directly:** Icon and bar panels can now copy their visual setup from another same-type panel from the panel header right-click menu.

## Polish | QoL

- **Clearer CDM aura choices:** CDM aura options now appear and add as their specific tracked states more consistently across panel entries, custom aura bars, resource aura pickers, and Auto Add.

## Bug Fixes

- **Custom Aura Bar Fix:** Custom aura bars that track stacks and hide while inactive should now appear as soon as the tracked aura is active, regardless of aura stack count.
]],
        },
        ["1.13.5"] = {
            markdown = [[
## New Features

- **Search Function:** Added a search bar to the config UI so you can quickly locate saved groups, panels, and entries, then jump straight to the match.

## Polish | QoL

- **Rename reminders:** Added small rename badges for default group and panel names, making it easier to clean up generic names with the existing rename popup.
]],
        },
        ["1.13.4"] = {
            markdown = [[
## Bug Fixes

- **Short cooldown timing:** Fixed an issue where very short cooldowns should no longer briefly flash as ready right after use, and cooldowns ending during the global cooldown should catch up more smoothly.
]],
        },
        ["1.13.3"] = {
            markdown = [[
## Polish | QoL

- **Better settings previews:** Preview buttons across the settings UI now act like stay-on toggles and now work for text elements like cooldown / aura duration / aura stacks.

## Bug Fixes

- **PvP talent availability:** PvP talent buttons now hide automatically when entering content that disables them without needing a reload.
- **Replacement spell cooldowns:** Fixed a regression where buttons for spells that temporarily become another ability now follow the replacement ability's icon and cooldown, then return to the original spell when the replacement ends.
]],
        },
        ["1.13.2"] = {
            markdown = [[
## New Features

- **Blizzard-style aura swipes:** Icon-mode aura durations can now use a yellow swipe overlay, enabled from icon panel Appearance settings, that more closely matches Blizzard's Cooldown Manager aura display.

## Bug Fixes

- **Frame anchoring alpha errors:** Anchored player and target frames using Inherit Alpha should no longer cause recurring Lua errors during target changes or other alpha updates.
]],
        },
        ["1.13.1"] = {
            markdown = [[
## New Features

- **Hero spec talent filters:** You can now make entries load only for a specific hero spec, or stay hidden while that hero spec is active, directly from the talent condition picker.

## Polish | QoL

- **Clearer unlocked group editing:** Unlocked groups now show a visible wrapper, clearer headers, and hover highlights so it is easier to see which panels belong together while you edit.
- **Direct panel editing inside groups:** You can now select, drag, and nudge panels inside an unlocked group without locking and unlocking the whole group first, and the editing UI now hides during combat before restoring your previous unlocked state afterward.

## Bug Fixes

- **Imported panel placement:** Older single-container imports now keep their saved panel position instead of snapping back to the center.
- **Hidden aura bars appearing late:** Hidden segmented and overlay custom aura bars now appear immediately when an aura is first applied from 0 stacks.

## Other

- **ignoreGCD cooldown handling:** Cooldown-based desaturation and related on-cooldown visuals now use real spell cooldown data instead of being kept active by GCD-only windows, while fallback cases still keep their configured GCD swipe and countdown behavior.
- **12.0.5 TOC update:** Updated the addon's TOC for WoW 12.0.5.
]],
        },
        ["1.13"] = {
            markdown = [[
## New Features

- **Trigger panels for compound alerts:** You can now build a trigger panel that only appears when every enabled entry meets its conditions, giving you one cleaner signal for more complex setups.
  - Combine multiple checks on the same entry, including cooldowns, buffs, debuffs, charges, range, count text, and similar conditions, without needing duplicate rows.
  - Choose whether the triggered result shows as a texture, a manual icon, or custom text.
  - Add sound alerts and active effects like Pulse, Color Shift, Bounce, and Shrink / Expand where they fit.
  - Preview the display more cleanly while editing, and get clearer tooltips and wording so trigger panel setup is easier to understand.
]],
        },
        ["1.12.5"] = {
            markdown = [[
## Bug Fixes

- **Outdoor delve load conditions:** Delve-based load conditions now recognize outdoor delves more reliably, so panels meant to appear there should show and hide correctly.
]],
        },
        ["1.12.4"] = {
            markdown = [[
## New Features

- **First time user tutorial:** New setups now get a guided walkthrough for creating their first icon panel and adding a spell. You can replay the tutorial later from the gear menu in the top right of the config.

## Polish | QoL

- **Player or target choice for resource aura overlays:** Resource aura overlays also received the unit specification that has been applied to aura tracking in panels and custom aura bars in order to protect the display from showing incorrect information.

## Bug Fixes

- **Target-based standalone auras:** Standalone aura entries that should watch your target now default there more reliably instead of being set to yourself by mistake, like Shatter for Frost Mage.
]],
        },
        ["1.12.3"] = {
            markdown = [[
## Polish | QoL

- **Aura unit specification for Custom Aura Bars:** You now choose whether a custom aura bar watches your own aura or your target's aura, making buffs, procs, and debuffs easier to set up correctly and protecting them from potentially displaying incorrect durations.
- **Enemy-only target alpha toggle:** Target-based alpha rules can now be limited to enemy targets only, so friendly targets no longer force those elements fully visible when you do not want that.
- **Cleaner move menus:** Moving entries between panels is now grouped by folder and group, which makes large setups much easier to navigate.
- **Clearer config headers:** Selected groups and entries now show cleaner, more consistent names at the top of columns by changing their names dynamically based on what is selected in the config.

## Bug Fixes

- **Shapeshift freeze with config open:** Shapeshifting while the config is open should no longer cause the multi-second freeze that could happen in larger setups.

## Other

- ! **Import strings from before 1.10 are now deprecated:** Profiles and imports from before version 1.10 (when the panel system was implemented) now fail on import and show a rejection message. This change was made in order to reduce maintenance overhead and simplify ongoing development.
]],
        },
        ["1.12.2"] = {
            markdown = [[
## Polish | QoL
- **Texture Panels**:
  - **SharedMedia:** The texture picker now lets you save SharedMedia textures. The custom import system has been replaced by this. If wanting to add custom textures, sync them via `SharedMedia_MyMedia` in your AddOns folder.
  - **Favorites**: Favorite any texture in the browser by clicking the + sign in the top right of the texture preview. This adds the texture to the new favorites category, making it much easier to reuse the textures you like most.
  - **Clearer texture browser controls:** Texture panel labels, browser messages, and favorite actions are now easier to understand at a glance.
  - **More blend-ready texture options:** More default texture panels and saved favorites now keep their intended blend look automatically.

## Bug Fixes

- **Charge/use text:** Cleaned up some more issues with this text element.
]],
        },
        ["1.12.1"] = {
            markdown = [[
## New Features

- **Ready glow for full charges:** Charge-based spells and items can now trigger Ready Glow when they are fully recharged, with new panel controls for tuning that behavior.

## Polish | QoL

- **Sound previews in dropdowns:** Sound alert dropdowns now include inline preview buttons so you can hear a sound before picking it.
- **Easier panel anchoring:** Panel anchor targets are now grouped in a cleaner dropdown, making it faster to pick the panel you want to anchor to.

## Bug Fixes

- **Standalone aura entries:** Fixed several issues that could cause standalone aura tracking to show the wrong ready state, charge state, or status text, especially on older migrated setups.

## Performance

- **Hidden custom aura bars:** Custom aura bars now avoid unnecessary update work while hidden, reducing CPU usage when they are not visible.
]],
        },
        ["1.12"] = {
            markdown = [[
## New Features

- **Texture panels:** A brand-new panel type that displays spell and aura effects as standalone visual indicators anywhere on your screen. Comes with drag positioning, nudge controls, rotation, stretch, opacity, and bounce/shrink animations. Includes a built-in texture picker with curated Blizzard textures, a proc overlay browser, and support for custom texture paths. Everything previews live in the config.

- **Cast bar vertical offset:** When panel anchoring is active for both resources and the cast bar, cast bars now have their own independent vertical offset slider, so you can position the cast bar separately from the rest of the icon group.

- **New standalone aura desaturation toggles:** Reworked the old `Saturate while Aura Active` toggle into 2 new muturally exclusive toggles: `Invert Desaturation Logic` and `Never Desaturate` for more fine-tuned control. Only applies to standalone aura entries.

## Polish | QoL

- **Panel type dropdown:** Extra panel types are now organized in a compact dropdown instead of separate buttons.
- **Empty panel guidance:** The panel list now shows helpful guidance text when no panels exist yet.
- **Aura tracking tooltip rewrite:** The aura tracking tooltip now shows structured setup requirements, supported capabilities, and limitations instead of a brief warning.
- **Stable config columns:** Button settings now always appear in Column 3 and panel/group settings always in Column 4.
- **Custom aura bar alpha controls:** Independently anchored custom aura bars now have their own Alpha tab.
- **Config tooltips:** Hold Shift while hovering over entries in Column 2 to see their tooltips. Also works for entries seen via Auto-Add in Column 3.
- **Smaller export strings:** Export strings are now significantly more compact, producing shorter share codes. Importing older strings still works as before.
- **Simplified group positioning:** Removed the old Anchor to Frame, Anchor Point, and Relative Point controls from group layout settings. Groups now use simple screen offsets for positioning. Panel settings continue to maintain their Anchor-to-Frame settings.

## Bug Fixes

- **Stacks layout preview not refreshing:** The layout preview now updates immediately when you change max stack settings.
- **Single aura stacks in text mode:** Auras with a single stack now show the stack count in text mode, matching multi-stack auras.
]],
        },
        ["1.11"] = {
            markdown = [[
## New Features

- **Custom keybind text:** Icon buttons now support custom keybind text, letting you override what's shown in the keybind corner of any icon.

## Polish | QoL

- **Drag and Drop 2.0:** A top-to-bottom overhaul of drag-and-drop across the config, with animated previews and smarter drop targeting.
  - **Column 1 drag-and-drop:** Sections, folders, and unloaded spells can now be reordered with refined drop targets and stable previews.
  - **Column 2 drag-and-drop:** Panels now animate smoothly as you drag, with cleaner gap placement and preview opacity.
  - **Resource bar layout and order:** Attached resource bars now support mirrored drag-and-drop reordering with a dedicated layout preview.
  - ! **The browse other characters toggle has been moved to top right button cluster to accomodate the new drag-and-drop system**

- **Column 1 onboarding:** First-time group setup and empty sections now show friendly placeholder text instead of being empty, with proper text wrapping in Column 1.

## Bug Fixes

- **Astral Power on non-Balance specs:** Astral Power is now hidden for druids that are not in their Balance spec.
]],
        },
        ["1.10.28"] = {
            markdown = [[
## Bug Fixes

- **Badge Lua Fix:** Disabled panel headers in the config view should now keep their own status badge correctly instead of sharing or losing it when the list refreshes.
]],
        },
        ["1.10.27"] = {
            markdown = [[
## New Features

- **Built-in changelog viewer:** You can now open bundled release notes directly from the config panel, browse older versions, and adjust the viewer text size for easier reading.

## Polish | QoL

- **Aura unit selection for tracked spells:** Aura-tracked spells can now explicitly watch either your Player or Target auras, making buff and debuff tracking easier to set up when the default target is not the one you want.
  - ! *Please double-check any entries that attach auras to spells to make sure the selected target is correct. This change was needed to help protect aura tracking from reading the wrong duration.*

- **Clearer aura tracking setup:** Aura tracking now gives more direct active or inactive feedback, clearer guidance when Blizzard Cooldown Manager setup is missing, and cleaner labels in the spell settings panel.

## Bug Fixes

- **Fixed inconsistent count text behavior:** Supported icon and bar count text should now behave more consistently instead of mixing charge-style and other count displays in the wrong situations.

- **Whirling Dragon Punch fix:** Whirling Dragon Punch now supports the unusable-state toggle so it can follow the same visibility and dimming rules as other supported buttons.
]],
        },
        ["1.10.26"] = {
            markdown = [[
## Bug Fixes

- **Fixed false cooldown states after empowered casts:** Spells should no longer briefly dim, hide, or act like they are on cooldown when an empowered cast is released and enters its recovery window.
- **Fixed config help tooltip taint errors:** Hovering info buttons in the config should now avoid the tooltip sizing taint errors that could fire while reading help text.
]],
        },
        ["1.10.25"] = {
            markdown = [[
## New Features

- **Animated custom aura bar indicators:** Custom aura bars can now show when an aura is active or in pandemic range, with optional pulse and color-shift effects to make those states easier to spot at a glance.
- **Multiline text panels:** Text panel formats can now span multiple lines, including a line break token in the format editor so you can build stacked text layouts more easily.

## Polish | QoL

- **Better bar effect previews:** Active-aura and pandemic preview buttons now give a fuller, more reliable preview of custom aura bar effects at both the group and per-button level.
- **More dependable text formatting:** Text panel formatting now handles keybind conditionals and fallback text more consistently, making advanced formats behave more predictably.

## Bug Fixes

- **Fixed multiline text sizing:** Multiline text panels and per-button multiline overrides now size themselves more reliably, reducing clipping and layout issues.
- **Fixed aura-only status text edge cases:** Aura-only text displays now report timeless buffs more cleanly and handle combat aura timers with more reliable sizing and classification.
]],
        },
    },
}

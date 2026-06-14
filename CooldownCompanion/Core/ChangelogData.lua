--[[
    CooldownCompanion - Core/ChangelogData.lua
    Repo-authored release notes bundled with the addon. Paste these same notes into the GitHub release body when publishing.
]]

local ADDON_NAME, ST = ...

ST._changelogData = {
    order = {
        "1.19.2",
        "1.19.1",
        "1.19",
        "1.18",
        "1.17",
        "1.16",
        "1.15",
        "1.14.3",
        "1.14.2",
        "1.14.1",
        "1.14",
        "1.13.10",
        "1.13.9",
        "1.13.8",
        "1.13.7",
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
        ["1.19.2"] = {
            markdown = [[
## New Features

- **Group Alpha:** Panel groups can now use one Group Alpha setting for directly anchored panels, including texture and trigger panels in the default group anchor mode.

## Polish | QoL

- **Clearer bar indicators:** Active aura and max stack indicators now share the same advanced settings layout, with border choices grouped together and bar effects separated into their own controls.
- **Max stack Pixel Glow controls:** Max stack Pixel Glow can now use the same line controls as active aura indicators, including the number of glow lines.
- **Bar Icon overrides:** Bar-mode buttons can now edit per-button Bar Icon overrides, and promoted Bar Icon overrides keep their flip, offset, and size behavior if group defaults change later.
- **Smaller default solid borders:** Newly enabled solid borders now start at a less oversized default.

## Bug Fixes

- **Duplicated profiles:** Duplicating a profile now keeps character-only groups assigned to their original characters instead of loading every copied character's groups on the current character.
- **Appearance Overrides tabs:** Saved overrides that are inactive for the selected button now show as inactive rows with Revert buttons instead of leaving the tab blank.
]],
        },
        ["1.19.1"] = {
            markdown = [[
## Performance

- **On-demand settings UI:** Normal gameplay can now run without loading the full settings interface until you open it. Release downloads now include the main addon and its companion settings folder, and settings still open from all the usual places.
- **Focused player updates:** CDC now skips extra power and spell-cast activity from other units, keeping cooldown updates focused on your character.
- **Fewer duplicate refreshes:** Cooldown displays should stay just as responsive during event-heavy moments while the addon avoids repeating the same refresh work when several updates happen at once.
- **Lighter key press highlights:** Key press highlights should look and respond the same, while the addon does less background work when no highlight is active.
- **Quieter alpha updates:** Profiles without active alpha fading or forced alpha rules now stop that background updater until something actually needs it.
- **Smoother group refreshes:** Group refreshes, mode switches, and visibility changes should do less rebuilding, while reused buttons still start clean.
- **Faster style-only setting edits:** Changes like icon size, spacing, bar dimensions, text size, and texture styling should update cooldown groups with less rebuilding.
- **Less unrelated aura work:** Player and target aura tracking should behave the same, while busy group, raid, and other activity from unrelated units creates less background work.
- **Refresh reliability cleanup:** Cooldown refresh handling was simplified behind the scenes to keep the recent performance work easier to maintain, with no intended gameplay change.
]],
        },
        ["1.19"] = {
            markdown = [[
## New Features

- **Trinket slot tracking:** Players can add Trinket Slot 1 or Trinket Slot 2 and have the entry follow the on-use trinket currently equipped in that slot.
- **Multiple resource thresholds and ticks:** Resource bars can now show up to three threshold colors or tick markers per resource and specialization.
- **Segmented smoothing controls:** Segmented resource bars and Stack Count bars in Segmented or Overlay mode can now keep smooth animation or snap immediately between segment values per spec or entry.
- **EllesmereUI unit-frame anchoring:** Frame Anchoring now includes one EllesmereUI Unit Frames option for both the full EllesmereUI addon and the standalone unit-frame package, with auto-detect choosing active player and target frames.

## Polish | QoL

- **Resource settings redesign:** Custom Bars & Resources now lets players select enabled resources directly and edit each resource/spec's text, colors, thresholds, ticks, and aura overlay settings from a focused Resource panel.
- **Resource Aura Overlay setup:** Overlay settings have been modernized and now use a compact Aura Tracking-style editor with Overlay Aura, CDM Settings, Pick CDM, selected-aura display, and clear controls.
- **Feral snapshot icons:** Feral Druid aura entries for Rake, Rip, and Moonfire can show the actual active aura icon so Tiger's Fury-snapshotted debuffs are easier to distinguish.

## Bug Fixes

- **Pandemic glow timing:** Pandemic glow now stays stable while a tracked aura remains in its pandemic refresh window and clears as soon as a refresh leaves that range. Button panels and resource-attached custom aura bars use the same behavior.
- **Soul Immolation charges:** Soul Immolation now displays as a charge-based spell when the Devourer Demon Hunter talent gives it 2 charges.
- **Frame-anchored alpha inheritance:** Panels that inherit alpha now keep that inheritance when anchored through unit frames or other external frames.

## Performance

- **Large-profile config refreshes:** The left group list should refresh more smoothly on large profiles, especially when sorting loaded/unloaded groups or searching.
- **Lighter aura updates:** Aura-heavy setups do less repeated work when many auras change at once, helping buttons and aura-backed resource bars stay responsive.
]],
        },
        ["1.18"] = {
            markdown = [[
## New Features

- **Profile-wide visual styles:** The gear menu now includes profile-level font, outline, and bar texture options so players can set one shared look across configurable addon text and bars while preserving local choices for later.
- **Passive cooldown tracking:** Passive abilities that Blizzard exposes as real cooldowns, such as Shaman Reincarnation, can now be added and tracked as cooldown entries.
- **Rune recharge text:** Death Knight Rune bars can now show optional per-segment recharge countdown text, either only on recharging Runes or across all Rune segments.
- **Unusable Visual modes:** The Indicators setting is now Show Unusable Visual, with separate Dim Icon and Desaturate Icon controls so players can use dimming, desaturation, both, or neither.

## Polish | QoL

- **Smoother bar motion:** Bar panels, Custom Bars, resource bars, health bars, and previews now fill and drain more smoothly instead of stepping through choppy value updates.
- **Smarter group and folder icons:** Top-level group rows and folder rows now show the first available child icon when no custom icon is set.
- **Talent picker help:** The talent picker now includes an in-panel help icon that explains border colors, choice talents, spec and hero tree dropdowns, and how multiple talent conditions combine.
- **Rune and Essence spenders:** Death Knight rune spenders and Evoker Essence spenders without real cooldowns no longer show resource recharge as a button cooldown or desaturation. These displays were simplified in order to avoid inconsistent Blizzard-provided information.

## Bug Fixes

- **Form action-bar keybinds:** Keybind text should now stay accurate for abilities on form-replacement action bars, such as Druid Bear Form replacing Action Bar 1.
- **Panel anchoring and alpha:** Panels anchored to other panels should now keep their intended positions on fresh login, and inherited alpha should follow parent visibility and mouseover behavior more reliably.
]],
        },
        ["1.17"] = {
            markdown = [[
## New Features

- **Cursor-anchored panels:** Panels can now use the mouse cursor as an anchor target during gameplay.
  - Cursor-anchored panels keep their normal cooldowns, glows, visibility rules, hide conditions, click behavior, and other panel settings while following the mouse.
  - Resource bars, cast bar, and unit frames cannot anchor to the cursor-anchored panels.
- **Panel Alpha controls:** Panels anchored to another panel can now inherit the target panel's alpha or use their own custom alpha settings.
- **Texture and Trigger Panel anchoring:** Texture Panels and Trigger Panels can now anchor standalone displays to another panel or to a picked frame.

## Polish | QoL

- **Smoother panel movement:** Unlocked panels now use more consistent drag headers, coordinate readouts, help tooltips, reset controls, and one-pixel nudging across regular panels, textures, and trigger panels.

## Bug Fixes

- **Loaded-to-unloaded group dragging:** Dragging a loaded group over the Unloaded Groups section no longer causes a Lua error.
- **Import review window layering:** Import review windows and confirmation popups now open above the main config panel, and import mode uses stable radio-style choices instead of a dropdown that could cover review text.
]],
        },
        ["1.16"] = {
            markdown = [[
## New Features

- **Reviewable imports and profile backups:** Imports now open one review flow for profile backups, groups, panels, folders, Custom Bars, and diagnostic profile strings before anything is applied.
- **Selected-piece profile imports:** Profile backups can restore the full profile or import selected current-class pieces, so players can pull useful panels, groups, folders, and Custom Bars from a backup without replacing everything.
- **Custom Bar cooldown and aura parity:** Custom Bars now follow the same cooldown, charge, global cooldown, and aura tracking behavior as regular bar panels, including player/target aura tracking, target switching, stacks, expiry, pandemic display, and Hide When Inactive.
- **Aura Unit for Custom Bars:** Aura Custom Bars can manually track Player or Target auras, matching standalone aura entries elsewhere in the addon.
- **Optional IconBrowser support:** Settings icon pickers can use IconBrowser for folder, button, trigger-panel, and container icons when it is installed, while the native picker remains the fallback.

## Polish | QoL

- **Clearer import reviews:** The import review window is easier to read over the game background, with larger shadowed review text, clearer spacing, and action buttons that stay attached to the bottom while resizing.
- **More consistent visuals:** Cooldown, aura, charge, visibility, glow, text, texture, trigger-panel, resource bar, custom bar, and health-bar visuals should line up more reliably across the addon.
- **More useful Bug Reports:** Bug Reports now include clearer display context, reasons something may be hidden, and compact profile data, making support reports easier to understand.

## Bug Fixes

- **Spell override visibility:** Cooldown icons set to hide while not on cooldown should stay hidden during temporary spell override states, including (eg Downpour), while still appearing when their saved spell is actually on cooldown.
- **Character auto-anchoring exclusions:** Character-only groups excluded from auto-anchoring now stay excluded, so auto-anchored resource bars, cast bars, and unit frames can move to the next eligible icon panel.
- **Cleaner picker cleanup:** Icon picker windows and sound preview dropdown rows clean up after themselves more reliably.

## Performance

- **Disabled Bars & Frames stay cold:** Resource Bars, Cast Bar anchoring, and Frame Anchoring now stop their ongoing background work when those features are disabled, reducing addon work for players who do not use them.

## Profile Compatibility

- **1.15 checkpoint required:** Cooldown Companion now requires profiles and import strings to have passed through the 1.15 compatibility checkpoint. Older profiles and very old compact import strings now show recovery guidance instead of trying outdated migrations.
]],
        },
        ["1.15"] = {
            markdown = [[
## New Features

- **Custom Bars import and export:** Custom Bars can now be imported and exported directly from the Custom Bars settings, including single bars, selected bars, or all Custom Bars.
- **Spec-aware Custom Bars:** Custom Bars now show as Loaded for the active spec or under Inactive Specs for other specs, with spec icon badges and spec filters to control where each bar belongs.
- **Custom Bars batch actions:** Multi-select actions now work for Custom Bars, including enable/disable, export, and delete.
- **Aura tracking cooldown display:** Aura-tracked icon buttons now have an opt-in Keep Spell Cooldown Swipe setting, letting the spell's own cooldown stay visible while the tracked aura still controls aura icon, glow, visibility, and stack behavior.
- **Profile-wide one-pixel borders:** A new Profile One-pixel Borders option in the config gear menu makes panel, resource bar, and cast bar borders render at one-pixel thickness without overwriting each saved border setting.

## Polish | QoL

- **Advanced settings side panel:** Gear buttons beside enabled config settings now open a focused Advanced Settings editor on the right instead of expanding extra controls inline.
- **Cleaner config previews:** Many preview actions now appear as compact play badges beside their setting, keeping dense config sections easier to scan.
- **Config drag visibility:** The main config window and attached tools now fade while being dragged, making it easier to see the game world and addon layout behind them.

## Profile Compatibility

- **1.15 import checkpoint:** Existing local profiles still open and migrate normally, while newly exported profiles, groups, folders, Custom Bars, and diagnostic strings now include a 1.15 compatibility marker.
- **Older import strings:** Import strings created before the 1.15 checkpoint are now rejected with recovery guidance instead of relying on very old import paths indefinitely.
- **Future migration cleanup:** 1.15 is the bridge release for older local profiles. Open your existing profiles in 1.15 before later cleanup releases remove older migration support.
]],
        },
        ["1.14.3"] = {
            markdown = [[
## New Features

- **One-pixel border thickness:** Border settings now include a dedicated One-pixel option for icon, bar, text, cast bar, and resource-style borders, while existing Custom Thickness borders and per-button overrides keep their current behavior.

## Polish | QoL

- **Blizzard CDM setup:** Aura Tracking now only shows the Blizzard CDM activation button when Blizzard CDM is disabled, keeping the config free of unnecessary toggles.

## Bug Fixes

- **Config helper text:** Helper, warning, status, and preview text in the config UI should now wrap correctly within the column instead of truncating unpredictably.

## Other

- **Cooldown readiness:** Buttons should no longer look like they are on a real cooldown during global-cooldown-only moments, including desaturation, icon fill, availability text, sound alerts, and hide-on-cooldown behavior.
  - This is not a normal bug fix: Blizzard's cooldown APIs can briefly expose incomplete or conflicting state during very short, high-haste cooldown windows, so the addon now trusts the current API result instead of adding extra smoothing.
]],
        },
        ["1.14.2"] = {
            markdown = [[
## New Features

- **Duration format choices:** Duration text now more formats across cooldown, aura duration, bar, text-mode, and Custom Bar displays.
- **Tracked and Additional Auras:** Button entries and Custom Bars now use searchable aura picking, ordered aura rows, right-click removal, and Shift-hover spell tooltips for tracked and additional aura IDs.
- **Standalone aura fallbacks:** Standalone aura entries can watch additional aura IDs while still prioritizing the original aura whenever it is active.

## Polish | QoL

- **Aura setup clarity:** The older override and fallback wording has been replaced with Tracked Auras and Additional Auras, with compact rows that show the spell icon, name, and ID at a glance.

## Bug Fixes

- **Very short cooldowns:** Short real cooldowns under high haste should be less likely to flash as ready while the ability is still recovering behind the active global cooldown.
]],
        },
        ["1.14.1"] = {
            markdown = [[
## Bug Fixes

- **Bar Panel aura stack displays:** Bar panel entries using Stack Count aura display now keep their segmented or overlay bar layout visible even when the tracked aura is inactive.
- **Migrated Custom Bars:** Custom Bars migrated from old Custom Aura Bars can now be fully deleted without the final removed entry reappearing afterward.
]],
        },
        ["1.14"] = {
            markdown = [[
## New Features

- **Custom Bars overhaul:** Custom Aura Bars have been rebuilt as Custom Bars in Bars & Frames.
  - Custom Bars now always attach to the Resource Bars panel stack, keeping them tied to the resource layout while Bar Panels remain the freely movable bar option.
  - Existing Custom Aura Bar setups migrate into the new Custom Bars model, including saved display settings, colors, sizing, sound alerts, and load conditions.
- **Spell cooldown Custom Bars:** Custom Bars support spell cooldowns with charge text, recharge colors, ready/cooldown colors, and sound alerts.
- **Aura tracking for spell Custom Bars:** Spell Custom Bars can track an associated aura alongside the spell cooldown.
  - Aura Tracking, Tracked Auras, Additional Auras, Aura Unit, CDM picking, active aura indicators, pandemic effects, and aura-based visibility rules are available where they apply.
  - Spell Custom Bars support Active and Stack Count aura tracking, with Continuous, Segmented, and Overlay stack display modes.
- **Bar Panel aura stack displays:** Bar Panel aura entries can now display tracked auras as stack-count bars instead of only active-duration bars.
  - Stack displays support Continuous, Segmented, and Overlay modes, plus max-stack color and max-stack indicator controls.
- **Per-spec Resource Bar customization:** Resource Bar layout, styling, colors, resource text, Health display settings, aura overlays, and attached Cast Bar placement can now differ by specialization.
- **Focus Exists alpha control:** Alpha settings now include a Focus Exists toggle, allowing frames to become fully visible while a focus target exists.

## Polish | QoL

- **Clearer Resource Bar copy controls:** Resource Bars now separate character-copy and spec-copy actions into distinct badges with clearer tooltips and confirmation dialogs.
  - Spec-to-spec Resource copies preserve manual or spec-local setup such as Health settings, Custom Bars, and aura overlays.
- **Panel add-entry helper text:** The panel add-entry box now shows grey helper text when empty, making it clearer that the field accepts spells, items, and IDs.
- **Folder controls restored:** Folder rows can be selected to edit folder load conditions, while the plus/minus badge remains the dedicated expand/collapse control.
  - Folder names, filter badges, and collapse controls now reserve space more cleanly in narrow layouts.

## Bug Fixes

- **Segmented resource flicker:** Segmented resource bars should no longer briefly flash the wrong ready color during resource-bar refreshes.

## Performance

- **Reduced duplicate cooldown refresh work:** Cooldown events now avoid repeating the same immediate refresh on the next ticker pass when no newer dirty state arrived.
]],
        },
        ["1.13.10"] = {
            markdown = [[
## New Features

- **Item fallback settings:** Consumables can now use an ordered fallback list, letting one consumable entry automatically show and track the first available usable item from your bags.
  - Healthstone entries with item fallbacks move to the next available fallback during the short combat state where Healthstone is unusable but its visible cooldown has not started yet.
- **Load conditions extended to entries:** Environment based load conditions can now be configured at the level of individual entries in addition to panels, groups, and folders.

## Polish | QoL

- **Narrow config resizing:** The config window now automatically hides folder/group/entry icons when reducing the width past a certain threshold in order to maintain visual clarity.
]],
        },
        ["1.13.9"] = {
            markdown = [[
## New Features

- **Health Bar:** Bars & Frames can now show an optional player health bar alongside your existing resource bars.
  - Health has its own tab, can be turned on from Resource Toggles, and uses the existing resource-bar sizing, ordering, layout, preview, texture, border, and text controls.
  - Health and Missing Health can be styled separately, with independent colors, opacity, and optional gradients.
  - Health bars can show friendly absorbs, healing absorbs, incoming heals, and low-health alerts, with previewable colors and bar textures for each effect.
  - Health text can show percent, current health, current / max health, current + percent, and compact percent formats without the `%` sign.

## Bug Fixes

- **Cast bar color flash:** Custom-styled cast bars should no longer briefly flash back to Blizzard's default fill color when a cast finishes, stops, fails, or is interrupted.
]],
        },
        ["1.13.8"] = {
            markdown = [[
## New Features

- **Icon Fill Timer:** Icon panels can now show cooldowns and tracked aura durations as a rectangular fill over the icon, with separate cooldown and aura colors and a full aura-colored fill for untimed active auras.

## Polish | QoL

- **Cleaner Buttons search placement:** The Buttons config search field now sits inside the Groups column footer, returning columns in the config to pre-search height.
- **Indicator settings organization:** The icon-mode Indicators tab is easier to scan, with Glows, Timers, and States grouped more clearly.
]],
        },
        ["1.13.7"] = {
            markdown = [[
## Polish | QoL

- **Bar color overrides:** Bar colors for entries in bar panels are now able to set per-entry overrides in order to have custom bar colors within a panel.

## Bug Fixes

- **Aura display updates:** Multi-variant aura displays now keep their active names and icons more reliably and reset cleanly when the aura ends (eg. Roll the Bones).
- **Cooldown responsiveness:** Cooldown buttons now recover more quickly after rapid resets (eg. Between the Eyes, Bloodthirst), so spells that become available right away should no longer look unavailable longer than they are.
]],
        },
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

--[[
    CooldownCompanion - Core/ChangelogData.lua
    Repo-authored release notes bundled with the addon. Paste these same notes into the GitHub release body when publishing.

    Trim policy: entries are kept back to the profile-import support floor
    (IMPORT_CHECKPOINT_VERSION, Core/Migrations.lua). When that floor moves,
    trim entries for versions older than it. Full history lives in the GitHub
    releases.
]]

local ADDON_NAME, ST = ...

ST._changelogData = {
    order = {
        "1.22.1",
        "1.22",
        "1.21",
        "1.20.1",
        "1.20",
        "1.19.5",
        "1.19.4",
        "1.19.3",
        "1.19.2",
        "1.19.1",
        "1.19",
        "1.18",
        "1.17",
        "1.16",
        "1.15",
    },
    entries = {
        ["1.22.1"] = {
            markdown = [[
## New Features

- **Outline + Slug font outlines:** Added an Outline + Slug font outline option for addon text.
]],
        },
        ["1.22"] = {
            markdown = [[
## Polish | QoL

- **Separate cooldown and aura duration swipes:** The single combined swipe toggle is now split into Show Cooldown Swipe and Show Aura Duration Swipe, so you can control each independently. The Blizzard Cooldown Manager aura swipe style now lives inside the Aura Duration Swipe advanced settings. Existing swipe settings carry over automatically after updating.
- **Open bar settings from previews:** In Bars & Frames, clicking a Resource or Custom Bar preview in Layout & Order now opens that bar's settings, matching the Custom Bars & Resources list.

## Bug Fixes

- **Custom Bars follow talent swaps:** Custom Bars with talent or load conditions now appear and disappear correctly right after you change talents, with no reload needed. The config panel's Active and Inactive lists, along with indicator previews, now reflect only the bars that will actually load for your current spec, talents, and conditions.
- **Aura displays ignore spell-only states:** While a tracked aura is active, its entry now reflects aura state only. It no longer dims or hides based on the spell's castability, turns red for range, or desaturates for usability. Normal range and usability visuals return once the aura fades.
- **GCD swipe works with the cooldown swipe off:** On icon panels, Show GCD Swipe now draws the global-cooldown sweep even when Show Cooldown Swipe is turned off. Previously that exact combination showed nothing, so the toggle appeared to do nothing.

## Performance

- **Much lower combat CPU:** A large backend restructuring makes Cooldown Companion now uses roughly a third of the CPU it previously used during combat, and close to none while you are out of combat or idle. Every display behaves exactly as before, including swipes, charges, text countdowns, pandemic glow, proc glows, target-switch behavior, panels, and bars.
]],
        },
        ["1.21"] = {
            markdown = [[
## New Features

- **Cooldown Manager Starter Panels:** Empty groups can now build editable panels from Blizzard's Cooldown Manager in one click, including Essential Cooldowns, Utility Cooldowns, Tracked Buffs, and Tracked Bars.
- **Starter Panel Defaults:** New starter panels use cleaner ordering, centered compact layouts, tracked aura defaults, and safer placement.
- **Zero-Charge Visibility:** Charge-based spell buttons can now be set to appear only when every charge is spent, so abilities like Monk Roll can stay hidden until they are fully out of charges.

## Polish | QoL

- **Better Defaults:**  New icon and bar panels default the following to enabled: Compact Mode, Loss of Control visuals, and Unusable Dimming/Visuals.
  - Compact Mode is disabled if resources, cast bar, or Unit Frames are anchored to the panel in order to maintain stable sizing of those elements.
- **Autocomplete Type Labels:** Add-entry search results now show a simple right-side type label, such as Spell, Aura, Equipment, or Item, making similar spell and aura entries easier to tell apart.
- **Cleaner Manual Adds:** The older Auto Add wizard and extra Manual Add/Add Entry button have been removed. Individual entries still use the add box, autocomplete, and arrow keys + Enter.
]],
        },
        ["1.20.1"] = {
            markdown = [[
## Polish | QoL

- **Live Tracked Aura Tooltips:** With Show Tooltips enabled, active tracked aura entries can now show Blizzard's live aura values, such as Ignite damage over time or Blazing Barrier absorb amount. Bar-mode icon hovers use the same aura-aware tooltip behavior.
- **Custom Bars List Ordering:** In Bars and Frames, the Custom Bars list now follows the layout preview order, making dragged bar positions easier to match with their settings.
- **First-Run Tutorial:** The tutorial now reflects same-class group sharing and folds the empty-panel guidance into the first ability step.
- **Addon Chat Messages:** Messages shown when adding transformed spells now use the same addon chat output style as the rest of Cooldown Companion.

## Bug Fixes

- **Deferred Cooldown Swipes:** Spells such as Nature's Swiftness and Tip the Scales should no longer flash an empty radial cooldown swipe while active and waiting for their real cooldown timer.
- **Charge Display Reliability:** Charge text color and icon desaturation return to the safer pre-Zenith-suppression behavior for charge-based abilities. The Zenith Stomp-specific suppression from 1.20 is backed out for now.
- **Zenith Stomp Follow-Up:** The Zenith Stomp suppression was reverted because it caused broader charge display issues. A safer Zenith Stomp-specific solution will be revisited in a future update.

## Performance

- **Bar Timer Text:** Bar-mode cooldown and aura timers, plus custom resource bar duration text, keep the same selected formatting while doing less background timer text work.
- **Timer Cleanup:** Timer labels now clear more reliably when bars are hidden, reused, or switch display modes.
]],
        },
        ["1.20"] = {
            markdown = [[
## New Features

- **Class-Wide Profile Controls:** Profiles now share more setup across same-class characters, instead of treating every character as a fully separate setup.
  - **Groups:** New groups default to the current class. Same-class alts share those class groups, while Browse Other Classes lets you preview off-class groups without making them active in normal play.
  - **Load Conditions:** Character, class, specialization, and hero talent filters are shown together. Character filters can still narrow visibility inside the class setup.
  - **Resource Bars:** Resource Bars, Resource Aura overlays, and Resource Bar Custom Bars now use one saved setup per class, so same-class characters can share the same bars.
  - **Update Resolver:** On update, if you have multiple same-class characters using the resource module, you will be prompted to pick a character whose setup will be inherited as the new class-wide setup.
  - **Resolver Details:** The kept setup provides the class Resource Bar settings and Resource Aura overlays; Custom Bars from the other same-class setups are preserved and merged into the class setup before the old character-specific Resource Bar copies are cleared.
- **Browse Other Classes:** Browse Other Characters has been expanded into a class browser built for the new class-wide setup model.
  - **Class Library:** Browse Other Classes opens as a class list. Pick a class to inspect that class's saved groups and folders without mixing them into your current class list.
  - **Selection-Based Previews:** Selecting an other-class panel can show a config-only preview of that panel and its parent container. The preview does not make the panel active in normal play and does not change saved data by itself.
  - **Hide Active:** The new Hide Active button can temporarily hide panels from your currently played character, making overlapping other-class layouts easier to inspect.

## Bug Fixes

- **Zenith Stomp Display:** Windwalker Monk Zenith entries now hide the base Zenith cooldown, charges, glow, texture effects, and sound alerts while Zenith Stomp replaces Zenith, then restore the normal Zenith display when the override ends.
]],
        },
        ["1.19.5"] = {
            markdown = [[
## Bug Fixes

- **Death Strike Tracking:** Blood Death Knights can add Death Strike as a normal spell entry again, without it turning into Coagulating Blood unless that aura is intentionally tracked.
- **Surging Totem Cooldowns:** Enhancement Shamans should no longer see Surging Totem as ready while its real cooldown is still running, including in Spell Custom Bars while the totem is active.
]],
        },
        ["1.19.4"] = {
            markdown = [[
## Bug Fixes

- **Timerless Active Auras:** Active auras with no visible duration, such as Sweeping Strikes, now keep their steady active-aura icon instead of briefly showing a cooldown swipe.
- **Unavailable Spell Entries:** Unknown, unlearned, or otherwise unavailable spells no longer stay in live displays or reserve attached-bar space just because their config panel is selected.
]],
        },
        ["1.19.3"] = {
            markdown = [[
## New Features

- **Assistant Panels:** A new Assistant Panel type can show the in-game rotation assistant's recommended next action as a simple locked icon. It supports the display behavior players expect from a cooldown icon while keeping setup focused and avoiding normal manual-entry controls.

## Other

- 12.0.7 ToC Update
]],
        },
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
    },
}

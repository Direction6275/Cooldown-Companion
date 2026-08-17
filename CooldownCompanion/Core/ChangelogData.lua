--[[
    CooldownCompanion - Core/ChangelogData.lua
    Repo-authored release notes bundled with the addon. Paste these same notes into the GitHub release body when publishing.
]]

local ADDON_NAME, ST = ...

ST._changelogData = {
    order = {
        "2.1",
        "2.0.1",
        "2.0",
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
        ["2.1"] = {
            markdown = [[
## New Features

- **Config redesign: one set of tabs for everything.** The separate Overrides tab is gone. Selecting an entry now turns the panel's own styling tabs into a view of that entry, so panel-wide settings and per-entry customizations live in the same place.
  - Settings that follow the panel appear grayed with a gold "Customize for this entry" button. Customized sections edit live and offer "Revert". Hovering a grayed control explains why it is locked.
  - A Customizations list at the top of each entry's Settings tab shows everything the entry customizes, with per-section Revert, Revert All, and links that jump straight to where each setting is edited.
  - **Copy Customization To...:** right-click an entry to copy one or all of its customizations to other entries. Compatible targets get a green ring in the Live Preview; click to apply, and keep clicking to spread the look across several entries, even on other panels.
  - The Visibility tab is now the home for everything that decides when an entry shows: Show & Hide Rules and Talent Conditions moved there under a Load Conditions heading. The entry Settings tab is leaner as a result.
  - Custom bars now use a single Settings tab with the same sections and order as panel entries, replacing their old four-tab cluster.
- **Aura Panels:** New Aura Icon and Aura Bar panel types show only the auras that are currently active, packed tightly in your configured order. Inactive auras take no space, so no more permanent gaps. A Collapse Direction setting controls whether the block packs from the start, the center, or the end, and it all works in combat.
- **New resource bars:** Icicles for Frost Mages, Tip of the Spear for Survival Hunters, and a Devourer Demon Hunter bar that tracks progress toward Void Metamorphosis, then becomes the Collapsing Star bar while transformed. All support the full resource kit, including segmented display and a max-stack border glow.
- **Stack threshold colors:** Aura-tracked entries can recolor their stack count at a chosen stack threshold, with an optional second color at max stacks. Works in combat on icons, bars, and custom bars.
- **Low Time Threshold:** Cooldown text can change to an alert color and/or show tenths (like `4.8`) below a chosen number of seconds, with an optional second, more urgent window (for example orange under 10, red under 3).
- **Centered growth:** Panels can now grow from the center. A partial last row sits centered under the full rows, and the panel's midpoint stays put as entries come and go, including Compact Mode repacking.
- **While Aura Active section:** One place on the Appearance tab now controls what the aura display does to a button, with a clear Cooldown dropdown: Hidden by Aura, Show Text, or Show Swipe and Text. Keeping the spell's cooldown swipe visible during the aura is back for the first time since 1.22, and old imports that used it recover the setting automatically.
- **Desaturate while aura active:** Aura-tracked entries can gray out their icon while the tracked aura is running, alongside the existing option for while it is missing.
- **Per-entry Pandemic:** The pandemic marker is now an Auto (Debuffs Only) / On / Off dropdown, and both the marker and the effect can be customized per entry.
- **Block bar upgrades:** Segmented stack bars gain a Segment Gap setting with five preset widths, and auras with up to 30 max stacks now render as blocks (the old cap was 20).

## Polish | QoL

- **Tracked Aura ID:** The Aura Tracking section now shows the spell ID of the aura an entry actually tracks (Moonfire shows the debuff's ID, not the cast spell's), so there is no guessing what an entry resolved to.
- **Hide unavailable entries from the preview:** A corner toggle on the panel preview hides unlearned or talent-gated entries and reflows the layout to what your current character actually sees. View-only and session-only; nothing saved changes.
- **Settings hide with their text:** Options that only affect a hidden text no longer clutter the config. Turn the text back on and they return exactly as configured.
- **Orientation switches keep your growth choice:** Changing a panel's orientation converts a centered growth direction to the new axis instead of dropping it.

## Bug Fixes

- **Cast bar survives talent changes:** The addon's cast bar no longer stays hidden after applying talents or switching specializations.
- **Aura tracking watches the right aura:** Track an Aura now follows the aura a spell actually applies, on the right unit. Fire Breath tracks its debuff on your target instead of the cast spell on you, and Shield of the Righteous tracks its buff on you. Aura suggestions in the add box now offer the applied aura directly.
- **Glows turn off when disabled:** Turning off Show Ready Glow removes the glow immediately instead of leaving it stuck until a reload. The same fix protects the proc glow, aura glow, and key press highlight.
- **Per-entry "off" now sticks:** Disabling a checkbox on a customized entry when the panel has it enabled (for example Flip Icon Side) now persists instead of silently reverting to the panel's setting.
]],
        },
        ["2.0.1"] = {
            markdown = [[
## Bug Fixes

- **Indirect target aura tracking:** Frost Mages can now add Freezing from Aura suggestions when Shatter is available. Other player-applied harmful auras that are not directly castable can be added by entering their exact spell ID.
- **No stale cooldown numbers:** Ready icons no longer retain old countdowns after config changes or cooldown previews. Real cooldown, charge-recharge, displayed GCD, and preview timers remain visible while active.
- **Reliable cast bar ownership:** The Blizzard player cast bar remains hidden whenever Cooldown Companion's cast bar is enabled, even after Edit Mode changes or overlay transitions. The talent-change progress bar still appears, and disabling Cooldown Companion's cast bar restores an active Blizzard contextual overlay.
- **Player-owned target debuffs:** Harmful target aura trackers no longer activate for the same debuff applied by another group member. Helpful aura tracking on yourself or group members is unchanged.
- **Combat-safe aura displays:** Aura displays continue updating through combat instead of freezing. Changes requested while aura access is restricted wait safely and apply after combat ends.
- **Correct aura state in vehicles:** Aura icons, bars, texture panels, and custom aura bars no longer all appear active from an unrelated aura when vehicle or unit reaction changes. Groups hidden for Vehicle / Override UI also now recognize vehicle occupancy even without a vehicle action bar.

## Performance

- **Smoother panel configuration:** Selecting entries and adjusting settings now causes fewer unnecessary updates to gameplay displays, reducing short stutters. Changes still appear immediately in Live Preview and apply to gameplay displays when you finish the interaction.
- **Faster Arrange Mode exit:** Finishing Arrange Mode now uses one combined layout refresh, reducing the noticeable pause on larger profiles.
]],
        },
        ["2.0"] = {
            markdown = [[
## Cooldown Companion 2.0

Cooldown Companion 2.0 is the 12.1 release, and it is the largest update the addon has ever shipped. The settings interface has been redesigned from scratch, aura tracking has been rebuilt on a new foundation, and layout editing is completely new. One goal drove virtually every interface decision: make the addon more approachable and intuitive. Your displays themselves should still look and behave the way you remember. Existing profiles migrate automatically, but export a backup before updating.

## The 12.1 Rework

### The aura rebuild

- **Why everything aura changed:** 12.1 tightened addon security, and auras were the main target. Blizzard's reasoning: just knowing an aura appeared is enough for an addon to detect a combat event and automate a decision around it. So while you are in combat, in an encounter, in Mythic+, or in a PvP match, the game no longer answers addon questions about auras at all. No addon can ask what auras a unit has, how much time is left on one, or how many stacks it is at. Instead, Blizzard provides new display building blocks: the addon builds and styles the display and declares what it should track, and the game itself fills in the icon, timer, and stacks and decides when it appears. The addon can never read back what its own display is showing; even asking whether one of its own aura icons is currently visible returns a value it is not allowed to look at.
- **Aura tracking, rebuilt from the ground up:** Cooldown Companion's aura tracking is rebuilt on those building blocks, so every aura display keeps working and always agrees with the game. The trade shows up all through this changelog as one rule: showing aura state works, reacting to it does not. That is why features like glowing while an aura is missing, hiding while it is active, stack-reactive effects, and live tooltip values are gone; Changed & Removed below covers each one. Tracking is also narrower by design: an entry tracks your own buffs on yourself (or your group, see below) or your own debuffs on your target, and never a mix of buffs and debuffs. The rebuild also upgraded what these systems can do:
  - **Aura glow styles:** Active auras can now glow with Solid, Pulse, Color Shift, Dashes, Ants, Proc, or Overlay styles, each with its own controls.
  - **Pandemic visuals:** Pandemic display now uses the game's own pandemic timing, with one Pandemic section in the config covering the glow, the bar marker, and the duration-text marker.
  - **Smarter aura search:** Autocomplete and typed names now resolve to the aura a spell actually applies, so entries like Rake find the debuff instead of the ability.
  - **Aura sounds:** Sound alerts now play through the game's native aura sound system and can fire on aura applied, stack gained, and removed.
  - **No more Cooldown Manager dependency:** Aura tracking no longer relies on Blizzard's Cooldown Manager in any way. You can disable the Cooldown Manager entirely in Blizzard's settings and keep full addon functionality.
  - **Snappier aura displays:** The old system needed layers of addon work to keep aura displays feeling responsive; the game now drives them directly. Target-based auras no longer have any update delay, so switching targets shows the right auras instantly.
### The interface redesign

- **A brand-new settings window:** The configuration interface has been redesigned end to end. A searchable Navigator tree on the left replaces the old column layout, and everything is edited in one wide workspace with a Live Preview at the top and settings laid out in clean two-column rows below.
  - **Edit from the preview:** Click an entry in the Live Preview to select it, drag entries to reorder them, and watch every setting apply to the preview as you change it. Previews never touch your real displays.
  - **Visibility, in one place:** Load Conditions mixed two different ideas under a name that suggested neither. It is now a Visibility tab split into two plain questions, who can use this and where to hide it, with the panel's Alpha settings moved in alongside.
  - **One home for bars:** Resource Bars, Cast Bar, and Unit Frames now live in a single Bars & Frames workspace with the same preview-first editing.
  - **Panels are created from the group overview:** Selecting a group shows a preview of all its panels, and new panels are created right there from panel-type cards.
  - **One Import and Export:** All of the scattered import and export buttons are consolidated into single Import and Export modes that handle profiles, groups, panels, Custom Bars, and Resources.
- **Unlocking and arranging, redone:** Unlocking your layout now opens a full arrange mode with drag snapping, edge resizing, one-pixel nudging, and live coordinates. Escape or the Cancel button reverts every move you have not yet saved (locking a frame saves its position), the minimap button toggles arrange mode with a right-click, and the config shows clear locked/unlocked state at all times.

## New Features

- **Track a buff on your group:** Buff entries have a new Track on Group Members option for spells like Lifebloom that usually sit on someone else. It tracks your own casts across your party or raid, with the same 12.1 limits as everything else: it cannot tell you who has the buff, and if several people have it at once the displays overlap.
- **Entry pings:** Turn on Allow Pings for a panel and its entries answer the ping keybind exactly like Blizzard's Cooldown Manager, letting you ping your cooldowns to your group. Spell entries ping; aura entries stay quiet, matching what Blizzard pings in the Cooldown Manager.
- **Spellbook window:** A compact spellbook side window lists your known spells so you can drag them straight into panels while configuring.
- **Icon Zoom:** Icons, bar icons, the cast bar icon, and trigger icon displays now offer a WeakAuras-style zoom that crops the icon's borders.
- **Duration Format:** One Duration Format setting now controls how both cooldown countdowns and aura duration text are written, per panel.
- **Custom Icon Strata:** The icon layering editor now exposes eight real, reorderable layers. Put Cooldown Swipe above Aura Display to keep a spell's own cooldown visible while its aura runs.
- **Text panel redesign:** Text panels now size themselves automatically from their font and content, with a Padding control, and formats are edited in a live in-config editor instead of a popup.
- **Resource bar aura borders and stack lane:** Resource aura tracking can now draw a whole-bar border and an independent stack lane, each with its own toggle and color.
- **Maelstrom Weapon stack shapes:** Maelstrom Weapon's stack display now offers three shapes: the classic overlay, one segment per stack, or a single continuous bar.
- **Group multi-select actions:** Groups now support batch actions from the group list, including enable, disable, duplicate, and delete across many panels at once.
- **Tooltip controls:** Tooltips now have position options and a hide-in-combat setting.
- **Per-panel auto-anchoring control:** Individual panels can now be included in or excluded from resource bar, cast bar, and unit frame auto-anchoring.

## Polish | QoL

- **Preview command center:** All config previews (glows, conditional visuals, health effects, casts, and more) are grouped into one picker with a play/stop button on the Live Preview.
- **Browse Other Classes, full workspace:** Browsing another class now opens the same full editing workspace as your own class instead of a limited read-only view.
- **Segmented stack bars restyled:** Each stack block now draws its own border ring in place of the bar's single outer ring and background, so stacks read as separate blocks.
- **Panel orientation sticks per mode:** Icon, bar, and text panels each remember their own horizontal or vertical arrangement, and switching display modes no longer resets a panel to vertical. Existing panels keep their current layout on update.
- **Adding entries keeps single-line panels single-line:** When a panel shows one full row or column, adding entries now widens the line instead of starting a surprise second row. Deliberately wrapped panels are untouched.
- **UI skin friendly:** Addon skins such as ElvUI can now style the config window's checkboxes and sliders, and a skinned settings pane keeps its own colors.
- **The config window remembers itself:** Window size and position persist between sessions, the preview/settings split is draggable, and double-clicking the resize grip resets it.
- **Clickable breadcrumbs:** Every ancestor in the Editing breadcrumb is clickable for fast navigation back up.
- **Color pickers save on close:** Color changes apply live while you drag and save when the picker closes, so previews and undo behave predictably.
- **Slider input polish:** Typed slider values snap to the slider's step, and mouse-wheel edits apply to the live display immediately.
- **Clearer preview tooltips:** Preview entries spell out their status (hidden, unavailable, overridden) instead of leaving you guessing.

## Changed & Removed

12.1 aura restrictions (Blizzard-imposed; no addon can work around these):

- **Aura tracking is player-and-target only:** An aura entry tracks your own buffs on yourself or your own debuffs on your current target. Tracking auras on arbitrary units, or auras cast by other players, is no longer possible for any addon. This also means debuffs that enemies put on you cannot be tracked; the game hides which debuffs you have from every addon. Existing entries are converted automatically based on whether the aura is a buff or a debuff. Custom bars follow the same rule: the manual tracked-unit picker is gone, and any saved unit choice switches to automatic on update.
- **Buffs or debuffs, never both:** An entry tracks buffs or debuffs, never a mixed list. Mixed lists from old profiles keep whichever side had more auras.
- **Live aura tooltip values are gone:** Tooltips on active tracked auras can no longer show live values such as Ignite's damage or Blazing Barrier's absorb. The game no longer shares that live aura data with addons; entries show the normal spell tooltip instead.
- **Trigger panels no longer take aura conditions:** Aura conditions on trigger panels have been retired. Saved aura conditions stay in your profile but never count as met, so a trigger relying on one will not fire until you reconfigure it.
- **Hide While Aura Active is gone:** 12.1 gives addons no allowed way to hide an entry only while its aura is running, so Hide While Aura Active and its Except in Pandemic variant are removed everywhere, including custom bars. The settings are cleared on update and those entries stay visible.
- **Aura glows only show while the aura is active:** Glowing while an aura is missing and combat-only glows cannot run on the protected aura display, so the Show When Missing and Show Only In Combat glow options are removed on update. The same qualifiers on Texture panel aura effects are removed for the same reason; those effects keep their chosen style, color, and speed.
- **The Icon Fill Timer no longer fills for auras:** The fill has to know how much time is left in order to animate, and the game no longer shares that, so the Icon Fill Timer now runs for cooldowns only. Its Aura Fill Color setting is removed and cleared on update. The aura's own duration text and swipe still show the time remaining.
- **Stack effects that react to the count are removed:** Stack counts are protected values in combat, so the features that read them are gone: the Overlay stack display (existing bars convert to Segmented), the Max Stack Color and threshold colors, the Max Stack Indicator glow, pulse, and color shift, the Stack Text Format choice, and the manual Max Stacks value. This applies to panel entries and custom bars alike; the maximum now comes from the game's spell data.
- **The {?pandemic} text tag is retired:** Pandemic state can no longer be read by addons, so custom text formats cannot branch on it. Saved formats that used the tag are rewritten automatically; the duration-text pandemic marker replaces it.
- **Aura sounds are sound files only:** The addon can no longer hear aura changes, so it cannot play its own sounds anymore; each sound is registered with the game up front and the game plays it, and the game only accepts actual sound files. Aura sound choices that used a built-in Blizzard sound or text-to-speech are cleared on update and need re-picking from file-based sounds.
- **Hidden aura entries reserve their slot:** In Compact Mode, an aura entry that is hidden still holds its layout position. The addon is never told whether an aura is active, so it cannot know a gap opened up, let alone close it mid-combat. Every other hide rule reflows normally; only aura entries hold their space.
- **Dracthyr Soar counts as a regular mount while auras are restricted:** Soar is a buff, and the addon cannot see buffs in combat, encounters, Mythic+, or PvP. In those situations the Regular Mount alpha rule applies instead of the Skyriding one. It corrects itself as soon as auras are readable again.
- **Hide-when-inactive aura bars live in buckets:** Aura custom bars that hide while inactive now collapse through the game's own aura containers, grouped into a player bucket and a target bucket on each side of the resource bar. Bars order freely inside their bucket, a swap control flips which bucket comes first, and an empty bucket can leave a small gap the addon cannot close, because aura state is secret. New aura entries now default to hiding while inactive.

Other changes on update:

- **Folders are retired:** The new Navigator tree took over the organizing job folders used to do, so the folder level above groups is gone. On update, the groups inside each folder move to the top level of the list in the folder's place, keeping their order, and folder-level visibility rules (spec, hero talent, class, character, load conditions) are applied directly to those groups so nothing loads differently. No group is created for the folder itself, so that layer of organization is lost.
- **Adding an entry asks Spell or Aura:** The addon no longer guesses what you meant. New entries always state whether they track the spell's cooldown or the aura it applies, the autocomplete labels each result, and suggestions only offer what can actually work under the 12.1 rules. The rule of thumb the suggestions follow: if it can appear as a buff on you, or it is yours, you can track it. Existing entries keep their converted behavior.
- **Cooldown swipe edge is off by default:** The 12.1 client draws the swipe edge detached from the swipe, and Blizzard's own cooldowns ship with it off. All existing panels flip to edge-off once on update; you can re-enable it per display in the swipe advanced settings.
- **Glows use a new engine:** The LibCustomGlow library is retired; glows are now drawn by Cooldown Companion's own engine. Autocast Shine survives as an addon-rendered style, and the separate Action Button Glow choice merges into the standard Glow. Existing glow settings convert to the closest new style; minor visual differences are possible.
- **Resource aura overlays are borders now:** The old Resource Aura Overlay recolored the bar while the tracked aura ran. That is no longer possible: under the new aura system the addon cannot tell when the aura is active, so it cannot change the bar's own fill color. The only aura-driven look left was covering the whole bar with a translucent wash, which hurt readability, so the overlay now draws an Aura Border around the whole bar instead, in Solid Border or Pixel Glow styles. Your existing overlay settings and color carry over automatically and keep working in combat. The stack lane's maximum now comes from the game's spell data rather than a manual setting.
- **The cast bar is now Cooldown Companion's own:** Blizzard's player cast bar can no longer anchor into the new aura displays, so the addon now draws its own cast bar and hides Blizzard's while the feature is on. It still steps aside for Blizzard's special cast bars, such as crafting and talent commits, and it now always sits at the end of its side of the bar stack instead of at a saved position in the order. The old Enable Cast Bar Styling switch is retired; styling lives behind the Appearance tab's enable toggle.
- **The Hide Cooldown Manager toggle is removed:** Cooldown Companion no longer offers hiding Blizzard's Cooldown Manager. If you hid it through the addon, it will be visible again; use Blizzard's own Edit Mode and settings to manage it. Since aura tracking no longer depends on the Cooldown Manager, disabling it there is completely safe.
- **Custom Icon Strata orders reset:** The layer set changed from six entries to eight real ones, so saved custom layer orders no longer apply and the Custom Icon Strata checkbox turns off.
- **Text panels size themselves:** The manual Width and Height sliders are gone. Custom sizes from old profiles are recalculated automatically.
- **Bar aura effects are border styles now:** The bar Active Aura effect is limited to border styles. Old fill-style choices convert to the closest border style (Pixel becomes Dashes, glow-type fills become Pulse).
- **Dim Instead Of Hide:** The old Use Baseline Alpha Fallback options under the Hide While rules are now called Dim Instead Of Hide (Dim While Aura Inactive for aura entries) and dim at one consistent strength instead of the group's baseline alpha.
- **Middle-click locking is retired:** Middle-click was an undiscoverable second way to lock that behaved differently depending on where you clicked. Use arrange mode, the minimap button, or `/cdc lock`, which now toggles.
- **Slash commands trimmed:** `/cdc bars`, `/cdc frames`, and `/cdc buttons` are retired; the redesigned config makes them unnecessary.
- **Entry reordering is drag-only:** The old reorder menu actions are gone; drag entries in the Live Preview instead.
- **Item fallbacks come from the add box only:** You can no longer set an item fallback by dropping an item from your bags. Use the add box and autocomplete instead.
- **Eclipse is no longer special:** Nothing in the game's data connects the Eclipse ability to its Solar and Lunar buffs, and the built-in exception that papered over that gap aged badly. Druid Eclipse now presents like everything else: one spell entry, plus its two buffs as ordinary aura entries.

## Bug Fixes

- **Rotation Assistant icons show the right state again:** When the recommended action briefly disappeared and came back, the icon could return bright and untinted even though the ability was unusable, because the reset left the addon believing the icon was already dimmed. Dimming and tint now clear properly, so a returning recommendation always draws its real state.

## Profile Compatibility

- **Automatic migration:** Existing profiles migrate automatically on first login, including the folder flattening and every aura conversion above. The addon prints one-time chat notices listing settings it had to adjust or drop; a few documented changes, like the swipe edge default and the Custom Icon Strata reset, happen without a notice. Exporting a profile backup before updating is strongly recommended.
- **1.15 checkpoint unchanged:** Import strings and backups must still have passed through the 1.15 compatibility checkpoint. Strings older than that continue to show recovery guidance.
]],
        },
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

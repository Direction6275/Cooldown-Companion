--[[
    CooldownCompanion - Core/ChangelogData.lua
    Repo-authored release notes bundled with the addon. Paste these same notes into the GitHub release body when publishing.
]]

local ADDON_NAME, ST = ...

ST._changelogData = {
    order = {
        "1.10.27",
        "1.10.26",
        "1.10.25",
    },
    entries = {
        ["1.10.27"] = {
            markdown = [[
## New Features

- **Built-in changelog viewer:** You can now open bundled release notes directly from the config panel, browse older versions, and adjust the viewer text size for easier reading.

## Polish | QoL

- **Aura unit selection for tracked spells:** Aura-tracked spells can now explicitly watch either your Player or Target auras, making buff and debuff tracking easier to set up when the default target is not the one you want.
  - *Please double-check any entries that attach auras to spells to make sure the selected target is correct. This change was needed to help protect aura tracking from reading the wrong duration.*

- **Clearer aura tracking setup:** Aura tracking now gives more direct active or inactive feedback, clearer guidance when Blizzard Cooldown Manager setup is missing, and cleaner labels in the spell settings panel.

- **Whirling Dragon Punch fix:** Whirling Dragon Punch now supports the unusable-state toggle so it can follow the same visibility and dimming rules as other supported buttons.

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

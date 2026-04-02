--[[
    CooldownCompanion - Core/ChangelogData.lua
    Repo-authored release notes bundled with the addon. Paste these same notes into the GitHub release body when publishing.
]]

local ADDON_NAME, ST = ...

ST._changelogData = {
    order = {
        "1.10.26",
        "1.10.25",
    },
    entries = {
        ["1.10.26"] = {
            markdown = [[
## Bug Fixes

- Fixed false cooldown states after empowered casts: Spells should no longer briefly dim, hide, or act like they are on cooldown when an empowered cast is released and enters its recovery window.
- Fixed config help tooltip taint errors: Hovering info buttons in the config should now avoid the tooltip sizing taint errors that could fire while reading help text.
]],
        },
        ["1.10.25"] = {
            markdown = [[
## New Features

- Animated custom aura bar indicators: Custom aura bars can now show when an aura is active or in pandemic range, with optional pulse and color-shift effects to make those states easier to spot at a glance.
- Multiline text panels: Text panel formats can now span multiple lines, including a line break token in the format editor so you can build stacked text layouts more easily.

## Polish | QoL

- Better bar effect previews: Active-aura and pandemic preview buttons now give a fuller, more reliable preview of custom aura bar effects at both the group and per-button level.

## Bug Fixes

- Fixed multiline text sizing: Multiline text panels and per-button multiline overrides now size themselves more reliably, reducing clipping and layout issues.
- Fixed aura-only status text edge cases: Aura-only text displays now report timeless buffs more cleanly and handle combat aura timers with more reliable sizing and classification.
]],
        },
    },
}

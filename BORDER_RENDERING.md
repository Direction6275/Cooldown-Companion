# Border Thickness Modes

Cooldown Companion supports two border thickness modes:

- `custom`: preserves the existing UI-unit border thickness behavior, including fractional values from `0.1`-step sliders.
- `crisp`: the internal value for the user-facing `One-pixel` option, which renders the border as one physical pixel using Blizzard `PixelUtil`.

The shared implementation lives in `Core/Utils.lua`. Runtime and preview callers should use the CC helpers there instead of adding local pixel conversion math.

## Profile-Wide One-Pixel Mode

Profiles can enable a global one-pixel border mode from the config panel's gear menu. This mode is an effective render override, not a settings rewrite:

- Local border mode, size, style, and color settings stay saved as-is.
- Runtime frames and matching config previews should ask for the effective border mode or effective layout size.
- Turning the profile mode off restores the local `custom` or local `crisp` behavior already saved on each surface.
- Border thickness controls are locked while the profile mode is active, but border style and border color controls remain editable.

The profile override only changes thickness for borders that are already visible. Callers must keep their existing visibility gates, including `borderStyle = "none"` and custom-size `0` hidden-border behavior.

## Audit Checklist

- One-pixel borders call Blizzard `PixelUtil` through `Core/Utils.lua`.
- Runtime and preview callers use effective helpers when profile-wide one-pixel mode should apply.
- Custom thickness remains a separate path and keeps existing `borderSize` values as UI-unit thickness.
- Missing render-mode settings resolve to `custom`, so existing profiles are not reinterpreted.
- Profile-wide one-pixel mode does not overwrite local border settings or force hidden borders visible.
- The code does not add a custom UI scale multiplier or a general layout toolkit.
- Feature text should describe this as an optional one-pixel border thickness mode, not as a broad UI scaling system.

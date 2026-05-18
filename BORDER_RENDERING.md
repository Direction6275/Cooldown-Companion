# Border Rendering

Cooldown Companion supports two border rendering modes:

- `custom`: preserves the existing UI-unit border thickness behavior, including fractional values from `0.1`-step sliders.
- `crisp`: renders the border as one physical pixel using Blizzard `PixelUtil`.

The shared implementation lives in `Core/Utils.lua`. Runtime and preview callers should use the CC helpers there instead of adding local pixel conversion math.

## Audit Checklist

- Crisp borders call Blizzard `PixelUtil` through `Core/Utils.lua`.
- Custom thickness remains a separate path and keeps existing `borderSize` values as UI-unit thickness.
- Missing render-mode settings resolve to `custom`, so existing profiles are not reinterpreted.
- The code does not add a custom UI scale multiplier or a general layout toolkit.
- Feature text should describe this as an optional crisp one-pixel border mode, not as a broad UI scaling system.

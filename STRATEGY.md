---
name: Cooldown Companion
last_updated: 2026-05-28
---

# Cooldown Companion Strategy

## Target problem

Players are trying to create personalized, intuitive tracking displays, but Blizzard's baseline UI is limited and does not offer enough customization.

## Our approach

Cooldown Companion makes deep tracking customization feel organic and intuitive through a carefully shaped config experience. It says no to extremely niche options and UI noise unless the choice is broadly useful and can fit coherently into the setup flow; the final tracking display is the result of that seamless configuration experience.

## Who it's for

**Primary:** UI-focused WoW players - They're hiring Cooldown Companion to build a personalized combat tracking display without fighting the config to do it.

## Key metrics

- **Config clarity feedback** - Players describe the config as clear, intuitive, or easier than alternatives; measured through reviews, direct feedback, and support conversations.
- **High-level personal fit** - The addon keeps feeling satisfying in top-level personal play because the setup and display feel right; measured through the maintainer's own use.
- **Negative feedback quality** - Negative feedback clusters around fixable specifics, not broad confusion or overwhelm; measured through reviews, comments, and user reports.
- **Customization coherence** - New customization features can be added without making the config feel cluttered; measured during design, review, and maintainer use.
- **Idea-to-display friction** - Users can get from an intended tracking idea to a working display without needing lots of explanation; measured through feedback and support burden.

## Tracks

### Config experience

UI clarity and intuitive setup for players who want deep customization without fighting the addon.

_Why it serves the approach:_ The config experience is the core product experience; the display is the result of getting that flow right.

### API health

Keeping up with Blizzard API changes, understanding what information the API can expose, and integrating cleanly with systems like post-12.0 secret values.

_Why it serves the approach:_ Reliable customization depends on respecting the real data and restrictions Blizzard exposes instead of building fragile behavior around assumptions.

### Scope discipline

Keeping the project focused on the tracking and customization work it is meant to do well.

_Why it serves the approach:_ Avoiding niche options and UI noise keeps the addon coherent for the vast majority of users.

## Milestones

- **2026-03-02** - Initial Cooldown Companion release aligned with World of Warcraft: Midnight launch.

## Not working on

- Cooldown Companion will not shape its core strategy around exploiting inconsistent non-secret aura availability. Where Blizzard's secret-value boundaries are fragile or likely to change, the addon should integrate conservatively instead of building major product direction on unstable exceptions.

## Marketing

**One-liner:** Cooldown Companion should be the best option for tracking in-combat information for your character.

# Rotapop

**Rotapop** is a new WoW Addon — a Hekili-style rotation helper rebuilt for **Patch 12.x** of World of Warcraft.

## Why Rotapop?

The original Hekili worked up to **Patch 11.2.5**. Starting with **12.0.x**, it became non-functional because Blizzard:

- Removed or changed classic Cooldown APIs
- Switched the internal cooldown system to a **category-based** model
- Introduced **structured return values** (`SpellCooldownInfo`)
- Added **restriction mechanics**

However, private addons continue to display SimC-based priorities correctly — the necessary data is still available in the client.

## Goal

Rotapop uses the **new Cooldown-Manager** (introduced in 11.1.5) as its **primary state source**.

- Not a workaround
- Not an API wrapper
- Direct usage of the new cooldown system

## Core Concept

The old Hekili used a spell-centric cooldown model. Since 11.1.5, the client manages cooldowns:

- **Category-specific**
- Via internal **cooldown tables**
- With structured **SpellCooldownInfo** objects

Rotapop reads and evaluates this new cooldown state model:

- Cooldown states are derived from the new system, not reconstructed from individual spell queries
- Shared cooldowns are correctly represented
- Start-recovery and GCD are properly accounted for

## What Stays the Same

- SimC priority logic
- APL structure
- Resource calculations
- Charge simulation

Only the **state retrieval** is adapted to the new Cooldown model.

## Architecture

| Module                              | Purpose                                                       |
|-------------------------------------|---------------------------------------------------------------|
| `Rotapop.lua`                       | Entry point, initial lookup build on PLAYER_LOGIN             |
| `Core/EventBus.lua`                 | Centralized event dispatching, decouples modules              |
| `Core/CooldownAdapter.lua`          | C_CooldownViewer as primary source, C_Spell fallback          |
| `Core/StateCache.lua`               | Event-driven cache over CooldownAdapter                       |
| `Engine/SimEngine.lua`              | APL priority engine with RegisterAction API                   |
| `Engine/APL/ShamanEnhancement.lua`  | Enhancement Shaman APL (SimC port)                            |
| `UI/NextSpellDisplay.lua`           | Next-spell icon with cooldown overlay                         |
| `UI/DebugOverlay.lua`               | Dev-only debug overlay for tracked spell states               |

## No-Legacy Policy

- **No** dependency on legacy global APIs (`GetSpellCooldown`, etc.)
- Fallbacks use only documented `C_*` namespace APIs
- Every data-field usage is documented with a reference to the API page

## Confirmed APIs (Patch 12.x)

| API / Structure | Reference |
|---|---|
| `C_Spell.GetSpellCooldown(spellID)` | [Docs](https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCooldown) |
| `C_Spell.GetSpellCharges(spellID)` | [Docs](https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellCharges) |
| `C_Spell.IsSpellUsable(spellID)` | [Docs](https://warcraft.wiki.gg/wiki/API_C_Spell.IsSpellUsable) |
| `C_Spell.GetSpellInfo(spellID)` | [Docs](https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellInfo) |
| `C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)` | [Docs](https://warcraft.wiki.gg/wiki/API_C_CooldownViewer.GetCooldownViewerCooldownInfo) |
| `SpellCooldownInfo` struct | [Docs](https://warcraft.wiki.gg/wiki/Struct_SpellCooldownInfo) |
| `SPELL_UPDATE_COOLDOWN` event | [Docs](https://warcraft.wiki.gg/wiki/SPELL_UPDATE_COOLDOWN) |
| `SPELL_UPDATE_CHARGES` event | [Docs](https://warcraft.wiki.gg/wiki/SPELL_UPDATE_CHARGES) |

## Relevant Patch Documentation

- [Patch 11.1.5 API Changes](https://warcraft.wiki.gg/wiki/Patch_11.1.5/API_changes)
- [Patch 12.0.0 API Changes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)

## Result

Rotapop will:

- Run stably under **Patch 12.x**
- Display **SimC next-spell** recommendations
- Functionally replace Hekili
- Fully leverage the **new Cooldown-Manager model**

No hybrid solutions. No legacy calls. Full adaptation to the new system.

# Rebuilding Runeterra Forge in Unity

This guide explains how to rebuild **all** of Runeterra Forge in Unity. Runeterra Forge is currently a Godot 4.6 project written in GDScript.
It is based on a complete read of every tracked script and scene in this repository (`project.godot`, `Scripts/*.gd`, `Scenes/*.tscn`, `Materials/*`, and the asset folders).

> **How to read "Unity 3D".** "Unity 3D" here means the engine. The Godot project is **2D**: it uses `Node2D` and `CanvasLayer`, a 1920×1080 viewport, and `canvas_items` stretch.
> The main path in this guide is therefore a **faithful 1:1 port**: Unity with URP, a 2D renderer, and an orthographic camera. It reproduces the game exactly.
> [Appendix A](#appendix-a--optional-true-3d-presentation) covers an optional 3D presentation: a perspective board, cards as quads, and real rotation flips. Build that only after the logic is at parity.

---

## Table of contents

1. [What the game is](#1-what-the-game-is)
2. [Recommended Unity setup](#2-recommended-unity-setup)
3. [Godot → Unity concept mapping](#3-godot--unity-concept-mapping)
4. [File-by-file port map](#4-file-by-file-port-map)
5. [Target Unity project layout](#5-target-unity-project-layout)
6. [Data layer (cards, lanes, keywords, vocab)](#6-data-layer)
7. [Coordinates, scales, and board geometry](#7-coordinates-scales-and-board-geometry)
8. [Card prefabs, visuals, text formatting, shaders, animations](#8-card-prefabs-and-visuals)
9. [Game flow: exact phase ordering](#9-game-flow-exact-phase-ordering)
10. [CardManager: play, drag, undo, resolve, trackers](#10-cardmanager)
11. [Ability system (AbilityResolver)](#11-ability-system)
12. [Level-up system (LevelUpManager)](#12-level-up-system)
13. [Aura system](#13-aura-system)
14. [Lanes (LaneManager), Swap Lane, Stun, Deep](#14-lanes-swap-lane-stun-deep)
15. [Determinism and RNG](#15-determinism-and-rng)
16. [Async model: replacing `await`](#16-async-model)
17. [Networking](#17-networking)
18. [Bot (offline opponent)](#18-bot)
19. [Menus and UI scenes](#19-menus-and-ui-scenes)
20. [Asset pipeline](#20-asset-pipeline)
21. [Current state of the source: what is *not* implemented](#21-current-state-of-the-source)
22. [Milestones and parity test plan](#22-milestones-and-parity-test-plan)
- [Appendix A: Optional true-3D presentation](#appendix-a--optional-true-3d-presentation)
- [Appendix B: Gotcha checklist](#appendix-b--gotcha-checklist)

---

## 1. What the game is

Runeterra Forge is a **two-player, simultaneous-turn, 3-lane card game**. Its rules resemble *Marvel Snap*, and its cards and art come from *Legends of Runeterra*.

- **6 global turns** (`GameManager.max_turns = 6`). Both players act during the same PLAY phase.
- **Mana:** base max mana equals the turn number, and it refills every turn. Temporary bonus mana (Ice Pillar) applies on the *next* turn only.
- **Board:** 3 lanes (columns) × 2 sides (rows). Each side of a lane is a **zone** with **4 slots** in a 2×2 grid. Each player also has a separate **spell zone** of 4 slots.
- **Hand/deck:** the starting hand is 3 cards, you draw 1 per turn, and the deck holds 12 cards. The deck in a match is currently hardcoded in `Deck.gd`.
- **Phases per turn:** `ROUND_START → PLAY → SWAP_LANE → RESOLVE → ROUND_END`.
  - Cards played during PLAY are **face-down** until RESOLVE.
  - During RESOLVE they flip one at a time. The player with **priority** ("flip first") goes first.
- **Winning:** win 2 of 3 lanes by total Power. If lanes are tied, total Power across all lanes decides. If that is also equal, the game is a tie.
- **Priority:** after each round, the player winning more lanes gets flip-first. Ties fall back to total Power, then to random.
- **Champions level up** (1 → 2 → 3) when a condition is met. The card flies to screen centre, spins, and changes art. After that, every copy of the champion (hand, deck, board) is upgraded.
- **Lanes** are random environment cards: Hexcore Foundry, Ornn's Forge, Sunken Temple, Noxkraya Arena, and Rockfall Path. The left lane is revealed at the start, the middle lane on turn 2, and the right lane on turn 3.
- **Modes:**
  - online 1v1 over ENet (host, or join by IP on port 9999);
  - offline against a simple bot.
- **Menus:** Home (Play, Deck Builder, Card Catalog), plus the in-game Lobby, Settings, Card Preview and Lane Preview overlays.

---

## 2. Recommended Unity setup

| Godot setting (`project.godot`) | Unity equivalent |
|---|---|
| Godot 4.6, Forward Plus | Unity 6 (6000.x) LTS with **URP** (2D Renderer) |
| `window/size` 1920×1080 | Game view 1920×1080. Player Settings default resolution 1920×1080 |
| `stretch/mode = canvas_items` | Orthographic camera `orthographicSize = 5.4` (1080 px / 100 PPU / 2). uGUI `CanvasScaler` = *Scale With Screen Size*, reference 1920×1080, match 0.5 |
| `viewport/hdr_2d = true` + `WorldEnvironment` glow | URP Asset: HDR on. Global Volume with **Bloom** (the level-up `PointLight2D` sweep relies on glow) |
| `physics/3d = Jolt` | Irrelevant (no 3D physics). Use **Physics2D** only for point queries |
| `rendering_device/driver.windows = d3d12` | Player Settings → Graphics APIs → D3D12 (or leave D3D11) |
| Autoloads (8 singletons) | See §3: bootstrap services |
| `run/main_scene = HomeScreen.tscn` | Build Settings scene 0 = `HomeScreen` |
| `export_presets.cfg` "Windows Desktop", company *TheAnyDev*, product *RuneterraForge* | Player Settings: Company Name `TheAnyDev`, Product Name `RuneterraForge`, target Windows x64 |

**Packages to install:**

| Package | Why |
|---|---|
| `com.unity.render-pipelines.universal` | 2D renderer, Light2D, Bloom |
| `com.unity.textmeshpro` (built into uGUI in Unity 6) | Replaces `RichTextLabel` BBCode |
| **UniTask** (`com.cysharp.unitask`) *or* Unity 6 `Awaitable` | Replaces GDScript `await` with value-returning async (see §16) |
| **DOTween** (optional) | Replaces `create_tween()` chains. Plain UniTask lerps also work |
| **Netcode for GameObjects** + **Unity Transport** (or **Mirror** / **FishNet**) | Replaces `ENetMultiplayerPeer` and `@rpc` (see §17) |
| `com.unity.nuget.newtonsoft-json` | Loading card/lane JSON and saved decks |

---

## 3. Godot → Unity concept mapping

| Godot | Unity | Notes for this project |
|---|---|---|
| **Autoload** singleton (`DeckManager`, `AbilityResolver`, `LevelUpManager`, `AuraSystem`, `LaneManager`, `SwapLaneManager`, `StunManager`, `BotManager`) | Plain C# service classes owned by a `GameServices` bootstrap. Use a `DontDestroyOnLoad` object, or static instances created by `[RuntimeInitializeOnLoadMethod]` | `DeckManager` must survive scene changes (Home ↔ DeckBuilder ↔ Main). The other seven hold **per-match state** (`StunManager._stun_entries`, `SwapLaneManager.swap_history`, `LaneManager._revealed`) and must be **reset per match**. The Godot code never resets most of them because the Main scene is only loaded once |
| `get_node_or_null("/root/Main/CardManager")` path lookups | An injected `MatchContext` (Board, CardManager, GameManager, Deck, PlayerHand, NetworkManager) that `Main` registers in `Awake` | Every service does these lookups. Keep a null-safe accessor, because preview cards live outside Main |
| `class_name CardDatabase` + `const CARDS = {...}` | **JSON in `StreamingAssets` or `Resources`**, deserialized into `CardData` classes. ScriptableObjects are an alternative | See §6. Keep string IDs (`"Azir1"`), because gameplay compares IDs and names everywhere |
| `signal` / `emit_signal` / `.connect` | C# `event Action<...>` or `UnityEvent` | `GameManager`: `phase_changed`, `turn_changed`, `mana_changed`, `flip_first_changed`. `InputManager`: left click/release, `card_right_clicked`, `lane_right_clicked` |
| `await x` / `create_timer(t).timeout` | `async UniTask` / `await UniTask.Delay(ms)` | Many ability functions both `await` and **return a value** (`bool` "did fire"). Coroutines cannot do that cleanly, which is why async is used (§16) |
| `queue_free()` | `Destroy(gameObject)` | Godot frees at end of frame. Unity destroys at end of frame too, but the C# reference remains non-null. Use Unity's `== null` overload or a custom `IsAlive` flag |
| `is_instance_valid(x)` | `x != null` (Unity overloaded) **plus** an `IsAlive` bool on `CardView` | Many arrays keep stale references (`all_cards_in_play_order` is append-only), so check every loop |
| `Node2D.position` (pixels, y-down) | `Transform.localPosition` (units, y-up) | Use a single conversion helper everywhere (§7) |
| `z_index` | `SortingGroup.sortingOrder` on each card root, and `SpriteRenderer.sortingOrder` inside | Cards use relative z −12..+101. Keep the numeric values and map them 1:1 to `sortingOrder` |
| `clip_children = 2` (art clipped to frame) | `SpriteMask` on the frame, and `SpriteRenderer.maskInteraction = VisibleInsideMask` on the art | Used by `CardSpriteParent`, `CardSpellSpriteParent`, `LaneBase` |
| `CanvasGroup` (`CardFront`) | Child GameObject `CardFront` with its own `SortingGroup` | The dissolve shader is applied per sprite (see §8.4), so no framebuffer grouping is needed |
| `RichTextLabel` + BBCode | `TextMeshPro` (world) / `TextMeshProUGUI` (UI) | `[color=#hex]` → `<color=#hex>`, `[br]` → `<br>`, `[img=32x32]path[/img]` → `<sprite name="X">` with a TMP Sprite Asset |
| `AnimationPlayer` clips | Animator clips, or (simpler) code-driven tweens | Five clips: `RESET`, `card_flip`, `card_flip_play`, `card_killed`, `card_levelup_spin`. Their key data is in §8.5 |
| `create_tween()` | DOTween sequence, or a UniTask lerp helper | `TRANS_SINE` + `EASE_IN_OUT` → `Ease.InOutSine` |
| `Area2D` + `collision_layer`/`mask` 1, 2, 4, 8 | 2D Colliders on Unity layers `Card`, `CardSlot`, `Deck`, `Lane` + `Physics2D.OverlapPointAll(point, layerMask)` | `InputManager` uses point queries, not physics bodies |
| `PhysicsPointQueryParameters2D` / `intersect_point` | `Physics2D.OverlapPointAll` | Must scan **all** hits (an Elusive card and its slot overlap) |
| `_input(event)` | New Input System actions, or `Input.GetMouseButtonDown` in `Update` | Block game input while a preview overlay is visible |
| `CanvasLayer` (layer 15, 20) | Separate Screen-Space Overlay `Canvas` with `sortingOrder` 15 / 20 | LobbyUI, SettingsUI (20), CardPreview (15), LanePreview (15) |
| `SubViewport` per mini card | **Do not** replicate with RenderTextures per cell. Build a uGUI version of the card (`MiniCardUI`) | §19.4 |
| `PackedScene.instantiate()` | `Instantiate(prefab)` | `Card.tscn`, `CardSpell.tscn`, `CardLandmark.tscn`, `CardSlot.tscn`, `Lane.tscn`, `KeywordItem.tscn`, `MiniCard.tscn` |
| `ResourceLoader.load("res://…webp")` | `Addressables.LoadAssetAsync<Sprite>(key)` or a `SpriteLibrary` dictionary | Paths in the data must be remapped (§20) |
| `FileAccess` + `user://decks.json` | `Application.persistentDataPath + "/decks.json"` | Same JSON shape |
| `get_tree().change_scene_to_file()` | `SceneManager.LoadScene()` | |
| `DisplayServer.window_set_mode/size` | `Screen.SetResolution(w, h, FullScreenMode)` | SettingsManager |
| `@rpc(...)` | NGO `[Rpc(SendTo.…)]` on a `NetworkBehaviour` | §17. RPCs live on autoloads **and** scene nodes |
| `seed()` + global `randi()`, `shuffle()`; `RandomNumberGenerator` | Two explicit `System.Random` instances | §15. Never use `UnityEngine.Random` for gameplay |
| Godot `Dictionary` (insertion-ordered) | `List<>` or an ordered dictionary | C# `Dictionary` enumeration order is **not guaranteed**. The source iterates `CARDS` to build random pools (§15) |
| `Vector2i` zone keys | `readonly struct ZoneKey(int col, int row)`, or `Vector2Int` | `(-1,-1)` = invalid. Spell zones are `(-1,1)` (allied) and `(-1,0)` (enemy) |

---

## 4. File-by-file port map

Every tracked script and scene is listed. `Scenes/Main.tscn4839691535.tmp` is a stray editor temp file, so skip it.

### 4.1 Scripts

| Godot file | Kind | Unity target | Responsibility |
|---|---|---|---|
| `Scripts/DeckManager.gd` | Autoload | `DeckStorage` (persistent service) | Saved decks `{name: [card_id]}` in `user://decks.json`, `MAX_DECK_SIZE = 12`, active deck name |
| `Scripts/AbilityResolver.gd` | Autoload (+2 RPCs) | `AbilityResolver` (service) + `AbilityNet` (`NetworkBehaviour`) | All card ability execution, dispatched on `AbilityType` (§11) |
| `Scripts/LevelUpManager.gd` | Autoload | `LevelUpManager` | Per-champion level-up conditions, Sun Disc transform (§12) |
| `Scripts/AuraSystem.gd` | Autoload | `AuraSystem` | Reset + reapply aura power/cost modifiers (§13) |
| `Scripts/LaneManager.gd` | Autoload | `LaneManager` | Lane reveal timing + lane effects (§14.1) |
| `Scripts/SwapLaneManager.gd` | Autoload | `SwapLaneManager` | Elusive swaps: pending list, animation, history (§14.2) |
| `Scripts/StunManager.gd` | Autoload | `StunManager` | Stun entries + expiry (§14.3) |
| `Scripts/BotManager.gd` | Autoload | `BotManager` | Offline AI (§18) |
| `Scripts/GameManager.gd` | Main node (`class_name GameManager`, 4 RPCs) | `GameManager : NetworkBehaviour` | Phases, turns, mana, flip-first, win check (§9) |
| `Scripts/CardManager.gd` | Main node (12 RPCs) | `CardManager : NetworkBehaviour` | Drag and drop, play validation, undo, resolve loop, trackers, recall/discard/create, level-up lock, RPC receivers (§10) |
| `Scripts/BoardGeneration.gd` | Main node `Board` | `Board` | Slot grid, zones, spell zones, lanes, power labels (§7) |
| `Scripts/Deck.gd` | Main node `Deck` | `DeckView` | Draw pile, draw/specific draw, Game Start triggers, Deep trigger |
| `Scripts/PlayerHand.gd` | Main node | `PlayerHand` | Hand list (index 0 = newest), fan layout, tweening |
| `Scripts/InputManager.gd` | Main node | `InputRouter` | Left-click raycast → drag. Right-click → card or lane preview |
| `Scripts/NetworkManager.gd` | Main node (`class_name NetworkManager`, 2 RPCs) | `NetSession` | Host/join/offline, peer ↔ player mapping (§17) |
| `Scripts/Card.gd` | Card scene script | `UnitCardView : CardView` | Unit card runtime state, power/cost math, level-up animation, death prevention, runtime keywords, dissolve |
| `Scripts/CardSpell.gd` | Spell scene script | `SpellCardView : CardView` | Same minus power. `on_spell_resolved()` dissolves and frees |
| `Scripts/CardLandmark.gd` | Landmark scene script | `LandmarkCardView : CardView` | No power, instant (non-animated) `_perform_level_up` |
| `Scripts/CardSlot.gd` | Slot scene script | `CardSlot` | `bool CardInSlot` |
| `Scripts/CardDatabase.gd` | Static data + helpers | `CardDatabase` (static) + `cards.json` | 74 card defs, `populate_card_visuals`, `format_card_text`, collectible/related lookups, scene selection |
| `Scripts/LaneDatabase.gd` | Static data | `LaneDatabase` + `lanes.json` | 5 lanes |
| `Scripts/KeywordDatabase.gd` | Static data | `KeywordDatabase` + `keywords.json` | 15 keywords (descriptions, flags). Not referenced by gameplay code yet |
| `Scripts/VocabDatabase.gd` | Static data | `VocabDatabase` + `vocab.json` | 13 glossary terms. Not referenced by gameplay code yet |
| `Scripts/KeywordItem.gd` | UI script | `KeywordBadge` | Sizes the NinePatch badge to its HBox content |
| `Scripts/HomeScreen.gd` | Scene script | `HomeScreenController` | 3 buttons → load scenes |
| `Scripts/LobbyUI.gd` | Scene script | `LobbyController` | Host / Join(IP) / Offline. Starts the game |
| `Scripts/SettingsManager.gd` | Scene script | `SettingsController` | Resolution 1920/1600, fullscreen/windowed |
| `Scripts/CardPreviewManager.gd` | Scene script | `CardPreviewController` | Big card overlay with ◀ ▶ over `PreviewTooltip` |
| `Scripts/LanePreviewManager.gd` | Scene script | `LanePreviewController` | Lane overlay, then related cards |
| `Scripts/DeckBuilder.gd` | Scene script | `DeckBuilderController` | Collection grid, filters, 12-card deck, save/load |
| `Scripts/CardCatalog.gd` | Scene script | `CardCatalogController` | Read-only collection grid + filters |
| `Scripts/MiniCard.gd` | UI script | `MiniCardUI` | Grid tile. Left/right click signals |

### 4.2 Scenes, shaders, materials

| Godot file | Unity target |
|---|---|
| `Scenes/HomeScreen.tscn` | `HomeScreen.unity` (Canvas: title "RUNETERRA FORGE" 48 pt, 3 buttons 52 px tall, bg `#141219`) |
| `Scenes/Main.tscn` | `Main.unity` (see §9.1 for the node → GameObject tree) |
| `Scenes/DeckBuilder.tscn` | `DeckBuilder.unity` |
| `Scenes/CardCatalog.tscn` | `CardCatalog.unity` |
| `Scenes/LobbyUI.tscn` | `LobbyUI.prefab` (Canvas) |
| `Scenes/SettingsUI.tscn` | `SettingsUI.prefab` (Canvas, sort 20) |
| `Scenes/CardPreview.tscn` | `CardPreview.prefab` (Canvas, sort 15) |
| `Scenes/LanePreview.tscn` | `LanePreview.prefab` (Canvas, sort 15) |
| `Scenes/Card.tscn` | `UnitCard.prefab` |
| `Scenes/CardSpell.tscn` | `SpellCard.prefab` |
| `Scenes/CardLandmark.tscn` | `LandmarkCard.prefab` |
| `Scenes/CardSlot.tscn` | `CardSlot.prefab` |
| `Scenes/Lane.tscn` | `Lane.prefab` |
| `Scenes/KeywordItem.tscn` | `KeywordBadge.prefab` (world-space, for cards) + `KeywordBadgeUI.prefab` |
| `Scenes/MiniCard.tscn` | `MiniCardUI.prefab` |
| `Materials/card_discard_dissolve.gdshader` | `CardDissolve.shader` (URP 2D sprite shader, §8.4) |
| `Assets/CardComponent/card_glow_outline.gdshader` | `CardGlowOutline.shader` (additive pulse). Currently unused in code; port it for parity |
| `Materials/card_flash.tres` | Trivial VisualShader (tint param). Currently unused; optional |

---

## 5. Target Unity project layout

```
Assets/
  _Project/
    Scenes/            HomeScreen, Main, DeckBuilder, CardCatalog
    Prefabs/
      Cards/           UnitCard, SpellCard, LandmarkCard, KeywordBadge
      Board/           CardSlot, Lane
      UI/              LobbyUI, SettingsUI, CardPreview, LanePreview, MiniCardUI, KeywordBadgeUI
    Scripts/
      Core/            GameServices, MatchContext, ZoneKey, Coords, Rng, AsyncUtil
      Data/            CardData, LaneData, KeywordData, VocabData, CardDatabase, LaneDatabase, CardTextFormatter
      Match/           GameManager, CardManager, Board, DeckView, PlayerHand, InputRouter
      Cards/           CardView, UnitCardView, SpellCardView, LandmarkCardView, CardSlot, KeywordBadge
      Systems/         AbilityResolver, LevelUpManager, AuraSystem, LaneManager, SwapLaneManager, StunManager, BotManager
      Net/             NetSession, GameNet, CardNet, AbilityNet
      UI/              HomeScreenController, LobbyController, SettingsController,
                       CardPreviewController, LanePreviewController,
                       DeckBuilderController, CardCatalogController, MiniCardUI
      Persistence/     DeckStorage
    Shaders/           CardDissolve.shader, CardGlowOutline.shader
    Art/
      CardComponent/   (frame pieces, PNG)
      CardSprites/     (converted from WebP)
      KeywordSprites/  (converted, also packed into a TMP Sprite Asset)
      RegionSprites/   (converted)
      LaneComponent/   lane_base, lane_border, lor_boardvisual_template
      LaneSprite/      (lane art)
      Misc/            card_back, card_slot, card_template, card_skillshadow, icon, RuneterraForge
    Fonts/             BeaufortforLOL-Bold/Medium, UniversCnRg, UniversRegular (+ TMP font assets)
  StreamingAssets/
    Data/              cards.json, lanes.json, keywords.json, vocab.json
```

---

## 6. Data layer

### 6.1 Card schema (`CardDatabase.CARDS`, 74 entries)

Export the GDScript dictionary to `cards.json` once, using a one-off Godot tool script, or by hand. Keep the **key order**, because the pools in §15 depend on it.
All fields:

| Field | Type | Notes |
|---|---|---|
| *(key)* | string | Card ID, e.g. `"Azir1"`, `"IcePillar"`, `"BuriedSunDisc"` |
| `Name` | string | Display name. **Gameplay compares names** (`"Azir"`, `"Draven"`, `"Restored Sun Disc"`…) |
| `Region` | string[] | 1–2 regions. The icon path is `RegionSprites/<Region without spaces>` |
| `Type` | string | `Champion`, `Follower`, `Spell`, `Landmark` |
| `SubType` | string | `""`, `Ascended`, `Yordle`, `Elite`, `Sea Monster`, `World Rune` |
| `Collectible` | bool | Missing means `false` |
| `Sprite` | string | `res://Assets/CardSprites/<id>.webp` → remap (§20) |
| `Level` | int | Champions only. Missing means 1 |
| `Cost` | int | |
| `Power` | int | **Absent** on Spells and Landmarks. `has("Power")` checks matter (Sion level-up, Deck power display) |
| `Keyword` | string[] | Static keywords. Runtime keywords (Stun) are separate |
| `Skill` | string | Markup text (§8.3). **Also used for trigger gating** (§11.1) |
| `LevelUp` | string | Level-up condition text (may be absent) |
| `LevelUpTo` | string \| null | Can be `null`, `""`, **or self-referencing** (`Rumble2 → "Rumble2"`). Treat all falsy values as "no level-up". Rumble2 never loops because checks require `Level == 1` |
| `AbilityType` | string | Dispatch key (§11). Can be `""`, `"none"`, or missing |
| `HandAbilityType` | string | Only on `Sion2` (`game_end_summon_from_hand`) |
| `BalanceValues` | `{string: int\|string}` | Tunables. Mostly ints, but `Draven2.create_card_id = "SpinningAxe"` is a string. Use `Dictionary<string, JToken>` or `Dictionary<string, object>` |
| `PreviewTooltip` | string[] | Pages for the preview overlay |

```csharp
[Serializable] public class CardData {
    public string Id;                 // injected from the JSON key
    public string Name, Type, SubType = "", Sprite = "", Skill = "", LevelUp = "";
    public string LevelUpTo;          // null | "" | id  → HasLevelUp => !string.IsNullOrEmpty(LevelUpTo)
    public string AbilityType = "", HandAbilityType = "";
    public List<string> Region = new(), Keyword = new(), PreviewTooltip = new();
    public bool Collectible;
    public int Level = 1, Cost;
    public int? Power;                // null for spells/landmarks
    public Dictionary<string, JToken> BalanceValues = new();
    public int BV(string key, int fallback) => BalanceValues.TryGetValue(key, out var t) ? t.Value<int>() : fallback;
    public string BVs(string key, string fallback = "") => BalanceValues.TryGetValue(key, out var t) ? t.Value<string>() : fallback;
}
```

`CardDatabase` static helpers to port:

- `GetCollectibleCards()`: collectibles, sorted Champions first, then Cost ascending, then Name.
- `GetRelatedCards(id)`: the `PreviewTooltip` entries.
- `GetCardIdByName(name, preferCollectible=false)`: the **first** ID in key order with that name.
- `GetCardPrefab(data)`: Spell → SpellCard, Landmark → LandmarkCard, else UnitCard.
- `PopulateCardVisuals(card, data, sourceCard=null)` (§8.2).
- `FormatCardText(text, balanceValues)` (§8.3).
- `ApplyPowerVisual`.

### 6.2 Lanes (`LaneDatabase.LANES`, 5 entries)

`{id: {Name, Sprite, Desc, Rarity, Appearable, RelatedCard[]}}`:

- **HexcoreFoundry**: draw a card.
- **OrnnsForge**: after turn 4, +1 Power to all units here.
- **SunkenTemple**: after turn 3, shuffle a hand card into the deck, then draw 1.
- **NoxkrayaArena**: on turn 5, everything must be played here.
- **RockfallPath**: summon `[Chip]` here, for both players.

The lane sprites are PNGs (`Assets/LaneSprite/*.png`).

### 6.3 Keywords and Vocab

`KeywordDatabase.KEYWORDS` has 15 entries: `{Description, Sprite, Stackable, Generatable, Transferable, Positive}`.
`VocabDatabase.VOCABS` has 13 entries: `{Typo[], Description}`.
Nothing reads them yet. Port them as data so tooltips can be added later.
**Only `Elusive`, `Stun` and `Deep` have gameplay effects in the code** (§21).

### 6.4 Saved decks

`DeckStorage` API: `SaveDeck(name, ids)`, `DeleteDeck`, `GetDeck`, `GetDeckNames`, `GetActiveDeck`, and `ActiveDeckName`.

- File: `persistentDataPath/decks.json`, holding `{ "<name>": ["Azir1", ...] }` (tab-indented).
- Parse failures are ignored.

> The source never feeds saved decks into a match. `Deck.gd.player_deck` is hardcoded (§21). Wiring `GetActiveDeck()` into `DeckView` is a one-line improvement. Make it explicitly, as a feature rather than as part of the port.

---

## 7. Coordinates, scales, and board geometry

### 7.1 Conversion

Godot uses **pixels, origin top-left, y-down**. Use **PPU = 100** and an orthographic camera at `(0,0,-10)` with size 5.4:

```csharp
public static class Coords {
    public const float PPU = 100f;
    public static Vector3 ToWorld(float gx, float gy) => new((gx - 960f) / PPU, (540f - gy) / PPU, 0f);
    public static Vector2 ToGodot(Vector3 w) => new(w.x * PPU + 960f, 540f - w.y * PPU);
}
```

Apply `ToWorld` to **every** hardcoded position in §7.2–§7.4, and convert relative offsets (y-flip only, then divide by PPU).
Import every sprite at PPU 100. With the Godot scales kept verbatim, sizes then match:

| Scale | Meaning |
|---|---|
| `0.2` (`DEFAULT_CARD_SCALE`) | Card in hand/drag. The 630×880 art becomes 126×176 px (1.26×1.76 u) |
| `0.21` (`CARD_BIGGER_SCALE`) | Hovered hand card |
| `0.15` (`CARD_SMALLER_SCALE`) | Card on the board (94.5×132 px = slot size) |
| `0.1` (`SPELL_SLOT_SCALE`) | Card in a spell zone |
| `0.5` | Level-up "fly to centre" scale |
| `1.0` | Card preview overlay (native 630×880) |
| `0.33` | Lane art inside `LaneBase` |
| `3.0` | Lane preview overlay |

### 7.2 Board constants (`BoardGeneration.gd`)

```
GRID_ORIGIN          = (652.75, 104)        // centre of top-left slot of zone (0,0)
SLOT_SIZE = SLOT_STEP = (630*0.15, 880*0.15) = (94.5, 132)
SLOTS_PER_ROW = 2  → ZONE_SIZE = (189, 264)
GRID_ORIGIN_TOP_LEFT = GRID_ORIGIN - SLOT_SIZE/2
CARD_STEP_X = 260, CARD_STEP_Y = 540         // zone-to-zone spacing
COLUMNS = 3, ROWS = 2, SLOTS_PER_CARD = 4
slot_position(col,row,i) = GRID_ORIGIN + (col*260, row*540) + ((i%2)*94.5, (i>>1)*132)

LANE_POSITIONS  = {0:(700,440), 1:(960,440), 2:(1220,440)}
POWER_TEXT_POSITIONS: (c,0) → (700|960|1220, 340),  (c,1) → (700|960|1220, 540)
   label = 50×30, centred (pos - (25,15)), font 24, white

SPELL_SLOT_SCALE = 0.1 → SPELL_SLOT_SIZE = (63, 88)
ALLIED_SPELL_ORIGIN = (483, 533)   // slots fill top → bottom: origin + (0, i*88)
ENEMY_SPELL_ORIGIN  = (1436, 346)  // slots fill bottom → top: origin - (0, i*88)
SPELL_ZONE_ALLIED = (-1, 1) owner 1,  SPELL_ZONE_ENEMY = (-1, 0) owner 0,  4 slots each
Slot sprite z = -12; spell-slot image scaled to 0.1
```

**Slot fill order matters.** It is the order slots are appended to `slots_by_zone[zone]`, and so the order cards fill a zone and the index used for "front/back row":

- Row 0 (opponent, top) appends slot indices `[3, 2, 1, 0]`: BR, BL, TR, TL, so it fills toward the board centre.
- Row 1 (player, bottom) appends `[0, 1, 2, 3]`: TL, TR, BL, BR.
- "Front row" = zone slot index 0–1. "Back row" = 2–3 (`get_card_slot_index_in_zone`).

Zone ownership: `zone_owners[(c,r)] = r`. Row 0 = player 0 (top/opponent) and row 1 = player 1 (bottom/local).
`get_ally_row(p) = p`, `get_enemy_row(p) = 1-p`, `get_opposing_zone((c,r)) = (c, 1-r)`.

### 7.3 Hit-testing a drop (`get_next_available_slot_for_position`)

1. If the point is in the allied spell rect, return the first free allied spell slot (or null). Do the same for the enemy spell rect.
2. `local = pos - GRID_ORIGIN_TOP_LEFT`. Reject negatives.
3. `col = floor(local.x/260)` and `row = floor(local.y/540)`. Reject out-of-range values.
4. `zone_local = local - (col*260, row*540)`. Reject the gap area outside the 189×264 zone rectangle.
5. Return the first slot in `slots_by_zone[(col,row)]` with `!CardInSlot`.

Do this math in **Godot pixel space**: convert the mouse world position with `Coords.ToGodot`. This keeps the constants identical.

### 7.4 Other fixed positions

| Thing | Godot position |
|---|---|
| Deck node | (150, 950). Collider 126×176 on layer 4. Card back sprite at scale 0.2, z −2. Count label at offset (−20,−120)…(20,−80), black |
| Draw spawn point | (150, 940) |
| Hand | `HAND_Y = 950`, `CARD_WIDTH = 160`, centred on `viewport.x/2`: `x_i = cx + i*160 - (n-1)*160/2` |
| `create_card_in_hand` spawn | screen centre (960, 540) |
| TurnText / ManaText / FlipFirstText | (1480,685)-(1680,735) 32 pt; (240,685)-(440,735) 28 pt; (150,95)-(350,145) 24 pt |
| End Turn / Undo buttons | (1695,925)-(1845,975); (1695,860)-(1845,910) |
| VictoryText | centred 500×200, Beaufort Bold 100 pt, black outline 24, z 150, hidden |
| Board background | `lor_boardvisual_template.png` centred at (960,540), z −999 |
| Card preview / lane preview container | (960, 540) |

---

## 8. Card prefabs and visuals

### 8.1 `UnitCard.prefab` hierarchy (from `Card.tscn`)

The root is at scale 0.2 with z 1. All offsets are relative to the card centre, in Godot pixels at scale 1 (630×880 card).

```
UnitCard  (CardView script, SortingGroup, scale 0.2)
├─ Hitbox            BoxCollider2D 630×880, layer "Card" (Godot mask 1). Disabled when on board unless Elusive
├─ CardFront         SortingGroup (was CanvasGroup)
│  ├─ Cost           TMP  rect (-295,-437.5)-(-175,-317.5)  Beaufort Bold 70, centred, z -5
│  ├─ SubType        TMP  rect (-125,-455)-(125,-335)        Univers Cn 30, colour (0.592,0.584,0.565), z -5
│  ├─ Power          TMP  rect (175,-437.5)-(295,-317.5)     Beaufort Bold 70, z -5
│  ├─ TextContainer  vertical layout, rect (-275,44)-(275,405), spacing 14 (anchored to card bottom)
│  │  ├─ CardName        TMP Beaufort Bold 64 (auto-shrink to 36, step 2, max width 530), outline 5
│  │  ├─ KeywordContainer horizontal, spacing 32, centred  → KeywordBadge children
│  │  ├─ Skill           TMP Univers Regular 36, outline 3
│  │  ├─ LevelSeperator  card_levelup.png
│  │  ├─ LevelUp         TMP Univers Regular 36, colour (1,0.635,0.396), outline 3
│  │  └─ RegionContainer horizontal, spacing -8 → Region1, Region2 (96×96, alpha 0.706)
│  ├─ CardMana       card_mana.png     z -6
│  ├─ CardPower      card_power.png    z -6
│  ├─ CardSubType    card_subtype.png  z -6, offset (-2.5,-0.5)
│  ├─ SkillShadow    card_shadow.png   z -7
│  ├─ CardSpriteParent card_sprite.png z -8 + SpriteMask (clip_children)
│  │  └─ CardSprite  (champion art)  maskInteraction = VisibleInsideMask
│  └─ CardBase       card_base.png     z -11
├─ CardBack          card_back.png  (hidden by default; z toggled 5 / -12)
├─ Light1, Light2    URP Light2D (Sprite/Freeform), hidden; rotation 15°, used by level-up sweep
└─ Animator / tween driver
```

Because the Godot text nodes sit in a y-down layout, build `TextContainer` with a `VerticalLayoutGroup` in a world-space `Canvas` child, or position TMP objects manually.
The Godot text nodes are all z −5 *inside* `CardFront`, so they draw above the frame sprites (−6 … −11).

- **SpellCard** (`CardSpell.tscn`) uses `CardSpellSpriteParent/CardSpellSprite`, `CardSpellSpriteBase`, `CardTextBase` and `CardTextShadowBase` (the `card_*_spell.png` pieces). `RegionContainer` sits directly under `CardFront`. It has no Power or SubType.
- **LandmarkCard** (`CardLandmark.tscn`) uses the `card_*_landmark.png` pieces. It has no Power, and its `RegionContainer` is under `TextContainer`.

### 8.2 `PopulateCardVisuals(card, data, source=null)`

1. `CardName` = Name. Shrink the font from 64 by 2 until the text width ≤ 530, with a minimum of 36. In TMP, use auto-size with min 36 and max 64.
2. `Cost` = base Cost. The cost colour is applied later by `UpdateCostLabel`.
3. Units only: power visual. The label and `CardPower` sprite show only when `Power` exists. The text comes from `source.GetPowerDisplayTextForBase(basePower)` when a live source card is given, otherwise the raw base.
4. `Skill`: hidden if empty, otherwise `FormatCardText(Skill, BalanceValues)`.
5. Units only: `LevelUp` + `LevelSeperator` are visible only if `LevelUp` is non-empty.
6. Art: `CardSprite` (or `CardSpellSprite`) ← `Sprite`.
7. Units only: `SubType` in upper case. The label and `CardSubType` bg are visible only if non-empty.
8. Regions:
   - `Region1` ← `RegionSprites/<Region[0] without spaces>`.
   - `Region2` gets region 2 if present; otherwise hide it.
9. Keywords: clear the container. If there are none, hide it. Otherwise add one badge per keyword. Show the keyword **name** only when there are fewer than 3 keywords.
   - `CardView.RefreshKeywordDisplay()` does the same with `static keywords + runtimeKeywords` (e.g. Stun). Call it after every repopulate.

**Power/cost display:**

- `GetCurrentPower()` = `Power(displayId ?? cardId) + powerModifier + auraPowerModifier`.
- The display is green when `powerModifier + auraPowerModifier > 0` and red when < 0.
- `GetCurrentCost()` = `max(0, Cost + costModifier + auraCostModifier)`.
- The cost label is green if either cost modifier is < 0 and red if `costModifier > 0`.

**Hand "glow":** `UpdateGlow(currentMana)` runs only while `IsInHand`.

- Affordable: `color = white`, dissolve `gray_amount = 0`.
- Not affordable: tint `(0.5, 0.5, 0.5)`, `gray_amount = 1`.

Call it on every `mana_changed` for the local player, after cost changes, and after aura recalculation. `HideGlow()` runs when the card leaves the hand.

### 8.3 Card text formatter (`format_card_text`)

The source text uses a mini-markup. Port the parser **character for character**, but emit TMP tags:

| Source token | Meaning | TMP output |
|---|---|---|
| `[br]` | line break | `<br>` |
| `[b]`, `[color=…]` etc. (known BBCode tag names) | pass-through | translate to the TMP equivalent |
| `[Card Name]` (anything else in brackets) | card reference | `<color=#54a5ff>Card Name</color>` |
| `:Keyword:` (identifier or int) | keyword icon + name | `<sprite name="Keyword">Keyword` |
| `:Keyword:{vocab}` | icon + vocab value | `<sprite name="Keyword">` + (BalanceValue or gold vocab) |
| `-{key}` | minus + value (no break) | `-<value>` (use `<nobr>`) |
| `{key}` | BalanceValue if the key exists, else a gold vocab term | value, or `<color=#ffca4b>key</color>` |

Example: `"{Round Start}: Grant me +{win_power} Power"` with `{win_power:2}` becomes `<color=#ffca4b>Round Start</color>: Grant me +2 Power`.

Keyword icons need a **TMP Sprite Asset** built from `KeywordSprites/*`, with each sprite named exactly like the keyword (`Stun`, `Deep`, `Augment`…). The Godot version renders them at 32×32.

### 8.4 Dissolve / grey shader (`card_discard_dissolve.gdshader`)

The source creates one shared `ShaderMaterial` per card in `_ready` and assigns it to the main sprites. Units use `CardBase`, `CardSprite`, `CardMana`, `CardPower`, `CardSubType` and `SkillShadow`. Spells and landmarks use their equivalents. The TMP text fades through the card alpha tween.

Uniforms: `dissolve_amount` (0), `edge_width` (0.06), `edge_color` (1,0.5,0,1), `gradient_weight` (0.5), `noise_seed` (random per discard), `gray_amount` (0/1).

```hlsl
// URP 2D sprite shader, fragment
float hash(float2 p){ p += _NoiseSeed; return frac(sin(dot(p, float2(127.1,311.7))) * 43758.5453); }
float vnoise(float2 p){ float2 i=floor(p), f=frac(p); f=f*f*(3-2*f);
  return lerp(lerp(hash(i),hash(i+float2(1,0)),f.x), lerp(hash(i+float2(0,1)),hash(i+float2(1,1)),f.x), f.y); }
half4 frag(Varyings IN):SV_Target{
  half4 o = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uv) * IN.color;
  float gy = 1 - IN.uv.y;                        // Godot UV.y is top→bottom; Unity is bottom→top
  float v = lerp(vnoise(IN.uv*6), gy, _GradientWeight);
  float th = _DissolveAmount * (1 + _EdgeWidth);
  clip(v - (th - _EdgeWidth));
  float e = 1 - smoothstep(0, _EdgeWidth, v - (th - _EdgeWidth));
  float3 c = lerp(o.rgb, _EdgeColor.rgb, e*_EdgeColor.a) + _EdgeColor.rgb*1.5*e*e;
  c *= lerp(1, 0.5, _GrayAmount);
  return half4(c, o.a);
}
```

`PlayDiscardDissolve(duration=0.8)`:

- Hide the back, randomise `noise_seed` (**use a cosmetic RNG**, §15), then tween `dissolve_amount` 0→1 and alpha 1→0 with `EaseInSine`.
- Spells use 0.4 s in `on_spell_resolved`, then destroy.

`card_glow_outline.gdshader` is additive: `glow_color * tex.a * intensity * (0.75 + 0.25*sin(TIME*speed*π))`. It is not wired up yet.

### 8.5 Animations (keep the exact timings)

Driving these with code tweens is simpler than Animator state machines. "Flip" means scaling X, as in the source.

| Clip | Length | Keys |
|---|---|---|
| `card_flip` (draw / create in hand) | 0.2 s | `CardFront.scale` and `CardBack.scale`: (1,1)@0 → (0.05,1)@0.1 → (1,1)@0.2. `CardBack.z`: 0@0 → −6@0.1 |
| `card_flip_play` (reveal during RESOLVE) | 0.7 s | Front and back scale: (1,1)@0 → (0.05,3)@0.133 → (3,3)@0.6 → (1,1)@0.7. `CardBack.z`: 20@0 → −10@0.133. `CardFront.z`: 19@0 → 25@0.133 → 0@0.7 |
| `card_killed` | 0.5 s | `CardBack` hidden. `CardFront` alpha 1 → 0 |
| `card_levelup_spin` | 2.7 s | Front and back scale.x alternate 1 ↔ 0.05 every 0.1 s from 0 to 0.9, then every 0.0667 s until 1.633 (21 keys). `CardBack.visible` toggles in pairs (false, true, true, false…). `CardBack.z` 101@0 → 0@1.567. Light1/Light2 visible 1.8 → 2.3 s while moving from (−310,445)/(−345,520) to (391.9,−519.5)/(356.9,−444.5) |
| `RESET` | – | Scales 1, front at (0,0), z 0, back visible, lights hidden at their start positions |

After `card_flip` or `card_flip_play` finishes, always call `HideCardBack()` (visible false, z −12).

**Level-up sequence** (`Card._perform_level_up(newId)`). Port it exactly, because other systems depend on its side effects:

0. If the new data is missing, return.
   - If this is a **local** card and `permanentlyLeveledUp[champName] == newId`, apply the level-up silently, fire `ExecuteLevelUpAbility`, and return.
1. Set `cardId = newId` **immediately**, before any await.
   - For local cards, set `permanentlyLeveledUp[champName] = newId` immediately.
   - If `displayCardId` is empty, set it to `oldId`. This freezes the shown stats while queued.
   - For local and online cards, send RPC `_receive_opponent_level_up(oldId, newId)`.
2. `levelUpPending++`. Wait while `levelUpInProgress`, then set `levelUpInProgress = true`.
3. Set `displayCardId = newId`. Tween to screen centre and scale 0.5 (1 s, InOutSine), with z 100.
4. Play the spin. After **1.5 s**, repopulate visuals from the new data and refresh keywords.
5. Wait for the spin to finish (2.7 s total). Tween back to the **current** slot position (the lane may have reflowed) and the original scale (1 s).
6. Restore z: board cards go back to 0. Wait 0.5 s.
7. `levelUpInProgress = false`, `levelUpPending--`, `displayCardId = ""`.
8. For local cards, run `CardManager.UpgradeAllCopies(oldId, newId)` (§10.6).
9. `AbilityResolver.ExecuteLevelUpAbility(this)`.

Landmark level-up is instant: swap the ID, repopulate, and send the RPC if the card is local.

**Death prevention:** `CanPreventDeath()` is true for `levelup_on_death` (Tryndamere1) and `survive_death` (Tryndamere2). `OnDeathPrevented()` either levels up to `LevelUpTo` or adds `+survive_power` (2) to `powerModifier`.

---

## 9. Game flow: exact phase ordering

### 9.1 `Main.unity` object tree (from `Main.tscn`)

```
Main
├─ CardManager    (+ TurnText, ManaText, FlipFirstText, Button "End Turn", Undo "Undo Actions")
├─ GameManager
├─ Board          (card_slot prefab ref; lane prefab)
├─ PlayerHand
├─ Deck           (collider layer Deck, back sprite, count label)
├─ InputManager
├─ NetworkManager
├─ LobbyUI  SettingsUI  CardPreview  LanePreview
├─ VictoryText
├─ Global Volume (Bloom)        ← WorldEnvironment glow
└─ Background sprite            ← lor_boardvisual_template.png, z -999
```

All spawned cards are **children of CardManager**. The source relies on this in `get_beheld_cards`, which scans CardManager's children as a fallback.

### 9.2 Enums and state

- `GamePhase { GAME_START, TURN_LOOP, GAME_END }`
- `RoundPhase { NONE, ROUND_START, PLAY, SWAP_LANE, RESOLVE, ROUND_END }`
- `GameManager` exports: `max_turns=6`, `player_count=2`, `starting_player_id=1`, `initial_draw_count=3`, `draw_per_turn=1`, `mana_indicator_player_id=1`.
- `PlayerManaState { base_max=1, bonus_max=0, current=1; max = max(0, base+bonus) }` for players 0 and 1.

### 9.3 Start of match

The lobby calls `GameManager.start_game()`. **The order below is deliberate.** The source comments say Game Start must run *before* lane assignment, so that Hexcore Foundry's reveal draw cannot pull Azir out of the deck first.

1. Reset phases, `turn_number = 0`, `active_player_id = 1`. Hide VictoryText. Emit phase.
2. Flip-first:
   - Online: the host picks `randi_range(0,1)` and broadcasts `_sync_flip_first(networkId)`.
   - Offline: pick locally and push it to CardManager.
3. `Deck.shuffle_deck()`.
4. `await Deck.trigger_game_start_abilities()`: for each deck entry whose Skill begins with `{Game Start}` → `AbilityResolver.execute_game_start_ability_for_deck`. Azir1 then summons a Buried Sun Disc in the mid lane.
5. Lanes:
   - Online: the host runs `Board.pick_random_lane_ids()` (shuffle the Appearable IDs, take 3) and broadcasts `_sync_lane_assignment`.
   - Offline: apply locally.
   - Either way: `Board.create_lanes_from_ids()` → `LaneManager.setup_lanes()`. The left lane is revealed now and its immediate effect fires.
6. `Deck.draw_cards(3)`.
7. If `BotManager.bot_enabled`, run `BotManager.setup_bot(3)`.
8. `start_next_turn()`.

### 9.4 Each turn

`start_next_turn()`:

- If the game has ended, stop.
- If `turn_number >= 6`, call `end_game()`.
- Otherwise:
  - set `TURN_LOOP` and `turn_number++`;
  - sync `current_player_id` (always 1);
  - emit `turn_changed`;
  - run `begin_round_start()`.

`begin_round_start()` (`ROUND_START`):

1. Expire the active temporary bonus mana from last turn.
2. Move pending bonus mana into active (adds to `bonus_max`, no refill).
3. `base_max = max(1, turn)` for both players. Clamp.
4. Refill both players to max.
5. `await LaneManager.on_round_start(turn)`: reveal the mid lane on turn 2 and the right lane on turn 3, and arm Noxkraya on turn 5.
6. `await CardManager.trigger_round_start_abilities()` (§10.5).
7. `Deck.draw_cards(1)`, then `await LevelUpManager.check_level_ups_after_draw()`.
8. If the bot is enabled, run `BotManager.on_round_start()`: it draws and queues its play synchronously.
9. Switch to `PLAY`.

**PLAY:** the player drags cards (§10.1). Undo is available. **End Turn** calls `end_play_phase()`:

1. Disable the button and cancel any active drag.
2. Online:
   - `sync_hand_data()`;
   - the host records itself, while the client sends `rpc_id(1, _on_player_end_turn)`;
   - once the server has 2 players, it clears the list and broadcasts `_proceed_to_resolve` (call_local).
3. Offline: call `_proceed_to_resolve()` directly.

`_proceed_to_resolve()`:

1. **SWAP_LANE**, via `_swap_lane_phase()`:
   - Hide every card in `played_cards_order` (this turn's plays).
   - `apply_pending_opponent_swaps()`.
   - `await SwapLaneManager.execute_swaps()`.
   - Unhide those cards, then run `_notify_zone_power_changed()`.
2. **RESOLVE**:
   - `seed(turn*7919 + flip_first*1337)`.
   - `StunManager.on_resolve_start(turn)`.
   - `await CardManager.resolve_played_cards()` (§10.4).
3. Online: `sync_hand_data()` again, so resolve-created cards count for behold.
4. Update the zone power labels.
5. **ROUND_END**:
   - `await trigger_round_end_abilities()`;
   - `await LaneManager.on_round_end(turn)`, which runs **after** the card abilities;
   - update the zone power labels again.
6. `check_lane_winners_and_update_flip_first()`:
   - Online, the host alone decides.
   - The winner is decided by lanes won, then total power, then random.
   - Convert with `_local_to_network_player` (host: `1 - local`) and broadcast `_sync_flip_first`.
7. `start_next_turn()`.

### 9.5 Game end

`end_game()`:

1. Set `GAME_END`, then `seed(turn*7919 + flip_first*1337)`.
2. `await CardManager.trigger_game_end_abilities()`, which runs 3 passes (§10.5).
3. Update the power labels.
4. Winner: row 0 vs row 1, per lane. Two lane wins decide it; otherwise total power decides; otherwise it's a tie.
5. Show **VICTORY** (row 1 wins), **DEFEAT** (row 0 wins) or **TIE**.

Zone power counts only **resolved** cards: `sum(GetCurrentPower())`.

### 9.6 Mana API (keep it public; abilities use it)

`get_player_max_mana`, `get_player_current_mana`, `set/add/get_player_bonus_max_mana(refill)`, `refill_player_mana`, `refund_player_mana`, `spend_player_mana` (returns false if too low), and `add_temp_bonus_mana(player, amount)`.
Temporary bonus mana is queued for the next turn and expires the turn after.

**UI indicators:** "Turn: N" (or "Game End"), "Mana: cur/max" for player 1, and "Priority: You / Opponent / —".
The End Turn button is enabled only in `TURN_LOOP + PLAY`. The Undo button is enabled only in PLAY with a non-empty undo stack.

---

## 10. CardManager

### 10.1 Input and drag

**InputRouter** (was `InputManager`):

- Ignore all input while CardPreview or LanePreview is visible.
- **Left press:** point-query every hit.
  - The first collider on layer **Card (1)** → `CardManager.StartDrag(card)`.
  - Layer **Deck (4)** → log only. Click-to-draw is disabled.
- **Left release:** `CardManager.OnLeftRelease()` → `FinishDrag()`.
- **Right press:**
  1. Query layer Card and take the highest z.
  2. If nothing is hit, fall back to a **geometric** hit test over the board cards: rect = `630*scale × 880*scale` around the position, highest z wins. Board cards have their colliders disabled.
  3. Emit `CardRightClicked(card)`.
  4. Otherwise query layer **Lane (8)** and emit `LaneRightClicked(laneId, revealTurn)` from the lane's metadata.

**CardManager hover:** `hovered` makes the card scale 0.21 with z 3. `hovered_off` makes it scale 0.2 with z 2, but only for non-board cards when no drag is active; it then re-checks the card under the cursor.
**While dragging:** the card follows the mouse, clamped to the screen.

`StartDrag(card)`:

- Allowed only in PLAY.
- **Board card:**
  - Only if it is resolved, has **Elusive**, is owned by the local player, has no pending swap, and is **not stunned**.
  - That starts a *swap drag*: free the origin slot, clear `card_slot_is_in`, and remove the card from the zone.
- Set scale 0.2 and z 10.

`FinishDrag()` for a normal play checks, in order:

1. The target slot exists.
2. The zone is owned by the local player.
3. Spells go only to the spell zone, and non-spells never do.
4. Noxkraya restriction: `LaneManager.is_placement_restricted`. Spell zones are exempt.
5. The game is in PLAY phase.
6. `spend_player_mana(cost)` succeeds.

If any check fails, return the card to the hand at scale 0.2, z 2.
On success:

- Set scale 0.15 (0.1 in the spell zone) and z 0, and set the slot.
- Remove the card from the hand, remembering its index. Snap it to the slot.
- Disable the collider **unless the card is Elusive**.
- Mark the slot occupied and set `owner = current_player_id`. Add the card to the zone.
- Append it to `played_cards_order` and to `all_cards_in_play_order` (duplicate-safe).
- Run `track_summoned_card(card, fromHand=true)`.
- Push `{card, hand_index, mana_cost, zone_key, slot}` onto `undo_stack`.
- `is_in_hand = false` and hide the glow.
- Online: RPC `_receive_opponent_card_play(id, col, 1-row, power_modifier)`.

**Swap drag release** (`_finish_swap_drag`):

- Valid only if the target is the same row, a different column, and owned by the local player.
- Place the card temporarily in the destination slot, then `SwapLaneManager.register_swap(...)`.
- Reposition both zones.
- Online: send `_receive_opponent_swap(id, fromCol, toCol)`.
- Otherwise, snap the card back to its origin with no tween.

### 10.2 Undo (`_on_undo_button_pressed`) — undoes all plays this turn

1. Sum the `mana_cost` of every entry.
2. For each entry: free the slot, remove the card from the zone, erase it from `all_cards_in_play_order`, set scale 0.2 and z 2, re-enable the collider, and set `is_in_hand = true`.
3. Re-insert the cards into the hand at their original indices, in ascending order (clamped). Lay out the hand over 0.3 s.
4. Refund the mana, then clear `played_cards_order` and `undo_stack`.
5. Online: send `_receive_undo_all_plays`, which clears the opponent's `_pending_opponent_cards`.

> The source does **not** undo the `summoned_cards` tracker entries added during play. Keep that behaviour for parity, or fix it deliberately.

### 10.3 Trackers (append-only per match; used by level-ups)

| Array | Entry | Written by |
|---|---|---|
| `all_cards_in_play_order` | Card refs, never removed (except by undo) | play, summon, opponent spawn |
| `played_cards_order` | This turn's plays; cleared after resolve | play, opponent spawn |
| `summoned_cards` | `{card_id, owner_player_id, was_played_from_hand, is_resolved}` | `track_summoned_card`. It then calls `LevelUpManager._check_sion_levelup()` |
| `killed_cards` | `{card_id, owner_player_id, killer_player_id, killer_card_id, zone_key, is_revived:false}` | `track_killed_card`. It then calls `_check_nasus_levelup()` |
| `created_cards` | `{card_id, owner_player_id, creator_player_id (-1 = lane), creator_card_id, created_at_turn}` | `track_created_card` |
| `recalled_cards` | `{card_id, owner_player_id, recaller_player_id, recaller_card_id}` | `recall_card`, when there is a recaller |
| `discarded_cards` | `{card_id, owner_player_id, discarded_by_card_id, discarded_at_turn}` | `track_discarded_card` (local + RPC) |
| `drawn_cards` | `{card_id, owner_player_id, turn}` | `Deck.draw_card` / `draw_specific_cards` |
| `opponent_hand_card_ids` | string[] | RPC `_receive_opponent_hand_ids` |
| `player_state` | `{0:{is_deep}, 1:{is_deep}}` | `set_player_deep` / RPC |
| `permanently_leveled_up` | `champName → highest id` | `_perform_level_up` (local) |

### 10.4 Resolve loop (`resolve_played_cards`)

1. `_spawn_pending_opponent_cards()`. For each queued `{card_id, zone_col, zone_row, power_mod}`:
   - put the card face-down in the first free slot, with `owner = 0`, scale 0.15 (0.1 in the spell zone) and the collider off;
   - apply `power_mod`;
   - add it to the zone, `played_cards_order`, `all_cards_in_play_order` and `opponent_played_cards`;
   - `track_summoned_card(fromHand=true)`.
2. Sort `played_cards_order` so the flip-first owner's cards come first, keeping play order within each owner.
3. Show every card back (z 5), then wait **0.5 s**.
4. For each card in order:
   1. Play `card_flip_play` and await it. Hide the back. Set `is_resolved = true`.
   2. Save `pre_summon_id = card_id`, then `await card.on_summon()` (the Play ability).
   3. Online:
      - If the card is the local player's, send `_receive_card_resolve_done(pre_summon_id)`.
      - Otherwise wait until that key arrives (polled every 0.05 s).
   4. If the card is `SpinningAxe`, increment `axe_play_count` on every resolved, on-board Draven owned by the same player.
   5. Mark the newest matching `summoned_cards` entry `is_resolved = true`.
   6. `LevelUpManager.check_level_ups_after_resolve(card)`, then `await WaitForLevelUp()`.
   7. **Spell cleanup:** free the slot, remove the card from the zone, reposition, wait 0.3 s, then `await on_spell_resolved()` (dissolve 0.4 s + destroy).
   8. `_notify_zone_power_changed()` → `AuraSystem.recalculate_auras()`, `LevelUpManager.check_conditional_buff_level_ups()`, and the power labels.
   9. Wait **0.7 s** (`CARD_PAUSE_TIMER`).
5. Clear `played_cards_order` and `undo_stack`.

### 10.5 Phase trigger loops

**Round start and round end** use the same shape:

- Iterate `all_cards_in_play_order`, flip-first sorted.
- Skip dead cards, cards without a slot (killed or recalled), and **stunned** cards.
- `didFire = await card.on_round_X()`, then `await WaitForLevelUp()`.
- If it fired: notify the power change and wait 0.7 s.
- After the loop: `check_level_ups_after_abilities()`, then wait for level-ups again.

**Game end** runs three passes:

1. **Every board card once.** Dedupe by reference, since recall and replay can create duplicates in the append-only list.
2. **Azir level 3 double fire.** For each resolved, on-board Azir at Level 3, fire `on_game_end` a *second* time on every other resolved, on-board **Ascended** ally of the same owner whose Skill contains `{Game End}`. Keep a guard so each card gets at most one bonus fire.
3. **Hand Game End.** For player IDs `[flip_first, 1-flip_first]` (or `[1,0]` if flip-first is unset), snapshot that player's hand cards whose effective type (`HandAbilityType` if set, else `AbilityType`) is `game_end_summon_from_hand` and whose Skill contains `{Game End}`. Then run `AbilityResolver.execute_game_end_hand_ability`, wait, notify, and pause 0.7 s.

### 10.6 Card creation, recall, discard, cost, global upgrade

- **`create_card_in_hand(id, creatorId="", creatorPlayer=-1)`**:
  - If the champion name is in `permanently_leveled_up`, create the upgraded ID instead.
  - Spawn at screen centre, play `card_flip`, and add to the hand over 0.3 s. Set `is_in_hand`, update the glow, and track creation.
  - **The new card is inserted at hand index 0.** Rumble2 relies on this.
- **`recall_card(card, recallerPlayer, recallerCardId)`**:
  - Free the slot, remove the card from the zone, reposition.
  - Online: send `_receive_opponent_recall(id, col, 1-row)`.
  - For an opponent card: just remove it from the board.
  - Otherwise: `is_resolved = false`, z 10, re-enable the collider, then scale-tween 0.15 → 0.2 over 0.8 s while flying to the hand. Afterwards set z 2, `is_in_hand`, update the glow, and track the recall.
- **`discard_card_from_hand(card, byCardId)`**:
  - Remove the card from the hand without relayout. Play the dissolve for 0.8 s. Relayout the hand over 0.1 s.
  - Track the discard.
  - If the type is `on_discard_buff_create`, run the on-discard ability and then `_check_sion_levelup()`.
  - Destroy the card.
- **`adjust_cost(cardOrArray, delta)`**: add `delta` to `cost_modifier`, refresh the cost label colour, and update the glow.
- **`upgrade_all_copies(old, new)`**. For local copies:
  - board copies: apply the level-up silently;
  - hand copies: swap the ID, repopulate, and play `card_flip`;
  - deck entries: swap the ID.
  - Online: send `_receive_opponent_champion_level_up_global`, which silently upgrades the opponent's board copies and fixes `opponent_hand_card_ids`.
  - `Deck.draw_card` also maps IDs through `get_upgraded_card_id` as a safety net.
- **`set_player_deep(p)`**:
  - Happens once only.
  - Sets `is_deep` and recalculates auras.
  - Runs `check_level_ups_after_deep_state_change(p)`.
  - If local and online, sends `_receive_opponent_became_deep`.
- **Behold** (`get_beheld_cards(p)`): the local hand, plus the cards in the player's ally zones, plus CardManager children owned by `p` (the fallback). For the opponent it also adds `BeheldCardProxy {card_id, owner}` objects built from `opponent_hand_card_ids`.

**The standard "summon to board" recipe** is repeated about 7 times in the source (Sun Disc, Blade, Chip, summon copy, Sion, and the RPC mirrors). Make it one helper:

```csharp
CardView SummonToSlot(string id, int owner, ZoneKey zone, CardSlot slot, string creatorCardId = null, int creatorPlayer = int.MinValue) {
    var data = CardDatabase.Get(id);
    var c = Instantiate(CardDatabase.GetCardPrefab(data), cardManager.transform);
    c.CardId = id; c.OwnerPlayerId = owner; CardDatabase.PopulateCardVisuals(c, data);
    c.transform.position = slot.transform.position; c.SetScale(0.15f); c.SortingOrder = 0;
    c.Slot = slot; c.SetColliderEnabled(false); c.IsResolved = true; c.HideCardBack();
    slot.CardInSlot = true; board.AddCardToZone(zone, c);
    cardManager.AddCardToPlayOrder(c); cardManager.TrackSummonedCard(c, fromHand:false);
    if (creatorCardId != null) cardManager.TrackCreatedCard(c, creatorPlayer, creatorCardId);
    return c;
}
```

---

## 11. Ability system

### 11.1 Dispatch and trigger gating

`AbilityResolver` switches on `AbilityType`. Each phase entry point **also gates on the Skill text**. Keep these exact tests, because several cards depend on them:

| Entry point | Gate | Returns |
|---|---|---|
| `ExecutePlayAbility(card)` | none (any AbilityType match) | `Task` |
| `ExecuteRoundStartAbility(card)` | `Skill.Contains("{Round Start}")` | `Task<bool>` (true when gated in) |
| `ExecuteRoundEndAbility(card)` | `Skill.StartsWith("{Round End}")` | `Task<bool>` |
| `ExecuteGameEndAbility(card)` | `Skill.Contains("{Game End}")` | `Task<bool>` |
| `ExecuteGameStartAbilityForDeck(id, data, owner)` | the caller checks `Skill.StartsWith("{Game Start}")` | `Task` |
| `ExecuteLevelUpAbility(card)` | none | `void` (fire and forget) |
| `ExecuteOnDiscardAbility(card)` | the caller checks the type | `Task` |
| `ExecuteLastBreathAbility(card)` | the caller checks `AbilityType == "last_breath_create"` | `Task` |
| `ExecuteSwapArriveAbility(card, to, from)` | none | `Task` |
| `ExecuteGameEndHandAbility(id, data, owner)` | effective type = `HandAbilityType` or `AbilityType` | `Task` |

### 11.2 Complete AbilityType inventory

This covers every value in `CardDatabase.gd`. "Local-only" means the effect runs only on the owner's client: `owner == current_player_id` (or `== 1`, which is the same thing). The other client learns the result by RPC.

**Play (`execute_play_ability`)**

| AbilityType | Cards | Behaviour (from code) |
|---|---|---|
| `create_card` | Trundle1 | Local-only. Parse the first `[Name]` in Skill, look it up by name (→ IcePillar) and create it in hand |
| `mana_ramp` | IcePillar | Local-only. `add_temp_bonus_mana(owner, 5)`. **Hardcoded 5**: `BalanceValues.mana_bonus` is ignored |
| `drain_power` | Xerath1 | For every *other* resolved Champion or Follower in this lane (both sides), `power_modifier -= drain_power` (2). Xerath gains the **actual** total change |
| `stun_enemy` | Kennen1, Kennen2 | `pick_random_target` among enemy Champions/Followers in the opposing zone, then `StunManager.apply_stun`. If `power_decrease` is set (Kennen2: 1), also apply −1 Power |
| `recall_allies_same_lane` | NavoriConspirator | Local-only. Recall every other resolved allied Champion/Follower in this zone (collect first, then recall) |
| `recall_cost_allies` | SolitaryMonk | Local-only. Recall allied resolved Champions/Followers whose **base** Cost == `recall_cost` (1), across all ally zones |
| `discard_by_cost_bracket` | Rumble1 | Local-only. Split the hand into brackets ≤2, 3–4 and ≥5 (current cost). Discard one random card per non-empty bracket (**local RNG**) and send `_receive_opponent_discard` for each. Gain +2 Power per discard (RPC `_receive_opponent_power_buff`). If Rumble1's owner now has ≥ `discard_threshold` (4) discards, `await` the level-up to `LevelUpTo` inline |
| `create_card_if_not_in_hand` | Draven1 | Local-only. Parse `[Spinning Axe]` and create it unless one is already in hand |
| `spinning_axe_discard` | SpinningAxe | Local-only. Target hand index 0 (**newest**, "leftmost"). Find the first resolved, on-board Draven of the same owner and give +`power_bonus` (1), notifying and sending the RPC buff. Then discard the target |
| `create_multiple_cards` | Draven2 | Local-only. Create `create_count` (2) × `create_card_id` ("SpinningAxe"), with no duplicate check |
| `janna_updraft_draw` | Janna1 | Local-only. **Updraft** the `updraft_threshold` (2) **oldest** hand cards: −1 cost each, wait 0.8 s, then insert each into the deck at a random position (**local RNG**) as `{id, cost_mod}`. Draw the same number, then run the draw level-up check |
| `janna_draw_cost_reduce` | Janna2 | Local-only. Draw `draw_threshold` (1). Find the new cards by diffing the hand snapshot and apply −`cost_reduction` (1) to them. Run the draw level-up check |
| `sea_scarab_draw_discard` | SeaScarab | Local-only. Pick a random non-Champion entry from the deck (local RNG), `draw_specific_cards([id])`, find it in the hand, discard it, then run the draw check |
| `abyssal_eye_draw` | AbyssalEye | Local-only. Draw `draw_count` (1), then run the draw check |
| `devourer_deep_kill_enemy` | DevourerOfTheDepths | Local-only. Only if the owner is Deep: kill a random (`pick_random_target`) resolved enemy Champion/Follower in the opposing zone with strictly less Power (standard kill flow, §11.3) |
| `summon_copy` | *(no card uses it)* | Summon a copy in the next free slot near the card's position. Port it for completeness |
| `buff_allies`, `damage_enemies` | *(no card uses them)* | **Placeholders that only log**. Port as no-ops |

**Level up (`execute_level_up_ability`)**

| AbilityType | Cards | Behaviour |
|---|---|---|
| `level_up_create_from_discards` | Rumble2 | Local-only. For each of the owner's discards: build the pool of **Collectible** cards with the same base cost (cached per cost, **ordered by the CARDS key order**) and pick one with the local RNG. `create_card_in_hand`, then take `hand[0]` and apply −1 cost. (The card text mentions Augment, which isn't implemented) |
| `nautilus_levelup_create_sea_monsters` | Nautilus2 | Local-only. Pool = cards with SubType "Sea Monster" and Cost ≥ `created_cost` (3), in key order. Fisher–Yates with the local RNG, then take `created_count` (3) without duplicates and create them in hand |

**Round Start** (gate `Contains("{Round Start}")`)

| AbilityType | Cards | Behaviour |
|---|---|---|
| `conditional_buff` | Renekton1/2/3 | If this zone's resolved power is **greater than** the opposing zone's, `power_modifier += win_power` (2/3/3), then `LevelUpManager.check_level_up_by_power(card)`. Trundle2 also has this type, but its Skill has no `{Round Start}`, so it never fires here |
| `create_card_if_not_in_hand` | Draven1 | as Play |
| `create_multiple_cards` | Draven2 | as Play |
| `janna_draw_cost_reduce` | Janna2 | as Play |

**Round End** (gate `StartsWith("{Round End}")`)

| AbilityType | Cards | Behaviour |
|---|---|---|
| `kill_ally_buff` | Nasus1/2/3 | Kill the **weakest** ally Champion/Follower in this zone (excluding itself; the first card wins ties). If it can prevent death, wait 0.5 s and trigger prevention. Otherwise use the standard kill flow, with killer = the Nasus owner. **Then always** `+kill_power` (2/3/3) |
| `megatusk_deep_buff_lane` | Megatusk | If the owner is Deep, every resolved ally Champion/Follower in this zone (including itself) gets +`power_bonus` (1) |
| `terror_debuff_lane_enemies` | TerrorOfTheTides | Every resolved enemy Champion/Follower in the opposing zone gets −`power_reduction` (1) |

**Game End** (gate `Contains("{Game End}")`)

| AbilityType | Cards | Behaviour |
|---|---|---|
| `conditional_buff` → by **Name** | Trundle2 | Behold: count beheld Champions/Followers (not itself) with **base** Cost ≥ `mana_threshold` (5). Gain `behold_power` (2) × count |
| `conditional_buff` → by **Name** | Renekton3 | A random (`pick_random_target`) resolved enemy Champion/Follower in the opposing zone gets −`enemy_debuff` (3) |
| `aura_debuff` | Xerath3 | Gain the sum of current Power of the enemy Champions/Followers at zone slot index 0–1 (front row) in the opposing zone. The enemies keep their Power. (Xerath2 has the same type, but no `{Game End}` text) |
| `kill_ally_buff` | Nasus3 | Kill a random resolved enemy in the opposing zone with Power strictly below Nasus's (standard kill flow, with death prevention) |

**Other triggers**

| AbilityType | Cards | Trigger | Behaviour |
|---|---|---|---|
| `summon_sun_disc` | Azir1 | Game Start (from deck) | Summon BuriedSunDisc in the first free slot of zone `(1, allyRow(owner))`, tracking creation by "Azir1". Online: send `_receive_opponent_game_start_summon("BuriedSunDisc", 1, 1-row)`. The bot calls this with owner 0 |
| `on_discard_buff_create` | Sion1 | When discarded | Local-only. A random card in hand (local RNG) gets +`power_buff` (2). Then create a `Sion1` in hand |
| `last_breath_create` | Sion2 | Last Breath (inside kill flows) | Local-only. Create `SionReturned` in hand |
| `game_end_summon_from_hand` | Sion2 (via `HandAbilityType`), SionReturned | Game End, while in hand | Local-only. Choose the lane column where the owner is **losing** with the highest ally power. If there is none, use the lowest ally power; otherwise column 0. Remove the card from the hand and summon a new board card there. `best_power` starts at −1, so a losing lane at power 0 still qualifies |
| `swap_arrive_recall` | Ahri1, Ahri2 | After a swap tween (owner client) | Recall the weakest resolved allied Champion/Follower in the destination zone. Ties break on the lexicographically smaller `card_id`. Ahri2 also applies −`recall_cost_reduction` (1) to the recalled card. Then `_check_ahri_levelup()` and wait for level-ups |
| `swap_arrive_summon_blade` | Irelia1, Irelia2 | After a swap tween | Summon a `Blade` in the first free slot of the **origin** zone. Then `_check_irelia_levelup()`, wait, and send `_receive_opponent_irelia_blade_summon(col, 1-row, owner, creator)` |
| `levelup_on_death` | Tryndamere1 | Death prevention (`Card.gd`) | Level up to Tryndamere2 instead of dying |
| `survive_death` | Tryndamere2 | Death prevention | +`survive_power` (2) instead of dying |

**Marker types (no resolver handler)**

| AbilityType | Cards | Used by |
|---|---|---|
| `aura_ascended_buff` | Azir2, Azir3 | AuraSystem (Azir is matched by name; this type is the fallback) |
| `aura_debuff` | Xerath2, Xerath3 | AuraSystem (by name + level) and Game End (above) |
| `aura_blade_buff` | Blade | AuraSystem |
| `transform_landmark` | BuriedSunDisc | `LevelUpManager._check_sun_disc_transform` |
| `ascend_champions` | RestoredSunDisc | Nothing reads it. The effect lives in `LevelUpManager._on_sun_disc_restored` |
| `none` | Chip | nothing |
| `mordekaiser_play_kill`, `mordekaiser_round_end_purge` | Mordekaiser1/2 | **No handler.** The last commit removed Mordekaiser's logic but kept the data |
| `""` (27 cards) | see §21 | not implemented |

### 11.3 Shared helpers to implement once

- **`PickRandomTarget(list)`**: filter to `IsResolved`, then `list[sharedRng.Next(n)]`. Use the shared seeded RNG only (§15).
- **Standard kill flow**:
  1. If `target.CanPreventDeath()`: wait 0.5 s, call `OnDeathPrevented()`, and stop.
  2. Otherwise play `card_killed` and await it (or wait 0.5 s).
  3. `TrackKilledCard(target, killerPlayer, killerCardId)`.
  4. Free the slot, remove the card from the zone, reposition the zone, and set `Slot = null`.
  5. If the type is `last_breath_create`, await Last Breath.
  6. Destroy the card.
  7. Devourer only: also notify the power change.
- **`CalcZonePower(zone)`**: the sum of `GetCurrentPower()` over resolved cards.
- **Label refresh**: after any `power_modifier` change, update that card's power label. Most flows also call `_notify_zone_power_changed()`.

---

## 12. Level-up system

`LevelUpManager` entry points and the checks each one runs:

| Entry point | Called from | Runs |
|---|---|---|
| `check_level_ups_after_resolve(card)` | after each card resolves | Trundle(card owner), Azir, Irelia, Xerath, Nasus, Ahri, Kennen, Rumble, Sion, Draven, Nautilus(0 and 1), **await** Janna, Sun Disc transform |
| `check_level_ups_after_abilities()` | after the round start/end loops | same, minus Trundle |
| `check_level_ups_after_draw()` | after draws | await Janna |
| `check_level_ups_after_deep_state_change(p)` | `set_player_deep` | Nautilus(p) |
| `check_conditional_buff_level_ups()` | after **every** aura recalculation | `check_level_up_by_power` on every resolved, on-board card |
| `check_level_up_by_power(card)` | Renekton Round Start + above | if the card has `power_threshold` and `power_modifier ≥ threshold` → level up (Renekton1: 4) |

The per-champion conditions below apply to **resolved, on-board lv1 cards** (`card_slot_is_in != null`). "Local-only" means `owner == current_player_id`.

| Champion | Condition (BalanceValues) | Notes |
|---|---|---|
| Azir1 → 2 | ≥ `ally_threshold` (6) `summoned_cards` entries of the owner, excluding Azir's own id, that are **Landmark, Champion or Follower** | then `_check_ascended_sun_disc_upgrade` |
| Irelia1 → 2 | ≥ `ally_threshold` (7) summoned Champions/Followers (no Landmarks), excluding herself | |
| Trundle1 → 2 | `summoned_cards` has `IcePillar` **played from hand** by that owner | matched by `Name == "Trundle"` and `AbilityType == "create_card"` |
| Xerath1 → 2 | ≥ `ally_threshold` (4) of the owner's resolved on-board Champions/Followers (including Xerath) have `power_modifier + aura_power_modifier > 0` | then the Ascended upgrade check |
| Nasus1 → 2 | Local-only. ≥ `kill_threshold` (2) `killed_cards` with `killer_player_id == owner` | |
| Ahri1 → 2 | ≥ `recall_threshold` (3) `recalled_cards` with `recaller_player_id == owner` **and** `recaller_card_id == this card's id` | |
| Kennen1 → 2 | any single `card_id` appears ≥ `summon_threshold` (3) times in the owner's `summoned_cards` | |
| Rumble1 → 2 | Local-only. ≥ `discard_threshold` (4) owner discards | also triggered inline inside the Rumble Play ability |
| Sion1 → 2 | Local-only. Sum of base `Power` over the owner's discards + the owner's **resolved** summons ≥ `power_threshold` (32) | also called after every summon track and on-discard |
| Draven1 → 2 | Local-only. `axe_play_count ≥ axe_threshold` (2) on that Draven instance | |
| Nautilus1 → 2 | Local-only. The owner `is_deep` | the level-up fires the Nautilus2 level-up ability |
| Janna1 → 2 | Local-only. ≥ `draw_threshold` (12) `drawn_cards` of the owner | awaited |
| Renekton1 → 2 | `power_modifier ≥ power_threshold` (4) | via `check_level_up_by_power` |
| Tryndamere1 → 2 | would die | via death prevention |
| **Buried → Restored Sun Disc** | owner has ≥ `ascended_threshold` (2) resolved on-board Ascended champions at **Level 2** | then `_on_sun_disc_restored(owner)` |

**`_on_sun_disc_restored(owner)`**:

1. If the owner is local, draw from the deck every Ascended card whose **Name** isn't already beheld. Only one per name.
2. Level up **every** allied on-board Ascended lv2 champion to lv3 (iterate over a snapshot).

**`_check_ascended_sun_disc_upgrade(card)`**: after any Ascended champion reaches level 2, if the owner's Sun Disc is already Restored, push it straight to level 3.

Level-ups are started **without awaiting** (`card._perform_level_up(...)`). Callers use `CardManager._wait_for_level_up()` to wait for the pending counter to drain (§16).

---

## 13. Aura system

`AuraSystem.recalculate_auras()` runs on every `_notify_zone_power_changed()`:

1. Reset `aura_power_modifier = 0` on every card in `cards_by_zone`. Reset `aura_cost_modifier = 0` on every local hand card.
2. For each resolved, on-board card in `all_cards_in_play_order`, apply the matching aura. Checks run in this order, and the **first match wins**:
   - `Xerath` Level 2: every resolved enemy Champion/Follower **in the opposing zone** gets −`aura_debuff` (1). *(The card text says "back-row"; the code debuffs the whole lane. Port the code.)*
   - `Xerath` Level 3: resolved enemy Champions/Followers at slot index ≥ 2 (back row) in **every** enemy column get −1.
   - `Azir` Level ≥ 2 (or any `aura_ascended_buff`): other resolved allied **Ascended** Champions/Followers in all ally zones get +`aura_power` (2). *(Azir3's "Game End fires twice" is in CardManager §10.5.)*
   - `Irelia` Level 2: resolved on-board allied Champions/Followers with **base Cost 1** get +`power_increase` (1). Irelia herself costs 3, so she never qualifies. Iterate `all_cards_in_play_order`, not zones, because of row mirroring.
   - `aura_blade_buff`: every other resolved on-board `Blade` **in the same row** gets +`aura_power` (1).
   - `Nautilus` Level 2 (local owner only): Sea Monster cards in the local hand get `aura_cost_modifier −= cost_reduction` (3).
3. **Deep aura** (global): every resolved on-board card whose owner `is_deep` and whose static `Keyword` list contains `Deep` gets +3.
4. Refresh the power labels of all board cards. Refresh the hand cost labels (green/red) and glow.

---

## 14. Lanes, Swap Lane, Stun, Deep

### 14.1 LaneManager

- `setup_lanes(ids)`: store `[left, mid, right]` and set `_revealed = [true, false, false]`. Fire the **immediate** effect for column 0.
- `on_round_start(turn)`:
  - turn 2 → reveal column 1; turn 3 → reveal column 2.
  - A reveal runs `Board.reveal_lane_visuals` and then the immediate effects.
  - If a revealed lane is **Noxkraya Arena** and the turn is 5, activate the restriction on that column.
- `on_round_end(turn)`:
  - **Ornn's Forge** at turn 4.
  - **Sunken Temple** at turn 3.
  - Then clear Noxkraya.
- `is_placement_restricted(zone)`: returns `noxActive && zone.col != noxCol`.

| Lane | When | Effect |
|---|---|---|
| Hexcore Foundry | on reveal | `Deck.draw_cards(1)`. Each client draws for itself |
| Rockfall Path | on reveal | Summon `Chip` in this column for **both** players (creator −1 = lane), then notify the power change |
| Ornn's Forge | end of turn 4 | +1 permanent Power to every resolved Champion/Follower in this column, both rows |
| Sunken Temple | end of turn 3 | If the local hand is non-empty, move one random card (**global RNG in the source**, see §15) into the deck at a random position with its `cost_mod`. Then draw 1 |
| Noxkraya Arena | turn 5 PLAY | Every non-spell card must be played in this column |

**Hidden lanes** show no name, the text "Will be revealed on turn N" and no art. Lane objects carry `lane_id` and `lane_reveal_turn` (−1 = revealed) for the right-click preview. Their collider is on layer **Lane (8)**.

### 14.2 SwapLaneManager (Elusive)

- `SWAP_DURATION = 1` s.
- `pending_swaps` entry: `{card, swapped_by_player_id, cause_card_id, from_zone, from_slot, to_zone, to_slot, turn_number}`.
- `swap_history` is permanent: `{card_id, owner_player_id, swapped_by_player_id, cause_card_id, from_zone, to_zone, turn_number}`.
- `get_swap_count_for_card(id, player)` exists for future level-ups.

`execute_swaps()`:

1. Sort the swaps so the flip-first player's come first. Reset the step semaphore.
2. **Snap back.** For each swap: remove the card from `to_zone` and free its current slot. Then `insert_card_to_zone_at_slot(from_zone, card, from_slot)` and reposition `from_zone`.
3. **Animate one at a time.** For each swap:
   1. If `to_slot` is occupied now, cancel it; the card stays at its origin.
   2. Otherwise remove the card from `from_zone`, free its slot and reposition `from_zone`.
   3. Insert the card at `to_slot` and mark the slot.
   4. Tween the position over 1 s (InOutSine) at z 10, then set z 0.
   5. If the local player owns the card, `await ExecuteSwapArriveAbility`. If online and the type starts with `swap_arrive_`, send `_rpc_notify_swap_step_done`.
   6. If the opponent owns the card and it has such an ability, wait on the semaphore: a counter plus an event.
   7. Reposition `to_zone` and append to the history.
4. Clear the pending list.

### 14.3 StunManager

- `apply_stun(card, turn)`: not stackable. Adds the runtime keyword badge "Stun".
- `has_stun(card)`.
- `on_resolve_start(turn)`: removes entries whose card is gone or where `stunned_on_turn < turn`, and removes their badges.
- `reset()`.
- A stun blocks the card's Elusive self-swap, its Round Start and its Round End.

### 14.4 Deep

A player becomes Deep when their deck reaches 0, whether through a normal draw, a specific draw or the bot's draws. It is **permanent**, even if cards later return to the deck.
Effects:

- the Deep aura (+3 on Deep-keyword units);
- the Megatusk and Devourer conditions;
- the Nautilus level-up.

---

## 15. Determinism and RNG

Both clients run the **same resolve simulation locally**; no server simulates the match. They stay in sync through:

1. RPCs for every *owner-only* effect: discard, recall, power buff, level-up, summon mirror.
2. A **shared seed** for every random choice that both clients make independently.

The source uses Godot's **global** RNG in several places. Recreate the streams explicitly:

| Stream | Seed | Used for |
|---|---|---|
| **SharedRng** (`System.Random`) | reseed at RESOLVE start **and** at `end_game` from a **perspective-independent** value, e.g. `turn*7919 + flipFirstNetworkId*1337`, or a host-broadcast match seed combined with the turn. **Do not** copy the source formula as-is (see the hazards below) | `PickRandomTarget` (Kennen stun, Renekton3 debuff, Nasus3 kill, Devourer kill) |
| **LocalRng** (`System.Random`, time-seeded) | once | Owner-only picks: Rumble discards, Rumble2 pool pick, Nautilus2 shuffle, Sion buff target, Updraft insert position, Sea Scarab pick |
| **Cosmetic** (`UnityEngine.Random`) | – | Dissolve `noise_seed` |
| **Host-only** (any) | – | Flip-first choice, flip-first tie-break, lane ID shuffle (the host broadcasts the result) |
| **Per-client** | – | Deck shuffle (each client shuffles only its own deck), bot choices (offline only) |

The source has several **parity hazards**. They are written down here so the port does not copy them blindly:

- **The "shared" seed is not shared online.** The formula `seed(turn*7919 + flip_first_player_id*1337)` uses the **local** flip-first ID. `_sync_flip_first` converts the network ID into local perspective, so the player with priority stores 1 and the other stores 0. Host and client therefore seed differently, and every `pick_random_target` can pick different targets on each side. In the port, seed from the flip-first **network** ID or from a host-broadcast seed.
- **Owner-only effects with no mirror RPC.** In each case below, only the owner's client applies the effect:
  - `devourer_deep_kill_enemy` is owner-gated and sends no RPC. The opponent's client never kills the target, and only one side consumes the shared RNG.
  - `game_end_summon_from_hand` (Sion2/SionReturned) is owner-gated, and the third Game End pass only iterates the local hand. The opponent's Sion never appears on your board, so the two clients can compute **different winners**.

  The port needs mirror messages for both (§17.3).
- `play_discard_dissolve` calls the global `randf()`, and Sunken Temple calls the global `randi()`. Both advance the shared stream on one client only, which can desync later shared picks. In the port, route both to Cosmetic/LocalRng. This is a bug fix, so record it.
- `_receive_card_resolve_done` is keyed by `card_id` alone. Two copies of the same card flipping in one resolve can therefore collide. In the port, key it by a per-play **network instance ID** instead.
- `seed()` also affects the bot and lane logic, which run on the global RNG. Separate streams remove this coupling.

**Ordered iteration:** Godot dictionaries iterate in insertion order, but C# `Dictionary<K,V>` does not guarantee order. Load `cards.json` into a `List<CardData>` (plus an ID index), and build every "iterate all cards" pool from the list. That covers Rumble2, Nautilus2, `GetCardIdByName` and collectibles.

---

## 16. Async model

The GDScript relies on coroutines that **await other coroutines and return values**. For example, `var did_fire = await card.on_round_start()`, and ability chains nest 3–4 levels deep.

Use **UniTask** (or Unity 6 `Awaitable`):

```csharp
public async UniTask<bool> OnRoundStart() => await AbilityResolver.ExecuteRoundStartAbility(this);
await UniTask.Delay(TimeSpan.FromSeconds(0.7f), cancellationToken: matchCt);   // CARD_PAUSE_TIMER
await tween.ToUniTask(); await animator.PlayAsync("card_flip_play");
```

- Pass one match-scoped `CancellationToken` everywhere, so leaving the scene stops all chains.
- Guard every `await` continuation with `if (card == null) return;`, because objects can be destroyed mid-await.
- **Level-up lock.** The source uses `_level_up_in_progress`, `_level_up_pending` and 0.05 s polling. Port it as:

  ```csharp
  readonly SemaphoreSlim levelUpGate = new(1, 1); int levelUpPending;
  // in PerformLevelUp: levelUpPending++; await levelUpGate.WaitAsync(ct); try { ...animation... } finally { levelUpGate.Release(); levelUpPending--; }
  public UniTask WaitForLevelUp() => UniTask.WaitUntil(() => levelUpPending == 0, cancellationToken: ct);
  ```

  Level-ups are usually **started without awaiting** (fire and forget: `PerformLevelUp(id).Forget()`). The pending counter is how the resolve and ability loops block until they finish. Keep that contract.
- **Cross-client waits** (`_wait_for_opponent_card_resolve`, the swap step semaphore) become `UniTaskCompletionSource` values in a dictionary, completed by the RPC handler. If the RPC arrives before the wait begins, store it as already completed. That is what the source's counter and dictionary achieve.

---

## 17. Networking

### 17.1 Topology and perspective

- 2 players, ENet, `DEFAULT_PORT = 9999`, `MAX_PLAYERS = 2`.
- The host is **network player 0** and the client is **network player 1**. Each machine renders itself as **local player 1 (bottom, row 1)** and the opponent as **local player 0 (row 0)**. `CardManager.current_player_id` is always 1.
- When sending a board position to the peer, **mirror the row**: `(col, 1 - row)`. Received opponent cards are always created with `owner_player_id = 0`.
- Flip-first travels as a *network* ID. Each client maps it back: `local = (networkId == myNetworkId) ? 1 : 0`. The host converts local → network with `1 - local`.
- `NetworkManager.is_online()` means a connected peer and not offline mode. Offline mode fakes host mappings and turns the bot on.
- `NetworkManager` also defines `local_zone_to_network` and `network_zone_to_local`, but nothing calls them. Everything uses the direct `1 - row` mirror.

### 17.2 RPC inventory (from the `@rpc` annotations in the source)

| # | Owner script | RPC | Godot mode | Direction / purpose |
|---|---|---|---|---|
| 1 | GameManager | `_on_player_end_turn(peer_id)` | any_peer | client → server (`rpc_id(1)`), and the host calls it locally |
| 2 | GameManager | `_proceed_to_resolve()` | authority, call_local | server → all: start SWAP_LANE/RESOLVE |
| 3 | GameManager | `_sync_lane_assignment(lane_ids[])` | authority, call_local | server → all |
| 4 | GameManager | `_sync_flip_first(network_player_id)` | authority, call_local | server → all |
| 5 | NetworkManager | `_receive_player_assignment(player_id)` | authority | server → new client (`rpc_id`) |
| 6 | NetworkManager | `_notify_game_can_start()` | authority, call_local | server → all when 2 players are connected |
| 7 | AbilityResolver | `_receive_opponent_game_start_summon(card_id, col, row)` | any_peer | owner → peer: Azir's Sun Disc |
| 8 | AbilityResolver | `_receive_opponent_irelia_blade_summon(col, row, owner, creator_card_id)` | any_peer | owner → peer |
| 9 | CardManager | `_receive_undo_all_plays()` | any_peer, call_remote | → peer: clear pending opponent cards |
| 10 | CardManager | `_receive_opponent_discard(card_id, by_card_id)` | any_peer | → peer: track the discard |
| 11 | CardManager | `_receive_card_resolve_done(card_id)` | any_peer | owner → peer: resolve lockstep |
| 12 | CardManager | `_receive_opponent_card_play(card_id, col, row, power_mod)` | any_peer | → peer: queue a face-down play |
| 13 | CardManager | `_receive_opponent_swap(card_id, from_col, to_col)` | any_peer | → peer: queue a swap for SWAP_LANE |
| 14 | CardManager | `_receive_opponent_level_up(old_id, new_id)` | any_peer | → peer: animate the level-up on their copy |
| 15 | CardManager | `_receive_opponent_champion_level_up_global(old_id, new_id)` | any_peer | → peer: silently upgrade the other copies and the proxy hand IDs |
| 16 | CardManager | `_receive_opponent_became_deep()` | any_peer, call_remote | → peer |
| 17 | CardManager | `_receive_opponent_power_buff(card_id, buff)` | any_peer | → peer: apply the buff to the opponent's card with that ID |
| 18 | CardManager | `_rpc_notify_swap_step_done()` | any_peer | → peer: release the swap semaphore |
| 19 | CardManager | `_receive_opponent_recall(card_id, col, row)` | any_peer | → peer: remove the card from the board |
| 20 | CardManager | `_receive_opponent_hand_ids(card_ids[])` | any_peer | → peer: for behold |

### 17.3 Unity implementation

There are no synced transforms or physics, only discrete messages. The simplest faithful design is therefore **one `MatchNet : NetworkBehaviour`** in `Main`, holding all 20 RPCs and forwarding them to the services. That also solves "RPCs on autoloads" (7 and 8).

| Godot | Netcode for GameObjects |
|---|---|
| `rpc("f", …)` with `any_peer` (broadcast to others) | `[Rpc(SendTo.NotMe)] void FRpc(...)` |
| `rpc("f")` with `authority, call_local`, called on the server | `[Rpc(SendTo.Everyone)]`, called only when `IsServer` |
| `rpc_id(1, "f", …)` | `[Rpc(SendTo.Server)]` |
| `rpc_id(peer, "f", …)` | `[Rpc(SendTo.SpecifiedInParams)]` + `RpcParams` |
| `multiplayer.is_server()` / `get_unique_id()` | `NetworkManager.Singleton.IsServer` / `LocalClientId` |
| `ENetMultiplayerPeer.create_server(9999, 2)` / `create_client(ip, 9999)` | `UnityTransport.SetConnectionData(ip, 9999)` + `StartHost()` / `StartClient()`. Enforce 2 players with the connection-approval callback |
| `Array` of strings | `string[]` isn't a native RPC parameter. Send a joined string, or wrap it in an `INetworkSerializable` |

Mirror/FishNet work the same way: `[ClientRpc]`/`[Command]` or `[ObserversRpc]`/`[ServerRpc]`.

**Add two messages the source lacks** (see §15). Without them, parity means parity with a desync:

- `SummonCardAtZone(cardId, col, row, owner, creatorCardId)`: covers the Sion hand Game End summon, and can replace #7 and #8 with one generic message.
- `KillCardAtZone(col, row, slotIndex, killerCardId)`: covers Devourer's kill.

**Play-time network flow:**

1. A drop sends #12 immediately. The peer only queues it and spawns the card at RESOLVE.
2. End Turn → #1. When both players are in, #2 runs everywhere.
3. SWAP_LANE applies the queued #13s, then the swap-arrive abilities with #18 lockstep.
4. RESOLVE: both flip the same sorted list. The owner runs owner-only effects and emits #10/#14/#17/#19/#8. Then #11 releases the peer's wait.
5. End Turn and post-resolve send #20 (hand IDs for behold).
6. Round end: the host computes the priority winner → #4.

---

## 18. Bot

This is `BotManager`, enabled by **Play Offline (Solo)** in the Lobby.

- `BOT_DECK = [Azir1, Renekton1, Nasus1, Xerath1, Tryndamere1, Trundle1, Ahri1, Kennen1, NavoriConspirator, SolitaryMonk]`
- `setup_bot(3)`:
  1. Copy and shuffle the deck, then draw 3.
  2. Fire each distinct `{Game Start}` card in `BOT_DECK` once, with owner **0**. Azir's Sun Disc lands on row 0.
- `on_round_start()` (after the mana refill):
  1. Draw 1. If the deck is now empty → `set_player_deep(0)`.
  2. Collect the hand cards with `Cost ≤ player 0's current mana`. Collect the columns whose row-0 zone has fewer than 4 cards.
  3. Pick one random card and one random column. Spend the mana, remove the card from the hand, and call `CardManager._receive_opponent_card_play(id, col, 0)`.
  4. The card is then handled exactly like an online opponent's play: face-down, flipped at RESOLVE.
- The bot never swaps, undoes, or plays spells. Owner-only abilities on its cards (e.g. Trundle's `create_card`) skip themselves because `owner != 1`.

---

## 19. Menus and UI scenes

### 19.1 HomeScreen

- Background `Color(0.08,0.07,0.1)`.
- Centred VBox, min width 320: title "RUNETERRA FORGE" (48 pt), a 32 px spacer, then **Play** → `Main`, **Deck Builder** → `DeckBuilder`, **Card Catalog** → `CardCatalog`. Buttons are 52 px tall.

### 19.2 LobbyUI (inside Main)

- Centred 400×360 panel: title "Card Game Lobby", **Host Game**, an IP field (placeholder `127.0.0.1`), **Join Game**, **Play Offline (Solo)**, and a status label.
- Host/Join disable all three buttons and show status text.
- **Offline:** `start_offline()`, `bot_enabled = true`, hide the panel, `start_game()`.
- Online: `game_can_start` → hide the panel and `start_game()` on both machines.
- Status messages: "Hosting... Waiting for opponent to join.", "Connecting to %s...", "Opponent connected! Starting game...", "Opponent disconnected!", "Failed to host/connect. Error: %d".

### 19.3 SettingsUI (sort order 20)

- A top-right "Settings" button (−120,10)…(−10,50) toggles a centred 400×350 panel.
- Panel buttons:
  - **1920 x 1080** and **1600 x 900**: leave fullscreen if needed, then resize.
  - **Fullscreen** and **Windowed**.
  - **Close**.
- Each action closes the panel.

### 19.4 DeckBuilder and CardCatalog

**Shared:** the filter bar has region toggle buttons (40×40 icons) and cost toggles; the combination is **OR within a group and AND across groups**. Name search is case-insensitive.
Grids are built from `GetCollectibleCards()`. Right-clicking a card opens `CardPreview.ShowPreviewById`.

**DeckBuilder:**

- Left panel, 488 px wide:
  - header: deck name field (default "My Deck") and a "Load deck…" dropdown;
  - "Deck (n / 12)" label;
  - deck grid, 3 columns, 4 px spacing;
  - footer: **← Back**, **Cancel** (revert to the last saved deck), **Save** (`DeckStorage.SaveDeck`; an empty name becomes "My Deck").
- Right: the collection grid, 5 columns, 8 px spacing.
- Clicking a collection card toggles it in the deck (max 12, at most one copy per card ID).
- Cards already in the deck get a 50 % black highlight.
- The deck grid is sorted Champions first, then cost, then name. Clicking a deck card removes it.
- Regions: 11, with no Ixtal and no Void. Costs: 0–5 and 6+.
- Tile size: `colW = (viewportW − 488 − 8*4) / 5`, `colH = colW * 176/126`. Deck tiles: `(472 − 4*2)/3`.

**CardCatalog:**

- Back button, 13 regions (adds Ixtal and Void), costs 1–5 and 6+ (no 0).
- 7 columns: `colW = (viewportW − 32 − 8*6)/7`.
- Left or right click opens the preview.

**MiniCard:** the source renders a full card scene into a `SubViewport` per tile. In Unity, build **`MiniCardUI` as a uGUI prefab**: Image layers for base, art (masked), mana, power and subtype, plus TMP text.

- Drive it with the same `PopulateCardVisuals` data mapping, via an interface that both the world-space and UI views implement.
- It exposes `CardClicked(id)`, `CardRightClicked(id)`, `SetInDeck(bool)` and `SetDisplaySize(w, h)`.

### 19.5 CardPreview / LanePreview overlays (sort order 15)

**Layout:** a 39 % grey backdrop (clicking it closes the overlay), **✕** at (12,12) size 60, **◀** / **▶** at x 360 / 1440, y 490, size 120×100, and a page label "i / n" at y 980. The content is centred at (960,540).

**CardPreview:**

- `ShowCardPreview(sourceCard)` (from right-click) or `ShowPreviewById(id)`.
- Pages = `PreviewTooltip`, or `[id]` if empty. Start on the clicked ID's index.
- Instantiate the card prefab at scale **1.0**, disable its collider, populate it and hide its back.
- Pass the **live source card** only when the page ID equals the source card's ID, so that page shows current power.
- Prev/next are disabled at the ends. **Esc** closes the overlay.

**LanePreview:**

- Pages = `lane:<id>`, plus `card:<id>` for each `RelatedCard`, but related cards are included **only if the lane is revealed**.
- Lane page: instantiate `Lane.prefab` at scale 3. A hidden lane shows the placeholder text.
- Card page: as CardPreview, without a live source.
- The navigation controls are hidden when there is a single page.

While either overlay is open, `InputRouter` ignores game input.

### 19.6 Lane prefab (`Lane.tscn`)

- `LaneBorder` (z −2).
- `LaneName`: TMP at (−80,−55)…(80,−31), Beaufort Bold 20, outline 3.
- `LaneDesc`: (−80,20)…(80,62), Univers Cn 16, spacing −4, outline 2.
- `LaneBase` (`lane_base.png`, z −3) acts as a SpriteMask for `LaneSprite` (scale 0.33).
- Capsule collider (radius 10, height 20, scaled ×10/×9) on layer **Lane**.

### 19.7 KeywordBadge

- A NinePatch `card_keyword.png` with 10 px borders → Unity 9-slice sprite, sliced to 10 px.
- Inside it: an HBox with padding 12/8 and spacing 8, holding a 36×36 icon (4 px margin) and the name label (Beaufort Medium 26, colour (0.933,0.8,0.486), upper case).
- The minimum size is the content size plus the margins. `ContentSizeFitter` does this in Unity.

---

## 20. Asset pipeline

1. **WebP → PNG.** Unity does **not** import `.webp`. Convert these folders:
   - `Assets/CardSprites` (73 files; several followers share `DummySprite.webp`);
   - `KeywordSprites` (20);
   - `RegionSprites` (13);
   - `card_back.webp`, `card_skillshadow.webp`.

   ```bash
   # ImageMagick
   find Assets -name '*.webp' -exec sh -c 'magick "$1" "${1%.webp}.png"' _ {} \;
   # or libwebp: for f in $(find Assets -name '*.webp'); do dwebp "$f" -o "${f%.webp}.png"; done
   ```

2. **Remap paths in the data.** `res://Assets/CardSprites/Azir1.webp` becomes the Addressables key `CardSprites/Azir1` (or a `Resources/CardSprites/Azir1` path). Do the same for `RegionSprites/<Region>` and `KeywordSprites/<Keyword>`, which the code builds at runtime. Lane sprites are already PNG.
3. **Sprite import:** Texture Type *Sprite (2D and UI)*, **PPU 100**, pivot centre, *Filter Bilinear*, compression *High Quality*, mip maps off. `card_keyword.png` needs 10 px borders in the Sprite Editor (9-slice).
4. **Fonts:** create TMP Font Assets for `BeaufortforLOL-Bold`, `BeaufortforLOL-Medium`, `UniversCnRg` and `UniversRegular`. The other weights ship but are unused. Add an outline material preset per font, since outlines are used on names, skills and lane text.
5. **TMP Sprite Asset** from `KeywordSprites`. Name each glyph after its keyword, for inline `<sprite name="Stun">`.
6. **Other textures:**
   - `Assets/CardComponent/*.png`: unit, spell and landmark frame pieces;
   - `LaneComponent/*` (`lane_base`, `lane_border`, `lor_boardvisual_template`);
   - `card_slot.png`, `card_template.png` and `RuneterraForge.png` (logo);
   - `icon.svg`: convert to PNG for the app icon.

> Card art and fonts belong to Riot Games (*Legends of Runeterra*). Keep the same distribution caveats as the Godot build.

---

## 21. Current state of the source

Port **behaviour from the code, not from card text**. Where the two differ, the code is the source of truth for parity.
Everything below exists as **data only**. Port it as data, and don't invent behaviour to "achieve parity":

- **Cards with no ability implemented** (`AbilityType ""` or no handler): Viktor1/2, HexCoreUpgrade, Lucian1/2, Garen1/2, Quinn1/2, Valor, Hecarim1/2, SpectralRider, Zed1/2, LivingShadow, Ryze1/2, the five World Rune shards (ShardofViolence/Betrayal/Reverence/Hope/Madness), Galio1/2, Nautilus1 (its level-up is handled by LevelUpManager), TheBeastBelow (vanilla), and Mordekaiser1/2 (types with no handler).
  - Most of these are **not collectible**. The collectible ones still appear in the Deck Builder and Catalog.
  - Ryze1 has a `{Game Start}` skill with no type, so `trigger_game_start_abilities` only logs "unknown Game Start ability type".
- **Keywords with behaviour:** Elusive (swap), Stun and Deep only. Barrier, Challenger, Fearsome, Tough, Regeneration, Overwhelm, Scout, Ephemeral, Augment, Fast, Slow, Landmark and the rest are icons only.
- **Text that differs from the code:**
  - Xerath2's aura hits the whole enemy lane.
  - Ice Pillar's mana bonus is hardcoded to 5.
  - Rumble2 grants no Augment.
  - Janna2's "when you draw, reduce cost" is only applied to cards it draws itself.
  - Azir3 lists Barrier (no effect).
- **Decks:** a match always uses the 12-card list hardcoded in `Deck.gd`: Azir1, Renekton1, Nasus1, Xerath1, Tryndamere1, Ahri1, Kennen1, NavoriConspirator, Janna1, Draven1, Rumble1, Sion1. A commented-out Sea Monster test deck sits next to it. The bot has its own list. **`DeckManager`'s saved decks are never loaded into a game.**
- **Unused code:** `summon_copy`, `buff_allies` and `damage_enemies`; `NetworkManager.local_zone_to_network` / `network_zone_to_local` / `is_local_action`; `get_beheld_cards_filtered` / `count_beheld_matching`; `card_glow_outline.gdshader` and `card_flash.tres`; `KeywordDatabase` and `VocabDatabase`.
- **Source quirks to decide on:**
  - `CardSpell`/`CardLandmark._refresh_keyword_display` look up `KeywordSprite` directly on the badge root, but the badge nests it at `HBoxContainer/SpriteMargin/KeywordSprite`. Adding a runtime keyword to a spell or landmark would therefore error. The Unity port should use one shared badge builder.
  - Undo leaves `summoned_cards` entries in place (§10.2).
  - Online desyncs: the resolve/game-end seed differs per client, and Devourer's kill and Sion's hand Game End summon are never mirrored to the opponent (§15).
  - The RNG hazards are listed in §15.
- **Singletons are never reset.** Starting a second match in the same session would keep old state in `StunManager`, `SwapLaneManager.swap_history`, `LaneManager` and `BotManager`. The Unity port needs a `ResetForNewMatch()` on every service.

---

## 22. Milestones and parity test plan

### Milestones

| # | Milestone | Done when |
|---|---|---|
| M0 | Project setup | URP 2D, camera, CanvasScaler, packages, folders; WebP converted; fonts and the TMP sprite asset built |
| M1 | Data | `cards.json` (74), `lanes.json` (5), `keywords.json` (15), `vocab.json` (13) load; ordered list plus ID index; `CardTextFormatter` unit-tested against sample strings |
| M2 | Card views | Unit, Spell and Landmark prefabs render any card ID identically to Godot (compare screenshots at 1.0 scale); dissolve and flip animations |
| M3 | Menus | HomeScreen, Card Catalog, Deck Builder with save/load, CardPreview |
| M4 | Board and hand | Slot grid, spell zones, lanes (hidden/revealed), hand fan, drag and drop with every placement rule, undo, power labels |
| M5 | Turn loop (offline, no abilities) | 6 turns, mana, draw, face-down plays, flip-first resolve order, win screen, priority recalculation |
| M6 | Abilities | Every AbilityType in §11, the standard kill/summon helpers, trackers, the phase loops including the three Game End passes |
| M7 | Level-ups and auras | Every §12 condition, level-up animation plus global lock, upgrade all copies, Sun Disc restore, every §13 aura, Deep |
| M8 | Lanes, Swap, Stun | All five lane effects, Elusive swap drag plus the SWAP_LANE animation, swap-arrive abilities, stun gating and expiry |
| M9 | Bot | Offline match against the bot is fully playable |
| M10 | Networking | Host/join over LAN; all 20 RPCs; perspective mirroring; lockstep resolve; no desync over 20 scripted matches |
| M11 | Polish and build | Settings, Bloom and the level-up light sweep, Windows build named `RuneterraForge` by `TheAnyDev` |

### Parity tests

Write these as EditMode/PlayMode tests with the SharedRng/LocalRng injected:

1. **Formatter:** each card's `Skill`/`LevelUp` → expected TMP string. Generate the expected values once from Godot by printing `format_card_text`.
2. **Geometry:** `SlotPosition(col,row,i)` for all 24 slots plus 8 spell slots, and the hit-test table (including gap points), must equal the Godot values.
3. **Resolve order:** played cards from both owners with flip-first 0 and 1 → expected flip sequence.
4. **Scripted scenarios**, one per ability or level-up. Build the board state directly, run the phase, and assert the power/trackers. For example:
   - Rumble1 with hand costs {1,3,6} → 3 discards, +6 Power, level-up;
   - Nasus Round End with a Tryndamere1 as the weakest ally → Tryndamere levels up and Nasus still gets +2;
   - Azir2 + Renekton1 → the aura pushes Renekton to his threshold and he levels up;
   - Xerath3 Game End front-row sum;
   - Sion2 hand Game End lane choice.
5. **Game End passes:** Azir3 with two Ascended allies that have `{Game End}` → each fires exactly twice. Duplicate references in `all_cards_in_play_order` fire once.
6. **Determinism:** run two in-process simulations with mirrored perspectives and the same seeds and RPC stream. Assert identical board power per lane after every phase.
7. **Golden replays:** record full offline Godot matches (log every `print`). Replay the same inputs in Unity with the bot and shuffles seeded, and diff the logs. The source's verbose `print` calls make this practical.

---

## Appendix A: Optional true-3D presentation

Do this only after M10, as a **view-layer swap**. The logic services never touch transforms directly except through `CardView`, `Board` and `PlayerHand`, so the change stays contained.

- **Camera:** perspective, ~35° pitch, looking at the board plane (XZ). Keep a `Coords.ToWorld3D(gx, gy)` mapping Godot pixels to the board plane: `x = (gx−960)/100`, `z = (540−gy)/100`, `y = 0`.
- **Cards:** a thin box or two back-to-back quads (front = the rendered card, back = `card_back`). Render the front either:
  - with a per-card **RenderTexture** from the existing 2D prefab (cache it, and rebuild only on `PopulateCardVisuals`), or
  - with a world-space Canvas on the quad.
- **Flips:** replace "scale X to 0.05" with a real **Y-axis rotation of 180°** over the same durations (0.2 s draw, 0.7 s play-reveal with a lift toward the camera instead of scale 3). The level-up spin becomes ~10 half-turns over 1.63 s.
- **Hand:** a curved fan anchored to the camera. Use the same index-0-is-newest ordering and the same spacing, converted to arc angle.
- **Hit-testing:** `Physics.Raycast` against box colliders on the `Card`, `CardSlot`, `Deck` and `Lane` layers replaces the 2D point queries. Keep the Godot-pixel math for drop zones by projecting the ray onto the board plane and converting back with `Coords.ToGodot`.
- **Lighting:** URP Lit with a key light. The level-up sweep becomes a moving spot light or an emissive shader stripe. Keep Bloom.
- **Dissolve:** convert the shader to URP Lit/Unlit (same math, with a world-space or UV noise input).

---

## Appendix B: Gotcha checklist

- [ ] Every Godot pixel position goes through `Coords.ToWorld`, with y flipped.
- [ ] Sprites are at PPU 100, and the scale constants 0.2 / 0.21 / 0.15 / 0.1 / 0.5 / 1.0 / 3.0 are kept.
- [ ] Slot append order: `[3,2,1,0]` for row 0, `[0,1,2,3]` for row 1. Front row = index 0–1.
- [ ] Hand index 0 = **newest** card (`insert(0)`). Updraft takes the **oldest** (end of the list). Spinning Axe discards index 0.
- [ ] Trigger gates: Round Start `Contains`, Round End `StartsWith`, Game End `Contains`, Game Start `StartsWith`.
- [ ] `LevelUpTo` null/""/self-reference handled. Level-up checks require `Level == 1` (or 2 for the Ascended → 3 path).
- [ ] The level-up changes `cardId` **before** the animation, and `displayCardId` freezes the shown stats until it runs.
- [ ] `IsResolved` gating everywhere: zone power, targets, auras, level-up checks.
- [ ] `card_slot_is_in == null` means "no longer on the board". The loops skip these because `all_cards_in_play_order` is never pruned.
- [ ] SharedRng is reseeded at RESOLVE and at GAME_END from a **perspective-independent** seed (not the local flip-first ID). Owner-only picks use LocalRng. Cosmetics never touch SharedRng.
- [ ] Devourer's kill and Sion's hand Game End summon are mirrored to the opponent.
- [ ] The card list is ordered, not a C# `Dictionary`, when building random pools.
- [ ] Opponent cards are always `owner = 0`. Rows are mirrored on send. Flip-first is sent as a network ID.
- [ ] All 20 RPCs are ported. Resolve-done waits are keyed by instance ID. Swap-step waits use a counter, not a bool.
- [ ] Every service is reset per match (`StunManager`, `SwapLaneManager`, `LaneManager`, `BotManager`, CardManager trackers).
- [ ] Game input is blocked while a preview overlay is open. Esc closes the overlays.
- [ ] WebP is converted, the `res://` paths are remapped, and a TMP sprite asset exists for the keyword icons.


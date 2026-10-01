# Runeterra Forge: Godot Roadmap

Runeterra Forge stays on Godot. This roadmap collects:

- the engine upgrade (4.6 → 4.7);
- the problems found in the current code while writing `UNITY_REBUILD_GUIDE.md`, rewritten as Godot fixes;
- a plan for animation and VFX, building on the Stun effect that already ships;
- a multiplayer rework for friends/LAN, where the host runs the rules (Part 3).

Where the card text and the code disagree, **the code is the source of truth**.

---

## Roadmap overview

| Phase | Status | Focus | Why in this order | Size |
|---|---|---|---|---|
| **0. Upgrade to Godot 4.7** | ✅ **Done**: Godot 4.7.2, commit `63570fe` on `upgrade/godot-4.7`. No regressions vs the 4.6 baseline. Manual GUI smoke test + Windows export still pending | Engine migration (§0) | Low risk. All later work (particles, shaders, new scenes) is built on the target version | S |
| **1. Critical fixes (cheap ones only)** | ✅ **Done**: commit `088f423` (branch `fix/phase-1-critical`, merged into `upgrade/godot-4.7`). `tools/lan_selftest.sh` passes (and fails with the old seed formula). Manual GUI check (F9 Stun, spell badge) + a LAN match with real plays still pending | Seed fix, cosmetic RNG split, per-match reset of singletons, keyword badge path bug (§1.1 a+d, §1.6), plus a found bug: `CardSpell.tscn` had no script attached. Adds debug-only auto-connect flags (`--autohost`, `--autojoin=<ip>`, `--autoendturn`, `--quit-on-end`), `[SYNC]` log lines, and `tools/lan_selftest.sh` to test LAN sync unattended | Correctness first. The other desync fixes (§1.1 b, c, e) are **superseded by Phase 3**, so don't hand-write mirror RPCs | S |
| **2. Quick wins** | ✅ **Done**: branch `phase2/integration` (merged into `upgrade/godot-4.7`). Offline smoke x3 + `tools/lan_selftest.sh` x2 pass. Manual GUI check (Deck Builder save/restart/load, Xerath2/Janna2/Rumble2 in a match, undo, recall+Stun, MiniCard sizing) + a LAN match with real plays still pending | Saved decks used in matches, text/code mismatches, undo tracker, MiniCard SubViewport warning (§1.2, §1.5, §1.6). **Planned and shipped:** saved decks reach a match (§1.2); §1.5 fixed against the card text — **Xerath2 back-row only**, **Janna2 passive applies to every draw including bot draws**, **Rumble2 grants the Augment badge**, plus the Ice Pillar mana ramp; undo drops stale `summoned_cards`; recall clears Stun; the MiniCard SubViewport warning is gone. **Extras found while in there:** the active deck is persisted in `user://active_deck.json`; Deck Builder *load* sets the active deck; only full 12-card decks are used in a match (otherwise the default deck); undo restores hand glow; the Augment sprite path is fixed | Small, visible improvements for players | S |
| **3. Multiplayer rework: host runs the rules** | 🔄 In progress. **M1 Foundation ✅** (`45df9e1`). **M2 Rules core ✅** (`68f60ac`). **M3 Abilities ✅** (`9596f52`). **M4 Presenter + offline switch ✅ implemented** (commit `8f73034`, on `upgrade/godot-4.7`): **offline vs bot now runs on the new engine** — `MatchController` (host + bot + intents) and `MatchPresenter` (engine events → the existing visuals/animations, fed only redacted events); `MatchSnapshot.for_viewer`; `--engine=old` keeps the old offline path until M5; online/LAN unchanged. `tools/offline_selftest.sh` (autoplay + `--verify-view`) green on 9 seeds; 513 tests. Manual GUI check pending. Next: M5 Online | Split game state from nodes, rules engine emitting events, presenter, intents + filtered events over ENet, LAN discovery (Part 3) | Removes desyncs by design and hides hidden information. It must come **before** the event VFX and cinematics, because those hook onto its event stream | L |
| **4. VFX foundation + status effects** | Planned (Stun ✅ shipped) | Generalise the Stun pattern. Elusive float, Deep glow (§2.1, §2.2) | Reuses shipped code. Status effects read card state, so they can start during Phase 3 | M |
| **5. Event effects** | Planned | Play/flip, kill, discard, recall, create, summon, swap, lane reveal, Sun Disc (§2.3), each as a handler for one event type | One presenter handler per event (Phase 3) | M |
| **6. Cinematics** | Planned | Trundle ice pillar, level-up cinematic (§2.4) | Biggest visual effort. Needs Phases 3–5 | L |
| **7. Content** | Planned | The 27 unimplemented cards, the text-only keywords, Quick Attack (§1.3, §1.4). Each is shipped **together with its VFX** | Written directly against the new rules engine. New gameplay needs no new network code | L (ongoing) |

Phase 2 and Phase 4 can overlap with Phase 3. Phase 7 is ongoing: pick one champion line at a time.
**Target multiplayer scope: friends / LAN.** Details in Part 3.

---

## 0. Upgrade to Godot 4.7

**Verdict: low risk for this project.** I checked the project against every item in `upgrading_to_godot_4.7.rst`.

### 0.1 Impact on this project

| 4.7 change | Affects us? | Evidence / action |
|---|---|---|
| RichTextLabel `add_image` / `update_image` param changes, `UPDATE_WIDTH_IN_PERCENT` rename | **No (API)**. **Check visually** | No calls in `Scripts/`. But `CardDatabase.format_card_text` emits `[img=32x32]…[/img]` BBCode for keyword icons, and the image sizing code changed underneath. Confirm the icons still render at 32×32 in skill text |
| `Object.is_class` → StringName | No | Not used |
| Particles `request_particles_process` new optional param | No (for now) | Not used. New VFX will use `GPUParticles2D` normally |
| CanvasItem lines lose the antialias feather | No (for now) | No `Line2D` / `draw_line` today. Keep in mind for the Quick Attack arcs: widen lines slightly |
| `InputEvent.device` IDs for mouse and keyboard changed | No | `InputManager.gd` checks the event **type** (`InputEventMouseButton`, `InputEventKey`), never `.device` |
| GDScript: overrides inherit typed return types | No | All scripts extend built-in classes. Overridden virtuals (`_ready`, `_input`, `_process`) are `void` |
| GDScript: setting a packed-array element no longer calls the property setter | No | No packed arrays with setters in `Scripts/` |
| Font importer `hinting` default 1 → 3 | No for existing fonts | All 15 font `.import` files pin `hinting=1` explicitly. **New** fonts will get 3, so set 1 if you want them to match |
| New-project stretch defaults | No | Only affects new projects. `project.godot` already uses `canvas_items` |
| `LinearToSRGB` visual shader no longer clamps | No | The VisualShader in `Card.tscn` and `card_flash.tres` doesn't use it |
| AudioStreamPlayer `area_mask` default | No | No audio yet. Remember it when adding sound with bus overrides |
| Jolt 3D changes (WorldBoundaryShape3D, SoftBody3D, Area3D) | No | Jolt is selected in `project.godot`, but there are no 3D bodies. The ice pillar and level-up cinematics use no physics |
| Animation `length` → double, BlendSpace `sync_mode` | No | Only `AnimationPlayer` is used, with no AnimationTree or blend spaces |
| Accessibility, ZIPPacker, OptimizedTranslation, Image EXR, `Texture2D.get_format`, PhysicsServer2D one-way, OpenXR, Editor importer / VCS | No | Not used |
| macOS minimum 11 | No | The export target is Windows only |

**Worth re-testing on 4.7:** `Card.gd` has a comment that `CanvasGroup` + a VisualShader has a broken framebuffer pipeline in 4.6, which is why the dissolve shader is applied per sprite. If 4.7 fixes that, a group-level shader could simplify the card effects later. This is optional, not required.

### 0.2 Steps

1. Commit the current work (Stun VFX, docs) and create a branch, e.g. `upgrade/godot-4.7`.
2. Close the editor. Optionally delete `.godot/` so it regenerates cleanly (it's in `.gitignore`).
3. Open the project in Godot 4.7 and let it reimport everything.
4. Confirm the upgrade prompt. `project.godot` `config/features` should become `"4.7"`.
5. Optionally re-save every scene (*Project → Tools → Upgrade Project Files…* if it's offered) so the diffs happen once, not scattered over later work.
6. Install the 4.7 export templates and re-check `export_presets.cfg` (Windows Desktop).
7. Delete the stray `Scenes/Main.tscn4839691535.tmp` while you're at it.

### 0.3 Smoke test (before merging)

- [ ] Home → Card Catalog (filters, right-click preview with ◀ ▶) → Deck Builder (add/remove, save, load).
- [ ] Offline match against the bot for all 6 turns. The VICTORY/DEFEAT/TIE text appears.
- [ ] Keyword icons render inside skill text (the `[img=32x32]` check).
- [ ] Hand grey-out for unaffordable cards, discard dissolve (Rumble, Spinning Axe), card flip on draw and resolve.
- [ ] Level-up animation (spin + light sweep), e.g. Renekton or Nasus.
- [ ] Stun: F9 debug toggle, plus a real Kennen stun from the bot. Check the tint, swirl and fade-out.
- [ ] Lane reveal on turns 2 and 3, lane right-click preview.
- [ ] Host/join on LAN (two instances): play a card, resolve, end the match.
- [ ] Windows export runs.

**Rollback:** switch back to `main`. Nothing on `main` is touched until the branch is merged.

---

## Part 1: Problems in the current game

### 1.1 Online desyncs (Phase 1: a and d only; b, c and e are solved by Phase 3)

> In Phase 1, only fix **a** (seed) and **d** (RNG split): they're a few lines each and keep LAN games playable until the rework lands.
> **b**, **c** and **e** exist because both clients simulate the match. The Phase 3 host-authoritative rework (Part 3) removes that, so don't spend time on new mirror RPCs.

Both clients simulate resolve locally. Every random pick must use the **same seed**, and every effect run only by the owner must be **mirrored by an RPC**. Five places break this:

| # | Problem | Where | Fix |
|---|---|---|---|
| a | The "shared" seed isn't shared. `seed(turn_number * 7919 + flip_first_player_id * 1337)` uses the **local** flip-first ID, which `_sync_flip_first` flips per perspective (1 on the priority player's machine, 0 on the other). Kennen, Renekton3, Nasus3 and Devourer can then pick different targets on each client | `GameManager._proceed_to_resolve`, `GameManager.end_game` | Store the flip-first **network** ID too (the value received in `_sync_flip_first`) and seed from that. Or have the host broadcast a match seed once and use `hash([match_seed, turn_number])` |
| b | Devourer's kill runs on the owner's client only and has **no mirror RPC**. The opponent never sees the kill | `AbilityResolver._ability_devourer_deep_kill_enemy` | Add `_receive_opponent_kill(zone_col, zone_row, card_id, killer_card_id)` (mirrored row) and run the standard kill flow there. It can be reused for future kill effects |
| c | Sion's Game End summon from hand runs on the owner's client only. The opponent's Sion **never appears** on your board, so the clients can compute **different winners** | `AbilityResolver._ability_game_end_sion_summon`, and the third pass of `CardManager.trigger_game_end_abilities` (iterates only the local hand) | After summoning, send `_receive_opponent_summon(card_id, col, 1-row, owner)`. A generic summon mirror can also replace `_receive_opponent_game_start_summon` and `_receive_opponent_irelia_blade_summon`. Make sure end-game waits for it before scoring |
| d | Cosmetic and owner-only code consumes the global RNG after `seed()`, advancing it on one client only | `Card.play_discard_dissolve` (`randf()`), `LaneManager._activate_sunken_temple` (`randi()`) | Use a separate `RandomNumberGenerator` for cosmetics, and `AbilityResolver._local_rng` (or its own) for Sunken Temple |
| e | Resolve lockstep is keyed by `card_id` only. Two copies of the same card flipping in one resolve can release each other's wait | `CardManager._receive_card_resolve_done`, `_wait_for_opponent_card_resolve` | Key it by `"%d_%s_%d" % [owner, card_id, play_index]`, or by a per-play instance ID sent with `_receive_opponent_card_play` |

### 1.2 Saved decks are never used (Phase 2, easy)

`Deck.gd` `player_deck` is a hardcoded list of 12 cards, and the Deck Builder saves decks that never reach a match.

**Fix:** in `Deck._ready`, build `player_deck` from `DeckManager.get_active_deck()` (`{"id": id, "cost_mod": 0}` per entry). Fall back to the current list if it's empty.
**Status: done (Phase 2).** The active deck name is persisted in `user://active_deck.json` (kept out of `decks.json` so every key there stays a deck), and loading a deck in the Deck Builder sets it active. A match only uses the active deck when it holds exactly `DeckManager.MAX_DECK_SIZE` (12) valid cards — a partial deck would start the match short and immediately Deep, so it falls back to the old hardcoded list with a warning naming the deck and its valid count. Unknown card ids are skipped with a warning. Saving partial decks in the Deck Builder is still allowed.
**Optional, not done:** a deck picker in the Lobby, and letting the bot use a saved deck.

### 1.3 Cards with no implemented ability (Phase 7)

**27 cards have `AbilityType ""`.** Two more have types with no handler.

| Line | Cards (✦ = collectible, shown in the Deck Builder) | Notes |
|---|---|---|
| Viktor | Viktor1 ✦, Viktor2, HexCoreUpgrade | Needs Augment + "created card" tracking (`created_cards` already exists) |
| Lucian | Lucian1 ✦, Lucian2 | Needs "ally died" events + Rally |
| Garen | Garen1 ✦, Garen2 | Needs a counter for Play activations + Rally |
| Quinn | Quinn1 ✦, Quinn2, Valor | Needs Spawn + Scout |
| Hecarim | Hecarim1 ✦, Hecarim2, SpectralRider | Needs Ephemeral + summon to other lanes |
| Zed | Zed1 ✦, Zed2, LivingShadow | Swap-arrive (like Irelia) + Strike |
| Ryze | Ryze1 ✦, Ryze2, the five World Rune shards (Violence, Betrayal, Reverence, Hope, Madness) | `{Game Start}` shuffles the runes into the deck (today it only logs "unknown Game Start ability type"). Alternate win condition |
| Galio | Galio1 ✦, Galio2 | Needs mana-spent tracking and "summon from hand at Round End" |
| Nautilus | Nautilus1 ✦ | No Play ability by design. Its level-up works (`LevelUpManager._check_nautilus_levelup`) |
| Sea Monsters | TheBeastBelow ✦ | Vanilla by design (Deep keyword only) |
| Mordekaiser | Mordekaiser1 ✦, Mordekaiser2 | `mordekaiser_play_kill` / `mordekaiser_round_end_purge` have **no handler** (the logic was removed in the last commit). Either restore it or make the cards non-collectible |

Also, `buff_allies` and `damage_enemies` in `AbilityResolver` only print a message, and `summon_copy` is used by no card.

### 1.4 Keywords that are text only (Phase 7)

Only **Elusive** (swap), **Stun** and **Deep** have gameplay effects.

- **Icon only**, defined in `KeywordDatabase.gd`: Fearsome, Barrier, Regeneration, Tough, Challenger, Lifesteal, Augment, Evolve, Spirit, Impact, Scout, Ephemeral.
- **Icon only, with a sprite but no database entry:** Fast, Slow, Overwhelm, Landmark, Burst.
- **Quick Attack** doesn't exist yet. Add it to `KeywordDatabase.gd` and add `Assets/KeywordSprites/QuickAttack.webp` before anything else.
- Small data fix: `KeywordDatabase` points Augment to `Augmented.webp`, but the file is `Augment.webp`.

### 1.5 Card text vs code mismatches (Phase 2)

Decide which one is right, then fix the other:

| Card | Text says | Code does | Where |
|---|---|---|---|
| Xerath2 | Back-row enemies here get −1 | ✅ **back-row only** — code now matches text | `AuraSystem._apply_aura_xerath_lv2` |
| Ice Pillar | +`{mana_bonus}` mana (5) | ✅ reads `BalanceValues` — code now matches text | `AbilityResolver._ability_mana_ramp` |
| Rumble2 | Created cards get Augment | ✅ grants the Augment badge — code now matches text | `_ability_level_up_create_from_discards` |
| Janna2 | "When you draw a card, reduce its cost" | ✅ every card its owner draws, bot draws included — code now matches text | `_ability_janna_draw_cost_reduce` |
| Azir3, Xerath3 | Barrier | Keyword not implemented — **still Phase 7** | §1.4 |

### 1.6 Bugs and quirks

| Problem | Where | Fix | Phase |
|---|---|---|---|
| Adding a runtime keyword (e.g. Stun) to a **spell or landmark** errors: the badge sprite is looked up at the root, but it lives at `HBoxContainer/SpriteMargin/KeywordSprite` | `CardSpell._refresh_keyword_display`, `CardLandmark._refresh_keyword_display` | Copy the `Card.gd` version, or move one shared badge builder into `CardDatabase` | 1 ✅ (shared `CardDatabase.fill_keyword_container`) |
| Spell cards were instantiated **without their script**: in `CardSpell.tscn`, `script = ExtResource(...)` had been merged into the node header, where Godot ignores it. It only worked because `Deck.draw_card` / `CardManager` re-attach it with `set_script()` | `Scenes/CardSpell.tscn` root node | Move `script = …` to its own property line (the `set_script()` fallbacks stay as harmless safety nets) | 1 ✅ |
| Autoload singletons are never reset. A second match in one session keeps old stuns, swap history, lane state and bot hand | `StunManager` (has `reset()`, never called), `SwapLaneManager`, `LaneManager`, `BotManager` | Add `reset()` to each and call them from `GameManager.start_game()` | 1 |
| Undo returns cards but leaves their `summoned_cards` entries, which can count toward Azir, Irelia, Kennen and Sion level-ups | `CardManager._on_undo_button_pressed` | Remove the matching unresolved entries (`was_played_from_hand && !is_resolved`) | 2 ✅ |
| Recalled stunned card stays tinted in hand until the next resolve | `StunManager.on_resolve_start` / `CardManager.recall_card` | Decide the rule. If recall should clear stun, remove the entry in `recall_card` | 2 ✅ |
| Engine warning in Card Catalog and Deck Builder: "Can't change the size of a `SubViewport` with a `SubViewportContainer` parent that has `stretch` enabled" (31× per screen; pre-existing, also on 4.6) | `MiniCard.gd:71` `set_display_size` sets `vp.size` while the container has `stretch = true` | Drop the manual `vp.size` assignment (stretch already sizes it), or set `stretch = false` and keep sizing manually | 2 ✅ |
| Unused code: `NetworkManager.local_zone_to_network` / `network_zone_to_local` / `is_local_action`, `get_beheld_cards_filtered`, `count_beheld_matching`, `card_glow_outline.gdshader`, `card_flash.tres`, `VocabDatabase` | various | Keep what future features need (glow shader → VFX, Vocab → tooltips) and delete the rest | any |

### Found during Phase 2 (follow-ups)

- **The documented headless smoke test never leaves the lobby.** `--headless … res://Scenes/Main.tscn -- --autoendturn --quit-on-end` hung at the lobby, because `GameManager._ready()` did not auto-start and `LobbyUI` only started on Host/Join/Offline. ✅ **(a) Resolved** in M4 by the dev flags `--offline`, `--autoplay`, `--verify-view`, `--seed`, `--fast`, `--engine=old` plus `tools/offline_selftest.sh`, which plays whole headless matches and checks the view.
- **`tools/lan_selftest.sh` needs two workarounds on Windows.** `timeout` resolved to `C:\WINDOWS\system32\timeout.exe` instead of GNU coreutils, and the script had to be launched with `sh` (direct execution fails with `%1 is not a valid Win32 application`, and `bash` silently drops the `G47` environment variable). ✅ **(b) Resolved**: all three scripts now go through `tools/_env.sh`, which loads the gitignored `tools/local.env` (see `tools/local.env.example`) and puts Git's `/usr/bin` first on `PATH`; the scripts' `G47` defaults are unchanged.
- **`lan_selftest.sh` never plays a card.** Both peers auto-end every turn, so lanes stay `[0,0,0]`; the test covers turn/lane/seed sync but not card-play sync. ⏳ **(c) Moved to M5**, where `lan_selftest` gains an auto-play mode with real card plays.
- **`summoned_cards` entries keep the lv1 `card_id` / level-up checks don't filter on `is_resolved`.** ✅ **(d) and (e) Fixed** in the new engine on `upgrade/godot-4.7` (10 new scenario/tracker tests): (d) In the new engine Azir/Irelia only check at level 1, so self-counting after a level-up can't happen; they now exclude only their own instance, so a second copy of the same champion counts as an ally. (e) Azir, Irelia, Kennen and Trundle now count only revealed summons, like Sion, so a level-up happens right after the triggering card flips. New engine only — the old LevelUpManager is deleted in M5.
- **Each LAN peer plays its own locally active deck.** Nothing syncs the deck, so two players with different active decks play different decks. ⏳ **(f) Moved to M5** (deck sync, §3.9).

### 1.7 Suggested fix order

1. §1.1 a (seed) and d (RNG split).
2. §1.6 singleton reset, then the badge path.
3. §1.2 saved decks.
4. §1.5 mismatches, then the §1.6 undo tracker.
5. Part 3 (multiplayer rework) takes care of §1.1 b, c and e.
6. §1.3 / §1.4, card by card, together with their VFX (Part 2), on top of the new rules engine.

---

## Part 2: Animation & VFX plan

### 2.1 Foundation: generalise the Stun pattern (Phase 4)

The shipped Stun effect already sets the pattern:

- **Tint:** a parameter on the shared per-card material. `stun_amount` lives in `card_discard_dissolve.gdshader`, set via `Card._dissolve_mat`.
- **Symbol:** built in code (`Card._build_stun_vfx`), procedural shader `stun_swirl.gdshader`.
- **Hook:** `add_runtime_keyword` / `remove_runtime_keyword` → `_set_stun_visual(on)`, which fades over `STUN_FADE_TIME`.
- **Cleanup:** `_hide_stun_symbol` fades on `card_killed` and `play_discard_dissolve`. The symbol hides during `_perform_level_up`.

Generalise it:

> **After Phase 3** (Part 3), event effects become handlers in the `MatchPresenter`, one per event type: `CardKilled`, `PowerChanged`, `Recalled`… The hooks in §2.3 name today's functions; their logic moves into the rules engine, and the visuals move into these handlers. Status effects stay on the card view and read its `CardState`.

1. **`Card._refresh_status_vfx()`.** Compute `active = static Keyword (CardDatabase) + runtime_keywords`, then diff against the spawned effects. Start or stop each effect with a fade. Call it:
   - wherever `_refresh_keyword_display()` is called now;
   - after `populate_card_visuals` (level-up changes the keywords);
   - on resolve, when `is_resolved` becomes true, so face-down cards show nothing.
2. **One node per status effect**, created on demand under a `StatusVfx` Node2D child of the card. It's a `Node2D` scene with an `enter()` / `exit()` API.
   - `Stun` moves into this system first as a refactor.
   - Keep the tint parameters on the shared card material: add `elusive_amount`, `deep_amount` and so on next to `stun_amount`.
3. **Event effects** are `async` functions or small scenes that `await` their animation, e.g. `await Vfx.play(&"kill", card)`. Put them in a new `Scripts/VfxManager.gd` autoload. Call sites are the existing gameplay functions (§2.3).
4. **Optional:** a `VfxLibrary.tres` resource mapping `keyword → PackedScene` and `"CardId.trigger" → PackedScene`, so new effects are data entries.

**Rules for every effect**

- **Never move the card root.** `Board.reposition_cards_in_zone`, swaps, drag and hand layout all set `position`. Animate `CardFront` or VFX children instead.
- **Keep Cost and Power readable.** Tints go through the sprite material, which excludes the labels. Symbols stay in the art area (see `STUN_VFX_CENTER`).
- **Face-down cards show no status effects.** Hidden cards are hidden.
- **Respect the level-up lock.** Cinematics go inside `_perform_level_up`, so the existing queue keeps them serialized.
- **Effects are local only** and never change game state. Multiplayer sync stays in gameplay code.
- **Timing budget:** each resolved card already costs about 0.7 s (`CARD_PAUSE_TIMER`). Keep event effects ≤ 1.5 s. Add **Reduced effects** and **Skip cinematics** toggles to `SettingsUI`.
- **Performance:** up to 24 board cards plus the hand. Use a few particles per effect, shared materials, and `GPUParticles2D` with `one_shot` for bursts. Pause looping status particles when their card is hidden (`visible = false` during SWAP_LANE).

### 2.2 Status effects (per keyword)

"Gameplay first" means the keyword must be implemented (§1.4) before its effect makes sense.

| Keyword | Look | Godot technique | Hook | Gameplay first? |
|---|---|---|---|---|
| **Stun** | Purple pulsing tint, spinning swirl + orbiting stars | Material param + procedural shader | `add/remove_runtime_keyword` | **Done** ✅ |
| **Elusive** | Card gently floats (bob + tilt) on airflow, soft shadow shrinks as it rises, faint wind streaks underneath | Looping tween on `CardFront` position/rotation, shadow `Sprite2D`, `GPUParticles2D` stretched streaks | static keyword, on board + resolved | No |
| **Deep** | Once the owner is Deep: dark-teal underwater tint with slow caustic light and rising bubbles | Material param (`deep_amount`) with scrolling caustic noise, bubble particles | `CardManager.set_player_deep` / `_receive_opponent_became_deep` → refresh cards with the Deep keyword | No |
| **Quick Attack** | Blue electric sparks crawling around the card edge, with occasional arcs | Edge-mask shader (card alpha) + scrolling noise, `Line2D` jittered arcs (widen them: no antialias feather in 4.7), spark particles | static keyword | **Yes** (new keyword) |
| **Barrier** | Golden hex shield bubble. Shatters when it blocks a kill | Circle + hex-pattern shader, shatter burst | keyword + the kill flow | Yes |
| **Challenger** | Red pulsing rim, crossed-swords flash when it triggers | Rim shader param, one-shot sprite | keyword + trigger | Yes |
| **Fearsome** | Dark smoky aura at the card base | Smoke particles (soft, slow) | keyword | Yes |
| **Tough** | Steel sheen sweep every few seconds | Sheen band in the material | keyword | Yes |
| **Regeneration** | Green leaves or sparkles rising. Burst when a debuff is cleansed | Particles + a burst at Round End | keyword + Round End | Yes |
| **Spirit** (stacks) | Blue wisps orbiting, one per stack | Particles with `amount` = stacks | keyword count | Yes |
| **Impact** (lane) | Ground-crack glow in the lane under the card | Lane-level sprite on `Board` | lane power | Yes |
| **Scout** | Ghost after-image offset behind the card | Duplicated `CardFront` at low alpha (or a trail shader) | keyword | Yes |
| **Ephemeral** | Translucent ghostly flicker, then fade on death | Material alpha flicker | keyword + death | Yes |
| **Augment / Lifesteal / Evolve** | Brief "power up" flash: gold / red / prismatic | One-shot bursts at trigger time | trigger | Yes |

### 2.3 Event effects (Phase 5)

These hook into existing functions. Most calls go in *before* or *around* the current animation.

| Event | Look | Technique | Hook (`file:function`) |
|---|---|---|---|
| **Card reveal (resolve flip)** | Impact ring + dust puff when the card lands face-up. Region-coloured flash | One-shot particles + ring shader at the card's position | `CardManager.resolve_played_cards`, after `card_flip_play` |
| **Play from hand (drop)** | Short slam: squash on `CardFront`, small dust | Tween on `CardFront.scale` | `CardManager.finish_drag` (success path) |
| **Kill** | Crack lines, then shards/ash burst, replacing the plain fade | Crack overlay shader param, then shard particles, then the existing dissolve | standard kill flow: `AbilityResolver._ability_kill_ally_buff`, `_ability_nasus_game_end_kill`, `_ability_devourer_deep_kill_enemy` (animation `card_killed`) |
| **Death prevented** (Tryndamere) | Red rage flare + "survive" shockwave | Burst + screen shake (small) | `Card.on_death_prevented` |
| **Discard** | Existing orange dissolve + rising embers | Add ember particles | `Card.play_discard_dissolve` |
| **Recall** | Blue rewind swirl at the board spot, trail following the card to the hand | Swirl sprite + trail (`Line2D` following the tween) | `CardManager.recall_card` |
| **Create in hand** | Card materialises from light at centre before flying to the hand | Glow burst + scale pop | `CardManager.create_card_in_hand` |
| **Summon to board** (Sun Disc, Blade, Chip, Sion) | Rune circle appears in the slot, card rises from it | Rune ring shader + particles at the slot | the summon recipe in `AbilityResolver._game_start_summon_sun_disc`, `_ability_swap_arrive_summon_blade`, `_ability_game_end_sion_summon`, `LaneManager._summon_card_in_lane` |
| **Power buff / debuff** | Green up-arrows / red down-arrows + the number pops | Floating label + particles | wherever `power_modifier` changes. Centralise in a `Card.change_power(delta)` helper |
| **Swap lane** (Elusive) | Wind streak trail during the 1 s move | Trail + streak particles | `SwapLaneManager.execute_swaps` (the tween step) |
| **Stun applied** | Lightning flash on apply (Kennen) | Burst before `_set_stun_visual(true)` | `AbilityResolver._ability_stun_enemy` |
| **Lane reveal** | Fog clears to reveal the lane art | Dissolve shader on a fog sprite over the lane | `Board.reveal_lane_visuals` (called by `LaneManager._reveal_lane`) |
| **Lane effects** | Hexcore: hextech pulse. Ornn: forge sparks on the units. Sunken Temple: water swirl. Noxkraya: red arena glow on turn 5. Rockfall: falling rocks + dust | Lane-level particles | `LaneManager._activate_*`, `on_round_start` (Noxkraya) |
| **Sun Disc restored** | Golden sunburst from the landmark across the board | Big radial burst + light sweep | `LevelUpManager._on_sun_disc_restored` |
| **Win / lose** | Confetti or gold rays for VICTORY. Dim + ash for DEFEAT | Particles behind `VictoryText` | `GameManager._show_match_result_text` |

### 2.4 Cinematics (Phase 6)

**Trundle1 Play: Ice Pillar rises, card emerges**

1. **Hook:** `AbilityResolver._ability_create_card` (Trundle1). Before `create_card_in_hand`, `await Vfx.play_cinematic(&"trundle_ice_pillar")`.
2. **Scene:** `Scenes/Vfx/TrundleIcePillar.tscn`:
   - a `SubViewportContainer` over the board, holding a `SubViewport` with its own `Camera3D`, a light and the low-poly **ice pillar model** (made in Blender, exported as `.glb`);
   - the SubViewport uses a transparent background;
   - an `AnimationPlayer` drives the cinematic.
3. **Timeline (≈1.8 s):**
   1. Frost cracks spread from the centre (2D shader) and the screen shakes lightly.
   2. The pillar rises with ice shards (`GPUParticles3D` in the viewport).
   3. A **Call Method track** emits `release_card` at the moment the card should appear.
   4. The pillar shatters, and the scene frees itself.
4. **Card:** on `release_card`, the Ice Pillar card is created. `create_card_in_hand` already spawns at the screen centre and tweens to the hand, so it appears to come out of the pillar.
5. **Look:** an ice shader on the pillar (fresnel rim, fake refraction, emissive cracks). No physics is needed, so the Jolt changes in 4.7 don't matter.

**Level-up cinematic (the champion doing something with a background)**

- **Hook:** `Card._perform_level_up`. Keep steps 0 and 6–9 (ID update, lock, upgrade copies, level-up ability). Replace steps 1–5 (fly-to-centre / spin / fly back) with `await Vfx.play_level_up(champ_name, self)` when a cinematic exists for that champion. Otherwise fall back to the current spin.
- **Scene per champion:** `Scenes/Vfx/LevelUp_<Champion>.tscn`:
  - **2.5D option** (matches the card art): layered cut-out art (background, character, effects planes) with parallax, `Skeleton2D` / bones or Spine, particles and light sweeps.
  - **3D option:** a rigged model in a SubViewport stage.
- **AnimationPlayer** with a **Call Method track** at the reveal beat that calls `CardDatabase.populate_card_visuals(self, new_data, self)`. That replaces today's fixed 1.5 s mid-spin swap.
- The global level-up lock (`CardManager._level_up_in_progress` / `_level_up_pending`) already queues simultaneous level-ups and makes resolve wait. Cinematics inherit that for free.
- Respect **Skip cinematics**: when it's on, use the current spin.
- Build one champion end to end first (Renekton or Nasus levels up often in bot games), then reuse the scene structure.

### 2.5 Suggested VFX order

1. Refactor Stun into `_refresh_status_vfx` (no visual change), then **Elusive float**, then **Deep**.
2. **Kill**, **card reveal** and **power buff/debuff** popups. These are seen every match.
3. **Recall**, **summon**, **create in hand**, **swap trail**, **discard embers**.
4. **Lane reveal** + lane effects, **Sun Disc**, **win/lose**.
5. **Trundle ice pillar**, the first cinematic, which establishes the SubViewport pattern.
6. **Level-up cinematic** for one champion, then the others.
7. Per-keyword effects alongside their gameplay in Phase 7 (Quick Attack, Barrier, Challenger…).

---

## Part 3: Multiplayer rework: the host runs the rules (Phase 3)

### 3.1 Goal and scope

**Target: friends / LAN.** One player hosts; the host's machine runs the only copy of the rules (a *listen server*); the other player's client only sends what it wants to do and animates what it's told.

| In scope | Out of scope (not needed for friends/LAN) |
|---|---|
| Host-authoritative rules, intents in, events out | Dedicated or cloud servers |
| No desyncs by design, hidden hands really hidden | Accounts, matchmaking, ranking |
| Validation of every client action | Protection against a cheating *host* |
| LAN host discovery (no typing IPs) | NAT traversal / relay servers |
| Offline vs bot on the same code path | |
| Optional: reconnect after a dropped connection | |

**Playing with friends over the internet:** use a virtual LAN such as Tailscale, ZeroTier or Radmin VPN, and join by the friend's virtual IP. The game needs no changes. LAN broadcast discovery may not work across these, so keep the manual IP field.

### 3.2 Why change (today's problems)

Today both clients simulate the whole match, kept in step by a shared seed, about 20 hand-written mirror RPCs, and "resolve done" lockstep messages. That causes:

- desyncs (§1.1: the seed bug, Devourer, Sion, RNG misuse, lockstep key collisions);
- hidden-information leaks: card IDs are sent on drop, and the whole hand is sent for behold (`sync_hand_data`);
- zero validation: a client can send any card or ignore mana;
- rules tangled with animation (`await` on tweens inside ability code).

### 3.3 Target architecture

```
 Client (guest)                        Host (player + authority)
 ─────────────                         ─────────────────────────
 Input / drag ──► Intent ─────RPC────► MatchRules.submit(player, intent)
                                          │ validate (phase, mana, card in hand, legal zone)
                                          │ mutate MatchState (pure data, no nodes)
                                          ▼
                                        events[]  ──► filter per recipient
 MatchPresenter ◄────────RPC──────────  (guest's view)      (host's view) ──► host's MatchPresenter
   plays events one by one as animations/VFX, then acks "presentation done"
```

- **Offline vs bot** runs the same `MatchRules` locally. The bot submits intents as player 0, and there's no network at all.
- **Player IDs become absolute:** `0` = host, `1` = guest. Perspective exists **only in the view**: `row = 1 if owner == local_player else 0`. All row mirroring (`1 - row`) disappears from the game logic.

### 3.4 Game state (pure data)

New `RefCounted` classes, with no scene nodes:

| Class | Holds (today's source) |
|---|---|
| `CardState` | `instance_id` (unique per match), `card_id`, `owner`, `location` (DECK / HAND / BOARD / SPELL_ZONE / GONE), `zone` + `slot_index`, `power_modifier`, `aura_power_modifier`, `cost_modifier`, `aura_cost_modifier`, `runtime_keywords`, `is_resolved`, `axe_play_count`. Taken from `Card.gd`, with `get_current_power` / `get_current_cost` moved here |
| `PlayerState` | deck (ordered `CardState`s with `cost_mod`), hand (index 0 = newest), mana state (from `GameManager.PlayerManaState` + pending/active temporary bonus), `is_deep`, `permanently_leveled_up` |
| `MatchState` | turn, game/round phase, flip-first player, lanes (IDs, revealed, Noxkraya), board zones (`slots_by_zone` / `cards_by_zone` logic from `BoardGeneration.gd`, but as indices), `all_cards_in_play_order`, `played_cards_order`, trackers (killed / summoned / created / recalled / discarded / drawn from `CardManager.gd`), stun entries (`StunManager`), pending swaps + history (`SwapLaneManager`), one `RandomNumberGenerator` |

Board **geometry** (pixel positions) stays in `Board`, which is a view. The state only knows `(col, row_of_owner, slot_index)`.

### 3.5 Rules engine

`MatchRules` owns a `MatchState` and exposes:

- `submit(player, intent) -> Array[Event]`: validate the intent, apply it, return the events (or `IntentRejected`).
- `advance() -> Array[Event]`: run the automatic phases (ROUND_START, SWAP_LANE, RESOLVE, ROUND_END, GAME_END) once both players have ended their turn.

It's **synchronous**: no `await`, no timers, no tweens. Timing belongs to the presenter. Port the logic system by system from `AbilityResolver`, `LevelUpManager`, `AuraSystem`, `LaneManager`, `StunManager`, `SwapLaneManager` and `GameManager`:

- Level-up becomes an instant state change plus a `CardLeveledUp` event. The global animation lock moves to the presenter.
- All owner-gating (`owner_player_id != current_player_id`, `!= 1`) is deleted, because the host runs every effect for both players.
- One RNG, owned by the host. It no longer needs to match across machines.
- Behold (Trundle2) reads both hands directly. `BeheldCardProxy` and `_receive_opponent_hand_ids` go away.
- Keep the resolve order rules (flip-first sorting, three Game End passes, the Skill-text trigger gates) exactly as they are today.

**Intents** (client → host):

| Intent | Fields | Validation |
|---|---|---|
| `PlayCard` | `instance_id`, `col`, `slot` (or spell zone) | PLAY phase, card in the sender's hand, affordable, own zone with a free slot, spell ↔ spell-zone rule, Noxkraya restriction |
| `SwapCard` | `instance_id`, `to_col` | PLAY phase, own resolved Elusive card on the board, not stunned, no pending swap, different column with a free slot |
| `Undo` | – | PLAY phase, the sender has plays this turn |
| `EndTurn` | – | PLAY phase, not already ended |

**Events** (host → clients). The first set is a starting point; add more when a new card needs one.

`MatchStarted`, `TurnStarted`, `PhaseChanged`, `ManaChanged`, `PriorityChanged`, `LaneAssigned`, `LaneRevealed`, `LaneEffect`, `CardDrawn`, `CardCreatedInHand`, `CardPlayed` (face-down), `PlayUndone`, `IntentRejected`, `SwapStarted`, `CardSwapped`, `CardRevealed`, `PowerChanged` (instance, delta, new total), `CostChanged`, `KeywordAdded` / `KeywordRemoved` (Stun…), `CardKilled`, `DeathPrevented`, `CardDiscarded`, `CardRecalled`, `CardSummoned`, `CardLeveledUp` (old/new ID), `DeepChanged`, `SunDiscRestored`, `GameEnded` (winner, lane powers).

### 3.6 Hidden information

The host filters every event per recipient before sending:

| Information | The owner sees | The opponent sees |
|---|---|---|
| Deck order | nothing | nothing |
| Card drawn / created in hand | `card_id` | only `instance_id` (a card back in the opponent's hand count) |
| Card played during PLAY | `card_id` + zone | **only the zone** (face-down) until `CardRevealed` |
| Hand contents | everything | only the count |
| Behold, discard picks, random targets | the result | the result |

**Opponent plays:** today the opponent's plays appear only at resolve (`_pending_opponent_cards`). Decide whether to keep that, or show face-down cards live during PLAY. The events support both.

### 3.7 Presenter (the view)

`MatchPresenter` receives event batches and plays them **one at a time**, awaiting each animation:

- Maps `instance_id → Card` view node. `Card.gd` becomes a view: it displays a `CardState` snapshot, and all logic is removed from it.
- The current animations move here: the flip, dissolve, recall flight, level-up spin, and swap tween.
- Part 2's event VFX (§2.3) become one handler per event type.
- The level-up lock (`_level_up_in_progress` / `_level_up_pending`) is replaced by the sequential event queue.
- Pacing (`CARD_PAUSE_TIMER`, the 0.5 s face-down pause) moves here, with a "reduced effects / skip" setting.
- When a batch finishes, the client sends `PresentationDone(turn)`. The host starts the next PLAY phase only after both clients ack, with a timeout of about 10 s so a stuck client can't freeze the game. This replaces today's per-card lockstep.

**Playing a card:** drag and drop still places the card instantly (optimistic, like now) and sends `PlayCard`. On `IntentRejected`, the card animates back to the hand. On LAN the round trip is milliseconds.

### 3.8 Network layer (ENet stays)

Keep `NetworkManager` (ENet, port 9999, 2 players) and replace the ~20 RPCs with **four**, in a new `MatchNet` node:

| RPC | Direction | Payload |
|---|---|---|
| `submit_intent(intent: Dictionary)` | guest → host | `{type, …fields}` |
| `receive_events(events: Array)` | host → guest | array of `{type, …fields}` Dictionaries (plain data only, no Objects) |
| `receive_snapshot(snapshot: Dictionary)` | host → guest | filtered full state (join / reconnect) |
| `presentation_done(turn: int)` | guest → host | – |

The host calls its own `MatchRules` and presenter directly; there's no loopback RPC.

**LAN discovery** (`LanDiscovery.gd`):
- While hosting, broadcast a small UDP beacon every second with `PacketPeerUDP` and `set_broadcast_enabled(true)`, for example on port 9998: `{"game": "RuneterraForge", "name": host_name, "port": 9999, "version": …}`.
- The lobby listens and shows the hosts it finds as a clickable list.
- Keep the manual IP field for VPN or cross-subnet play.
- Put a protocol version in the beacon and the join handshake, and refuse mismatched builds.

**Reconnect (optional):** the host keeps the `MatchState` for about 60 s after a disconnect. On rejoin it sends a filtered snapshot, and the presenter rebuilds the board without animations.

**Debugging:**
- Log every event batch to `user://logs/match_<time>.jsonl`.
- A debug replay mode feeds a log to the presenter.

### 3.9 Migration steps (revised for Phase 3 kickoff)

**Decisions (Phase 3 kickoff):**
- **Parallel engine + switch.** The new engine is built in `Scripts/Match/` *next to* the old code, which keeps working until the switch. Offline moves first (M4), then online (M5); the old engine and its RPCs are deleted in M5.
- **Opponent plays stay hidden until RESOLVE** (current behaviour): the host sends nothing about them before then.
- **Process:** one worktree + branch per milestone (`phase3/mN-…`), started from `upgrade/godot-4.7`. Claude commits after review; the user checks and pushes, then the branch is fast-forwarded into `upgrade/godot-4.7`.
- **Tests:** a small built-in headless runner (`tools/run_tests.sh` → `Tests/run_all.gd`), no addon. Scenario tests drive `MatchRules` directly. **On Windows**, copy `tools/local.env.example` to `tools/local.env` (it holds the Godot path) and run the scripts from Git Bash with `sh`, e.g. `sh tools/run_tests.sh` — direct execution and WSL's `bash` both misbehave; `tools/_env.sh` handles the rest.

**Engine rules** (all milestones, checked in review): files in `Scripts/Match/` extend `RefCounted` only; no `Node`, `get_node`, `await`, autoload identifiers or scene-tree access; no global `randi()`/`randf()` (all randomness via `MatchState.rng`); **player IDs are absolute** (0 = host, 1 = guest), perspective exists only in the view; card data comes from `CardDatabase.CARDS` / `LaneDatabase.LANES`.

| M | Name | Content | Game behaviour changes? | User check |
|---|---|---|---|---|
| **M1** | Foundation | State classes (`CardState`, `PlayerState`, `MatchState`), events/intents protocol, `MatchRules` skeleton, `MatchSetup`, headless test runner | No (new code only) | Test output |
| **M2** | Rules core (no card abilities) | Setup + shuffle, Game Start hook, turn/mana loop (incl. temporary bonus), draw/Deep, play/undo/swap intents with every `finish_drag` rule, resolve order (flip-first), reveal, round end, priority, lane assignment/reveal + the 5 lane effects, game end winner; bot decision → intents | No | Test output |
| **M3** | Abilities | Port all `AbilityResolver` handlers, kill/summon flows, death prevention, Last Breath, behold, trackers, `LevelUpManager` (incl. global upgrade + Sun Disc), `AuraSystem`, Stun, swap-arrive. Scenario tests per ability | No | Test output |
| **M4** | Presenter + offline switch | `MatchPresenter` plays events through the existing card views and animations; input → intents; the bot runs on the engine; offline uses the new engine (`--engine=new`, then by default) | **Yes (offline)** | GUI play vs bot |
| **M5** | Online | `MatchNet` (4 RPCs), per-recipient filtering, start snapshot, `presentation_done` gating; `lan_selftest` gains auto-play with real plays; **delete the old engine + old RPCs** (§3.10) | **Yes (online)** | LAN match |
| **M6** | LAN polish | UDP host discovery + version handshake; optional reconnect + event logs | Yes (lobby) | Lobby check |

**M5 detail:**
- `lan_selftest` gains an auto-play mode with real card plays on both peers. Each peer runs `--verify-view`, and the host's and guest's event logs (per-viewer redaction applied) must match the engine. This replaces the current "auto-end only" check.
- **Deck sync:** the guest sends its deck card ids in the join handshake; the host validates it with the same rule as offline (`MatchController.human_deck_ids`: exactly 12 known card ids, else the default deck) and passes both decks to `MatchSetup.new_match`. The guest never sees the host's list.

Useful first scenario tests (M3): Rumble's discard brackets; Nasus vs Tryndamere death prevention; the Azir aura pushing Renekton to his level-up; the three Game End passes; Sion's lane choice from hand.

### 3.10 Deleted in M5

- `seed(...)` calls in `GameManager`, and the `_local_rng` vs global split in `AbilityResolver`.
- Resolve lockstep: `_receive_card_resolve_done`, `_wait_for_opponent_card_resolve`, `_card_resolve_done_signals`.
- Swap sync: `_rpc_notify_swap_step_done`, `SwapLaneManager._swap_step_done` / `_swap_steps_received`.
- Every `_receive_opponent_*` mirror in `CardManager` and `AbilityResolver`, and `_receive_undo_all_plays`.
- `sync_hand_data`, `_receive_opponent_hand_ids`, `BeheldCardProxy`, `opponent_hand_card_ids`.
- `_pending_opponent_cards`, `_pending_opponent_swaps` and `apply_pending_opponent_swaps` (replaced by events).
- Owner-gating checks throughout `AbilityResolver` and `LevelUpManager`.
- `GameManager._sync_flip_first` perspective mapping, `_local_to_network_player`, and the unused `NetworkManager` zone converters.

This also resolves §1.1 b, c and e without writing any mirror RPCs.

---

## Appendix: files you'll touch most

| Area | Files |
|---|---|
| Engine upgrade | `project.godot`, `export_presets.cfg`, all `.tscn` (resave) |
| Desync fixes | `GameManager.gd`, `AbilityResolver.gd`, `CardManager.gd`, `Card.gd`, `LaneManager.gd` |
| Singletons / quirks | `StunManager.gd`, `SwapLaneManager.gd`, `LaneManager.gd`, `BotManager.gd`, `CardSpell.gd`, `CardLandmark.gd` |
| Decks | `Deck.gd`, `DeckManager.gd`, `LobbyUI.gd` (optional picker) |
| Multiplayer rework | new `Scripts/Match/` (`CardState.gd`, `PlayerState.gd`, `MatchState.gd`, `MatchRules.gd` + ability modules, `MatchEvents.gd`, `MatchPresenter.gd`, `MatchNet.gd`, `LanDiscovery.gd`); refactor `Card.gd`, `CardManager.gd`, `GameManager.gd`, `AbilityResolver.gd`, `LevelUpManager.gd`, `AuraSystem.gd`, `LaneManager.gd`, `SwapLaneManager.gd`, `StunManager.gd`, `BotManager.gd`, `NetworkManager.gd`, `LobbyUI.gd` |
| VFX | `Card.gd`, `Materials/card_discard_dissolve.gdshader`, new `Scripts/VfxManager.gd`, new `Scenes/Vfx/*`, new `Materials/*.gdshader`, `SettingsManager.gd` (effects toggles) |

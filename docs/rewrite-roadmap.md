# Removing the original game-code dependency

The owner chose to publish reviewed GPL components while replacing the remaining runtime with
original code. The existing local build stays playable during that work.

## Measured starting point

The local source lists in `build/daikatana_sources.zig` compile these Gold files:

| Subsystem | Translation units | Source lines before headers |
|---|---:|---:|
| Common utilities | 10 | 4,076 |
| Client entity library | 21 | 2,548 |
| Physics | 20 | 17,488 |
| World, AI, sidekicks, entities | 135 | 183,159 |
| Weapons | 29 | 24,179 |
| Cinematic editor/runtime support | 23 | 11,033 |
| Total | 238 | 242,483 |

These are source-list counts, not a claim that every line must be recreated. Unneeded legacy
behavior can be removed once its absence is demonstrated. Headers and code excerpts in patches
also need replacement; dropping the reference directory alone is insufficient.

## Ordered work

- [ ] Define original runtime types and narrow engine interfaces, without Gold headers.
  Gate: a standalone module compiles with the reference tree absent.
- [ ] Replace common utilities and data-table adapters using original implementations.
  Gate: synthetic format cases and required runtime callers work without Gold libraries.
- [ ] Replace entity storage, spawning, movement, collision, triggers, doors, and level transitions.
  Gate: walk a real level, operate a door, cross its exit, and retain player state.
- [ ] Replace weapons, inventory, health, damage, and progression.
  Gate: fire, hit, take damage, pick up equipment, and change weapons in the running game.
- [ ] Replace navigation, monster behavior, bosses, and sidekicks.
  Gate: encounter scenarios cover pursuit, attacks, death, scripted arrivals, and companion behavior.
- [ ] Replace scripting, cinematics, saves, and remaining client/UI dependencies.
  Gate: script-driven encounters, save/load, menus, and transitions work; original art and text
  are read only from locally supplied assets.
- [ ] Admit each finished component to the GPL repository after provenance review.
  Gate: no copied unlicensed implementation, embedded proprietary content, or hidden local input.
- [ ] Publish the playable build instructions when the complete game is independent of Gold.
  Gate: clean checkout plus documented open-source dependencies and user-owned assets builds
  the game; episode acceptance, save/load, and viewed gameplay evidence pass.

Use small replacements with explicit behavior evidence. A mechanical translation of the Gold
source is not an independent implementation. Keep unresolved components outside the public tree.

## Preserving the working game

The public subset has its own build root. Exporting it does not change the local game's launch
command or save path. The local bridge encounter fix is installed and verified: crossing the
e1m1b bridge starts the ten-mosquito swarm and an attacking thunderskeet.

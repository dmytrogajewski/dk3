# Development screenshots

Captured on 2026-09-25 from the independent native dk3 runtime at source commit
`8faf591`, using the locally installed 1.3 asset profile and HD texture overlay.
These are unretouched 1280 × 720 engine JPEG captures, rendered with OpenGL1 in
software through `dkguard --headless`.

| Image | Scene |
| --- | --- |
| [Shotcycler](shotcycler-ready.jpg) | Weapon at rest on e1dm1 with granted weapons/ammo; refreshed in sequence 202. |
| [Marsh](marsh.jpg) | Rain and waterfalls on e1m1a, using a positioned noclip camera. |
| [Menu](menu.jpg) | Native UI showing difficulty selection with supplied menu artwork. |

These frames illustrate the current development build. They do not establish
campaign completion or full visual parity; see [completion status](../status.md).
The game data is supplied locally and is not bundled with this repository.
Depicted artwork remains the property of its respective owners and is not
relicensed by the project's GPL grant; see [copyright](../../COPYRIGHT.md).

Local reproduction evidence: `zig-out/reports/readme-gallery-201/` for the marsh
and menu; `zig-out/reports/readme-gallery-202/` for the refreshed Shotcycler frame
(`capture-arena.py`, `harness.py`, `arena-settled.log`, and `arena-settled-inputs.txt`).
Installed runtime generation:
`6a4d5a4263029b67c6f5618cd107e7cfef5923d89d35daf21ab845a6e3cb36b4`.

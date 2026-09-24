# Native Zig weapons

The owner's explicit weapons rewrite overrides the general C game/client guidance
for this subsystem. Both native modules link Zig 0.16 weapon implementations.
The engine's existing C ABI provides collision, entities, snapshots, renderer,
audio, filesystem, generic model animation and damage services.

Every selectable weapon is a concrete type under `src/weapons/types`. Its methods
own prediction, firing, projectile contact and lifecycle, presentation, inventory
exceptions and restoration. `registry.zig` resolves IDs and checks the interface at
compile time. Shared Zig components implement mechanisms; they do not choose an
attack from a weapon ID. There is no C combat implementation or C behavior-plan
interpreter in the build.

Prediction and server movement use the same Zig controller and concrete updates.
Server entity callbacks re-enter Zig directly. Client view animation players are
instantiated per concrete type. Weapon-owned actions override their transitions.
Per-weapon effects and bounded transient pools are reset on client initialization
and time reversal. Fire presentation uses the engine’s event-sequence replay suppression, preserving
distinct shots delivered in the same render frame.

Existing numeric IDs and engine snapshot/save fields remain the compatibility
boundary. Do not serialize Zig pointers or native struct memory. Persistent entity
references use stable IDs. The Metamaser decodes its existing save fields into a
named Cube/Lock representation; restoring an entity rebinds its owning type's
callbacks. Retaining the wire layout does not require retaining C execution.

The connected implementation pass is complete. Integrated native builds, the shared
prediction/inventory contracts, all 28 authoritative firing paths, representative
restoration and liquid-contact scenarios, and the broad suite have been exercised.
[Sequence 199](../specs/runs/RUN-dk3-independent-port.md#weapons-zig--sequence-199)
records inputs, repaired failures and precise remaining acceptance limits.

In Zig, each source file is a concrete struct namespace type. `registry` registers
those types, and `inline for`/`@hasDecl` check and instantiate their methods. There is
no behavior opcode to interpret and no inheritance hierarchy. Shared mechanisms
accept a compile-time weapon type and call its methods; they do not switch on named
weapons. Stateful view players use `View(Weapon)` instances. Weapon owners alone
interpret their persistent controller fields; the unchanged save/snapshot schema is
an adapter to the engine, not a second implementation.

# Implementation and gameplay verification

Development uses two passes. First implement the authorized scope across related
systems. Then build the integrated game and test real scenarios, fixing failures
and rerunning affected cases until the required behavior works.

## Write the implementation

Use the accepted plan and relevant source/docs. Reuse existing code and runners.
Change size follows the feature and its dependencies; there is no micro-TDD line
limit, test-first requirement, or full-suite preflight. Tests can accompany the code
or be added during verification. An optional targeted build/probe should answer a
concrete uncertainty that would otherwise obstruct implementation.

Mark written work as **implemented; unverified**. This permits dependent implementation
to continue without claiming the game already works. Record missing design decisions
where useful; avoid a new FRD and checklist for every item.

## Run scenarios and fix failures

Build the integrated result, then exercise the required client/server paths using
existing tooling. Cover gameplay, presentation, authored progression, saves, and
multiplayer as required by the active plan. Inspect rendered results where relevant.
Entity counts and successful map loads are supporting diagnostics, not substitutes
for playing through encounters and transitions.

Keep a compact scenario matrix in the existing run log:

| State | Meaning |
|---|---|
| Unrun | Implementation exists; no acceptance result yet |
| Passed | Required behavior demonstrated with recorded inputs and evidence |
| Failed | An observed defect needs diagnosis, repair, and replay |
| Blocked | A named unavailable input/access prevents this scenario |

For failures, keep the first useful log, trace, or frame. Fix the cause and rerun
the affected scenario. Add focused regression coverage when useful. Preserve passing
results until their relevant inputs change, and broaden testing when shared changes
or measured failures justify it. Repeated failures call for different diagnostics,
not an automatic stop after a retry quota. Continue independent work around blockers.

For reproducible client input, `dk3_look <yaw> <pitch>` sets the next normal user
command's view orientation in an active game. It validates finite numeric angles and
accounts for server view offsets. It changes no position or world state; combine it
with ordinary movement, attack, use and save commands. `viewpos` and rendered captures
show the resulting view. Scenario inputs should record use of this command.
`cl_debugMove 3` logs changes in outgoing movement axes/buttons together with the
last authoritative ground, movement flags and velocity. Use it to distinguish
input-driver mistakes from simulation failures; it does not alter input or physics.

## Finish verification

After required scenarios pass, run applicable broad checks once. In this repository,
`make lint` invokes `zig build test`, and `make test` invokes that same suite. Running
all three adds duplicate work. Repair failures with focused checks, then refresh any
aggregate result invalidated by the repair batch. Do not rerun still-valid checks.

Skill and documentation edits need only content, link, and metadata review and an
available lightweight validator. They do not require game builds or test suites.
Keep failures and unverified requirements visible; these changes alter the execution
order, not the required game functionality or the evidence needed to claim it works.

## Instruction maintenance

AGENTS.md and `.agents/skills/` define this cadence. `.claude/commands/` points to the
canonical skills rather than carrying duplicate workflows. The checkbox gate, gate
tracker, and whole-roadmap stop hook are disabled in `.claude/settings.json`; remaining
hooks retain their existing scope. Acceptance still requires relevant evidence.

These files have local edits relative to `.promptkit.yaml` generation checksums.
Review a future promptkit update before applying it so it does not restore the old
per-item gates. No generator update is needed to use the edited skills.

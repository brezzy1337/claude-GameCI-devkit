# Judging test coverage for gameplay code

A shared rubric for the review lenses (`gameplay-reviewer` primarily; `factual-reviewer` and
`architecture-reviewer` within their lanes). The question is never "what's the coverage percentage?"
but "is the logic that would hurt players if it broke pinned down by a test that would fail?".

## Must be tested (missing test = Warning; Critical when money, saves, or fairness are at stake)

- **Economy and progression** — currency, prices, rewards, XP curves, unlock conditions, loot tables.
  Critical when real-money purchases or entitlements are involved.
- **Damage, health, and combat math** — formulas, modifiers, crits, resistances, death conditions.
- **State machines** — every transition the diff adds or changes, including illegal transitions being
  rejected (player, AI, game-flow, UI flow).
- **Save / load** — round-trip of changed save data; migration of old saves; `[FormerlySerializedAs]`
  renames keep old data (Critical: silent save corruption).
- **Frame-rate-sensitive logic** — movement, jump heights, cooldowns, timers: a parameterized test at
  several `deltaTime` values (e.g. 1/30, 1/60, 1/144) proves frame-rate independence.
- **Netcode validation** — server-side checks on client requests (bounds, ownership, rate limits).
- **Bug fixes** — a regression test that fails without the fix.

## Should be tested (missing test = Note)

- Input mapping to actions (action callbacks → game commands), with simulated input where practical.
- Physics-driven behaviour with clear expectations (a projectile hits within N steps), using scripted
  simulation.
- Scene-level integration of a new system (one small PlayMode test that it boots and runs a frame).
- Editor tooling that writes assets or project files.

## Acceptable without tests

- Pure presentation — VFX, animation timing, audio, UI layout and polish.
- Thin MonoBehaviour adapters whose logic lives in tested plain C# classes.
- Scene/prefab wiring (verified in playtests and by the Editor, not unit tests).
- Prototype code the PR explicitly marks as throwaway (flag if it touches the must-test list anyway).

## Signs a test doesn't count

- `Assert.Pass`, no assertions, or assertions on values the test just set.
- It tests Unity or a library instead of project logic (e.g. that `Vector3.Distance` works).
- Depends on real time (`WaitForSeconds`) or test order, or leaks static state / GameObjects between
  tests — flaky by construction.
- Mocks the thing under test, or asserts only that a mock was called with whatever the code passed.
- A PlayMode test for logic that could be an EditMode test — not wrong, but slow; suggest extracting.

## How to report

Stay in your lens's lane and use the shared shape:

```
Warning — Assets/Scripts/Gameplay/Economy/ShopRules.cs:42 — new discount stacking logic has no test;
  a regression would mis-price every bundle — add EditMode ShopRulesTests.StacksDiscountsMultiplicatively
  with [TestCase] rows for 0/1/2 active discounts
```

Name the test (class, method, EditMode or PlayMode, key cases) — a finding that only says "add tests"
is noise.

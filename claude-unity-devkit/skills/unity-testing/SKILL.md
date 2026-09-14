---
name: unity-testing
description: >-
  Unity Test Framework conventions for a Unity / C# repo — EditMode vs PlayMode tests, [UnityTest]
  coroutine tests, test assembly definitions, mocking with NSubstitute, designing gameplay code so it
  can be tested, running tests in batchmode and in GameCI, and how the review agents judge test
  coverage for gameplay code. Use this skill whenever the user wants to add, structure, run, or review
  Unity tests, set up test asmdefs, choose between EditMode and PlayMode, mock dependencies in Unity,
  get tests running in CI, or asks whether a gameplay change is adequately tested.
---

# Unity testing

## The idea

Unity tests run inside the Editor through the Unity Test Framework (UTF, `com.unity.test-framework`,
NUnit-based). The hard part isn't the syntax — it's that gameplay code is usually welded to
MonoBehaviour lifecycles, frames, and physics, which makes it slow and flaky to test. So this skill
is as much about *shaping code to be testable* as about writing tests, and it gives the review lenses
one shared rubric (`references/coverage-judgement.md`) for "is this change tested enough?".

## What you produce

- **Test assemblies** — `assets/Tests.EditMode.asmdef` and `assets/Tests.PlayMode.asmdef` (replace
  `__NAMESPACE__`), one pair per project or per major runtime assembly.
- **Tests** — EditMode for logic, PlayMode for behaviour that needs the player loop.
  `assets/EditModeSmokeTests.cs` and `assets/PlayModeSmokeTests.cs` are the day-one smoke tests the
  scaffolder installs so CI has something to run.
- **CLAUDE.md test commands** — the local batchmode command (if the team has an Editor path) and
  the GameCI Test workflow as the gate.

## EditMode vs PlayMode

| | EditMode | PlayMode |
| --- | --- | --- |
| Runs | in the Editor, no player loop | in Play Mode (or a player build), frames advance |
| Good for | plain C# logic, ScriptableObject logic, calculations, state machines, serialization, Editor tools | MonoBehaviour lifecycle, physics, coroutines, animation events, scene loading, input simulation |
| Speed | milliseconds | seconds (enters Play Mode, advances frames) |
| Asmdef | `includePlatforms: ["Editor"]` | `includePlatforms: []` |

Default to EditMode. Reach for PlayMode only when the behaviour genuinely needs frames, physics, or
the lifecycle — and then keep the logic under test in plain C# so most assertions stay in EditMode.

## Test assembly definitions

The templates encode the rules; state them in CLAUDE.md:

- `references` include `UnityEngine.TestRunner`, `UnityEditor.TestRunner`, and the runtime assembly
  under test.
- `overrideReferences: true` with `precompiledReferences: ["nunit.framework.dll"]` — add other test
  DLLs (e.g. `NSubstitute.dll`) here.
- `defineConstraints: ["UNITY_INCLUDE_TESTS"]` and `autoReferenced: false` — tests never compile into
  player builds and nothing references them.
- One test assembly per mode per runtime assembly (or one pair for a small project). Test assemblies
  live in `Assets/Tests/EditMode/` and `Assets/Tests/PlayMode/` (or next to their runtime assembly in a
  `Tests/` folder — match the repo).

## Writing tests

- `[Test]` — synchronous; runs in both modes.
- `[UnityTest]` returns `IEnumerator`: `yield return null` advances one frame,
  `yield return new WaitForFixedUpdate()` one physics step, `yield return new WaitForSeconds(t)` scaled
  time (slow and flaky — prefer frame or step counts, or drive time explicitly).
- `[SetUp]`/`[TearDown]` and `[UnitySetUp]`/`[UnityTearDown]` (coroutine versions). Destroy everything
  a test creates — `Object.Destroy` in PlayMode, `Object.DestroyImmediate` in EditMode — or state leaks
  into the next test.
- Build the scene in code (`new GameObject().AddComponent<T>()`) rather than loading big scenes; load a
  small purpose-built test scene only when setup is too complex (it must be in the build's scene list
  for PlayMode runs in a player).
- `LogAssert.Expect(LogType.Error, …)` for expected errors; an unexpected `Debug.LogError` fails the
  test by default.
- Deterministic physics: set `Physics.simulationMode = SimulationMode.Script` and call
  `Physics.Simulate(Time.fixedDeltaTime)` per step, instead of waiting on real time.
- `[TestCase]`, `[Values]`, `[Range]` for tables of inputs — ideal for damage formulas and frame-rate
  sweeps (e.g. the same movement at 30, 60, 144 fps).

## Designing gameplay code for tests

- **Humble object:** put rules in plain C# classes (`JumpRules`, `Inventory`, `DamageCalculator`) that
  take inputs and return results; the MonoBehaviour is a thin adapter that feeds them `Time.deltaTime`,
  input values, and references. Plain classes are EditMode-testable in milliseconds.
- **Inject time and input.** Pass `deltaTime` as a parameter or behind an `IClock`; read input into a
  plain struct before logic consumes it. Tests then choose the frame rate.
- **Interfaces at the seams** (`ISaveStore`, `INetworkSender`, `IRandom`) so tests can substitute them.
- **ScriptableObject configs** can be created in tests with `ScriptableObject.CreateInstance<T>()`.

## Mocking with NSubstitute

NSubstitute is not a Unity package. The cleanest route is the UnityNuGet scoped registry, which
republishes NuGet packages for UPM — route the addition through `dependency-auditor` first:

```json
"scopedRegistries": [
  { "name": "Unity NuGet", "url": "https://unitynuget-registry.openupm.com", "scopes": ["org.nuget"] }
],
"dependencies": {
  "org.nuget.nsubstitute": "6.2.0"
}
```

(6.2.0 was the latest there on 2026-09-13; it pulls `org.nuget.castle.core` and
`org.nuget.system.threading.tasks.extensions`.) Then add `"NSubstitute.dll"` to the test asmdef's
`precompiledReferences`. Check the package's plugin import settings so test-only DLLs don't ship in
player builds.

```csharp
var clock = Substitute.For<IClock>();
clock.DeltaTime.Returns(1f / 30f);
var motor = new MotorRules(clock);
motor.Tick(jumpPressed: true);
store.Received(1).Save(Arg.Any<SaveData>());
```

Substitute **your own interfaces**, not `UnityEngine.Object` types — MonoBehaviours and
ScriptableObjects can't be meaningfully mocked; create real instances instead.

## Running tests

- **Test Runner window** (Window → General → Test Runner) for local runs.
- **Batchmode** (CI-equivalent, Editor closed on that project):
  `"$UNITY_EDITOR" -batchmode -nographics -projectPath . -runTests -testPlatform EditMode
  -testResults Logs/editmode-results.xml -logFile -` — then `-testPlatform PlayMode`. Don't pass `-quit`:
  `-runTests` exits by itself. Results are NUnit XML.
- **GameCI** — `.github/workflows/test.yml` (see `gameci-pipeline`) runs both modes on every PR and
  publishes a check run per mode; that's the gate `/claude-unity-devkit:ship` waits on.
- **Coverage** — the test runner action enables coverage flags by default; reports need
  `com.unity.testtools.codecoverage` (add via `dependency-auditor`).

## How the review lenses use this

`references/coverage-judgement.md` is the shared rubric. `gameplay-reviewer` uses it to call out
untested gameplay paths and name the test that would pin each down; `factual-reviewer` flags tests
that assert nothing or the wrong thing; `architecture-reviewer` flags logic that can't be tested
without PlayMode because it's welded to a MonoBehaviour. Findings stay in each lens's lane.

## Grounding notes

- A green run proves the tests pass, not that the game feels right; playtesting still matters.
- PlayMode tests are slower and more timing-sensitive — keep them few and deterministic.
- Don't chase a coverage percentage for gameplay code; judge whether the *risky* logic is pinned down.

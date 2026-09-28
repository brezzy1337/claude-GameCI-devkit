# GameCI troubleshooting

Symptoms, causes, and fixes for the failures that come up most with the devkit's GameCI workflows.
Sources: GameCI's activation and common-issues docs, the actions' `action.yml` and release notes,
GitHub's runner reference, and Docker Hub image metadata (sizes checked 2026-09-13).

## Contents
- License activation failures
- Out of memory on WebGL (and IL2CPP) builds
- Docker image sizes and "no space left on device"
- Other common failures
- Unity exit-code quick reference

## License activation failures

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Activation fails on pull requests from forks only | Actions secrets are not passed to fork PRs | Expected. The test template skips fork PRs (`if:` on the job); run CI after merging or from a branch in the main repo. |
| Activation fails on Dependabot PRs only | Dependabot-triggered runs read **Dependabot** secrets, not Actions secrets | Add `UNITY_LICENSE`/`UNITY_EMAIL`/`UNITY_PASSWORD` under Settings → Secrets → Dependabot, or skip Unity jobs for Dependabot. |
| "No valid license" with a Personal license | `UNITY_LICENSE` isn't the full contents of a portable `.ulf` (partial paste, wrong file) — or it's a `UnityEntitlementLicense.xml`, which is machine-bound and never activates in CI | With a real `Unity_lic.ulf`: `gh secret set UNITY_LICENSE < Unity_lic.ulf` instead of pasting. Without one, new Personal activations can't produce it — see SKILL.md → "Personal licenses without a `.ulf`". |
| "You are not eligible to activate your license offline. Offline activation is available only for Enterprise and Industry seats." | Manual activation of a `.alf` (GameCI `create-activation-file`, CircleCI orb, `unity-license-activate`) with a Personal or Pro license | Not fixable in CI. Personal: Unity CLI on a self-hosted runner or Unity Build Automation. Pro/Plus: use `UNITY_SERIAL` instead of a license file. |
| Login fails for an account created with Google/Apple sign-in | The account has no Unity password | Set one on the Unity ID site (Security), then update `UNITY_PASSWORD`. |
| "The digital signature is invalid" | The license XML was altered in transit (whitespace, line endings) | Re-upload from the file with `gh secret set … < file`. GameCI's common-issues page also describes storing the license base64-encoded and decoding it in the pipeline for custom setups. |
| Pro/Plus activation fails intermittently in a wide matrix | Concurrent jobs each activate a machine and exhaust the seat's activations | Cap `strategy.max-parallel`; licenses are returned after each job. |
| Exit code -1 within seconds, licensing messages in the log | Transient licensing-service failure | Re-run after ~30 s (GameCI's quick-reference guidance). |
| "Insufficient shared memory available … run the container with --shm-size=1025M", then retry loops that look like a license failure | Unity 6.6+ editors need 1 GiB of shared memory; Docker defaults to 64 MB | Not an activation problem. `unity-test-runner` v4.3.2+ passes `--shm-size=1025m`; keep the actions current when you move to 6.6+. |

GameCI never stores your email, password, or license; activation happens inside the job's container.

## Out of memory on WebGL (and IL2CPP) builds

**Symptoms:** the build step dies with exit code 137, "Killed", a crash in the IL2CPP or
Emscripten/wasm-ld stage, or the runner "lost communication with the server".

**Why:** WebGL builds run IL2CPP and then compile and link WebAssembly with Emscripten — the most
memory-hungry step Unity does. Standard GitHub-hosted Linux runners have 16 GB RAM for public
repositories but only 8 GB (2 vCPU) for private ones.

**Fixes, cheapest first:**
1. **Avoid link-time optimization in CI builds.** In Player Settings → Web → Publishing Settings,
   the *with LTO* Code Optimization options need far more memory at link time; use a non-LTO option
   for CI and reserve LTO for release builds on a bigger machine.
2. **IL2CPP Code Generation → "Faster (smaller) builds"** reduces generated code size.
3. **Add swap on the runner** before the build step (Docker shares the host kernel, so container
   memory can page to it). Mind the disk budget from the next section.
4. **Run WebGL alone.** Keep it in its own matrix job (the templates do) so nothing else competes.
5. **Bigger machines** — GitHub larger runners, or a self-hosted runner with 16 GB+ RAM.

`dockerMemoryLimit` only caps the container; it can't add memory. A Library cache saved from a run
that crashed mid-import can be corrupt — change the cache key prefix once after an OOM crash.

## Docker image sizes and "no space left on device"

Compressed sizes of the Unity 6000.3.24f1 editor images (`unityci/editor:ubuntu-6000.3.24f1-<module>-3`),
from Docker Hub on 2026-09-13; they expand further on disk:

| Module | Used for | Compressed size |
| --- | --- | --- |
| `base` | EditMode/PlayMode tests | 5.21 GB |
| `linux-il2cpp` | StandaloneLinux64, dedicated server | 5.68 GB |
| `windows-mono` | StandaloneWindows64 (from Linux) | 5.95 GB |
| `webgl` | WebGL | 7.45 GB |
| `android` | Android | 8.63 GB |

A standard GitHub-hosted Linux runner has a 14 GB SSD, part of it already used by preinstalled
toolchains, plus your checkout, LFS objects, and the restored `Library/`.

**Fixes:**
1. **Free disk space first** — the build template removes preinstalled toolchains for Android and
   WebGL (`/usr/share/dotnet`, `/usr/local/lib/android`, `/opt/ghc`, CodeQL) and prunes Docker images.
   Extend the step's `if:` if another target hits the limit.
2. **One target per job.** Never build several targets sequentially in one job — each pulls its own
   image. The matrix gives every target a fresh runner.
3. **Keep `containerRegistryImageVersion` at its default (`3`).** Tags ending `-0`/`-1`/`-2` are
   outdated; a "manifest … not found" error usually means an old image version or an editor version
   GameCI hasn't published yet.
4. **Self-hosted runners** — pre-pull the images you use and prune old editor versions on a schedule.

## Other common failures

- **"Scripts have compiler errors" in CI but not locally** — something the local project has isn't
  committed: a missing `.meta` (run `scripts/check-meta-files.sh --tracked`), a package only in the
  local `Library/`, a gitignored file, or a DLL checked out as an LFS pointer because checkout lacked
  `lfs: true`.
- **PackageCache / GUID / "immutable package" errors** — a stale cached `Library/PackageCache`. Change
  the cache key prefix (or delete the cache entry in the Actions UI) to start clean.
- **Unity exits 0 but produced no build** — stale `Library/SourceAssetDB` or assets generated by
  `InitializeOnLoad` scripts; clear the cache and retry.
- **"Branch is dirty. Refusing to base semantic version on uncommitted changes"** — the build modified
  tracked files. Find them in the log, reproduce locally, and commit the real change.
  `allowDirtyBuild: true` hides the problem; avoid it.
- **Version comes out as 0.0.x** — Semantic versioning found no tags: checkout needs `fetch-depth: 0`
  and the repo needs a `v*` tag.
- **"Failed to find a suitable OpenCL device for the GPU Lightmapper"** — CI has no GPU; switch the
  Lighting Settings asset's lightmapper to Progressive CPU and commit it.
- **Windows IL2CPP / macOS / signed iOS builds fail on Linux runners** — those need Windows or macOS
  runners; Linux produces Windows Mono builds and an Xcode project for iOS.
- **Check runs missing on the PR** — the workflow lacks `permissions: checks: write`, or `githubToken`
  isn't passed to the test runner.

## Unity exit-code quick reference

From GameCI's common-issues page:

| Exit code | Symptoms | Category | Fix |
| --- | --- | --- | --- |
| -1 (within seconds) | Licensing messages | License | Retry after ~30 s |
| -1 (crash log) | Bee / memory errors | Crash | Clear `Library/Bee`; reduce parallelism |
| 1 | Compiler errors | Compile | Clear `Library/ScriptAssemblies`; check for LFS-pointer `.dll` files |
| — | PackageCache / CS0246 | Package | Clear `Library/PackageCache` only |
| 0 | No output produced | Skip | Delete `Library/SourceAssetDB`; check `InitializeOnLoad` scripts |

# Dependency safety reference (Unity)

Concrete, per-source detail for the **Dependency safety** block of the CLAUDE.md section. Read this
when generating that block or tailoring the `dependency-auditor` agent (`assets/dependency-auditor.md`).
Current as of September 2026; confirm against the tools' own docs when in doubt.

## Contents
- Why a release-age cooldown
- Where Unity dependencies come from
- Enforcing the cooldown when UPM has no gate
- Other supply-chain guards
- Anti-patterns
- `dependency-auditor` agent

## Why a release-age cooldown

Most malicious package versions are detected and pulled from the registry within hours to a
couple of days. Recent npm examples were caught fast — the Shai-Hulud worm within ~12 hours, the
debug/chalk compromise in ~2.5 hours — and OpenUPM, scoped registries, and NuGet are served by the
same kind of infrastructure. A cooldown ("minimum release age") refuses a version until it has been
public long enough for that detection to happen. The devkit's default is 7 days; the trade-off is
freshness, and the standard carve-out is genuine security fixes.

## Where Unity dependencies come from

| Source | Declared in | Pin by | Check age / existence with |
| --- | --- | --- | --- |
| Unity registry (`com.unity.*`) | `Packages/manifest.json` | exact version (UPM has no ranges) | `npm view <pkg> time --registry https://packages.unity.com` or WebFetch `https://packages.unity.com/<pkg>` |
| Scoped registries (OpenUPM, UnityNuGet, company) | `manifest.json` `scopedRegistries` + `dependencies` | exact version; narrow `scopes` | `npm view <pkg> time --registry <url>` |
| Git URL | `manifest.json` (`https://…/repo.git#v1.2.3`) | tag or commit SHA — never a branch; `packages-lock.json` records the resolved `hash` | the tag/commit date on the host |
| Local / embedded (`file:…`, `Packages/<name>/`) | `manifest.json` / folder | the repo itself | code review |
| Asset Store | imported into `Assets/` (or UPM via "My Assets") | the imported version | publisher page; **licensing check** |
| NuGet DLLs (NuGetForUnity, UnityNuGet, manual) | `Assets/Plugins/**`, `packages.config`, or scoped registry | exact version | nuget.org version history; NuGet advisories |
| GitHub Actions | `.github/workflows/*.yml` `uses:` | major tag or full commit SHA | the action's releases page |
| Core/built-in packages (`com.unity.ugui`, `com.unity.test-framework`, `com.unity.modules.*`) | `manifest.json` | the editor version | pinned by the editor — upgrade the editor, not the package |

## Enforcing the cooldown when UPM has no gate

Unity's Package Manager has no `minimumReleaseAge`-style setting, and GitHub's advisory database and
OSV don't cover UPM packages. Enforcement is therefore layered:

1. **Review gate (primary).** Every add or bump goes through `dependency-auditor`, which reads the
   publish time and returns NO-GO for anything younger than the cooldown. `/ship`'s preflight
   dispatches it whenever `manifest.json`, `packages-lock.json`, `Assets/Plugins/`, or workflow
   `uses:` lines change.
2. **GitHub Actions — Dependabot cooldown.**
   ```yaml
   # .github/dependabot.yml
   version: 2
   updates:
     - package-ecosystem: "github-actions"
       directory: "/"
       schedule: { interval: "weekly" }
       cooldown:
         default-days: 7
   ```
3. **Update bots for UPM (optional).** Dependabot has no Unity ecosystem. Renovate can track UPM
   manifests through a custom regex manager pointed at the npm datasource with the registry URL, and
   applies `minimumReleaseAge: "7 days"` to what it proposes — verify the config against Renovate's
   current docs before relying on it.
4. **Human gate.** `manifest.json` and `packages-lock.json` are single-owner files; changes to them
   are called out in the PR body by `pr-author`.

## Other supply-chain guards

- **Verify before adding (anti-slopsquatting / typosquatting).** The agent proposing the package is
  itself a risk: it can name a package that doesn't exist, which attackers pre-register. Confirm the
  package exists, is canonical (repo link resolves, real adoption/history), and the name isn't a
  near-miss of a popular package.
- **Narrow scoped-registry scopes (dependency confusion).** A scoped registry is consulted for every
  package whose name starts with one of its `scopes`. A broad scope (`com`, `com.unity`) lets that
  registry serve packages that should come from Unity. Scope to the publisher (`com.cysharp`,
  `org.nuget`).
- **Commit `packages-lock.json`.** It is the integrity record: resolved versions, sources, and git
  hashes. Review diffs to it; an unexpected change means something resolved differently.
- **Pin git dependencies** to a tag or commit. A branch ref silently changes under you.
- **Treat Editor code as install-time execution.** Any `[InitializeOnLoad]` script, `AssetPostprocessor`,
  or Editor-assembly code inside a package runs with your privileges as soon as the Editor loads it —
  the Unity equivalent of an npm `postinstall` script. Read a new package's `Editor/` folder before
  adding it.
- **DLLs are code you can't read.** Prefer packages with source; route precompiled DLLs through LFS,
  record where they came from, and set their platform import settings explicitly.
- **Asset Store licensing.** Content under the Standard Unity Asset Store EULA may not be redistributed
  — it must never be committed to a public repository. Editor extensions are licensed per seat.
- **Pin Actions** to a major tag or SHA; a floating major can change architecture (it happened to
  `unity-test-runner@v4`).

## Anti-patterns

- Cooling down new packages but letting transitive or git-branch dependencies float.
- Treating the CLAUDE.md rule as the enforcement layer. The auditor, the lock file, pinned refs, and
  the human review are what actually hold.
- Auto-bypassing the cooldown for "just this once." Route exceptions through a human with a reason.
- Adding a broad scoped registry "to make a package resolve".

## `dependency-auditor` agent

The plugin ships a ready-to-use read-only auditor (`claude-unity-devkit:dependency-auditor`); a copy
is in `assets/dependency-auditor.md` for repos that want a project-local version. It checks, per
source: existence and canonicalness, release age against the cooldown, Unity compatibility (the
package's `unity` field vs the editor version, pre-release status), advisories, provenance, git-ref
pinning, scoped-registry scope width, and Asset Store licensing — and returns GO or NO-GO with the
single biggest risk.

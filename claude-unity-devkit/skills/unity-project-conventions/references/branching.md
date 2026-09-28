# Branching for a small Unity team

A model for teams of roughly 3–15 with mixed roles (feature programmers, level/character designers,
artists). It is CI-agnostic: the `unity-init` (Unity CLI) and `gameci-pipeline` workflows both key
their triggers off it, and `/code-todo` and `/ship` target the integration branch recorded in
CLAUDE.md.

## Branches

```
main ─────●──────────────────●──────────   production: only release merges, tagged v*
           \                /
stable ─────●──●──●──●──●──●────────────   integration: always playable → playtest build
             \   ↗  \  ↗
 feature/inventory  level/forest-01        short-lived, one owner, merged by PR
```

| Branch | Purpose | Who | Merges into | CI |
| --- | --- | --- | --- | --- |
| `main` | What ships. Every commit is a release. | Release owner | — | `v*` tag → release build (+ deploy) |
| `stable` | Integration. Always opens and plays. | Everyone, via PR | `main` at release time | push → tests + playtest build |
| `feature/<name>` | Core mechanics, systems, tools | Programmers | `stable` | PR → tests |
| `level/<name>` | Levels, characters, set dressing | Designers | `stable` | PR → tests |
| `art/<name>` (optional) | Asset batches | Artists | `stable` | PR → tests |
| `hotfix/<name>` | Urgent fix to a release | Anyone | `main` **and** `stable` | PR → tests |

## Rules that make it work in Unity

- **Short-lived branches.** Days, not weeks. Scenes and prefabs are YAML that merges poorly; the
  longer two branches diverge, the worse the conflict. Merge `stable` into your branch often
  (`unity vcs sync` on `stable`, then merge).
- **Feature flags over long branches.** An unfinished mechanic merges early behind a flag (a
  ScriptableObject toggle or `#if` define) instead of living on a branch for a month.
- **One owner per scene at a time.** Mark `*.unity` `lockable` in `.gitattributes`; lock before
  editing (`git lfs lock Assets/Scenes/Forest.unity`), unlock after merging. Lockable files check out
  read-only until locked, which is the reminder.
- **Split big levels.** Additive sub-scenes and prefabs let two designers work on one level without
  touching the same file.
- **Binary art is unmergeable.** `*.psd`, `*.fbx`, `*.blend`, textures, audio live in LFS; mark the
  ones people edit in place `lockable` too.
- **Scene/prefab merges use UnityYAMLMerge.** `unity vcs merge-setup` once per clone; resolve with
  `unity vcs conflicts` / `explain` / `resolve`.
- **Switch branches with the Editor closed** — `unity vcs switch` refuses otherwise and reports the
  reimport cost. `unity vcs git worktree add` gives a second branch without a cold reimport.

## Real-time scene co-editing (Scene Fusion)

KinematicSoup's Scene Fusion lets several people edit one scene live, each in **their own local
Editor** (its session service syncs changes; selecting an object locks it to that person). It works
alongside git, not instead of it:

- Everyone pulls first; one person **hosts** the session, **holds the scene's `git lfs lock`**, and
  is the only one who saves and commits the scene and any new assets. Participants discard their
  local changes afterwards (Scene Fusion's "single committer" pattern) — which fits a `level/*` branch.
- Add `KinematicSoup/` to `.gitignore` (local logs and config).
- It doesn't need a shared VM or remote workstation. Don't set one up for this: Unity Personal is
  licensed per person (no shared logins), multi-user Windows remote desktop needs Server/RDS or
  multi-session licensing, and the Editor wants a real GPU. Free for two people; paid beyond.
- It has no effect on CI or licensing.

## Releasing

1. PR `stable` → `main` (title `Release vX.Y.Z`). Tests must pass.
2. After merge: `git tag vX.Y.Z origin/main && git push origin vX.Y.Z` → release build.
3. Hotfixes land on `main`, get tagged, and are merged back into `stable` the same day.

## Setting it up (the human runs the outward-facing parts)

```bash
git switch -c stable main && git push -u origin stable        # create the integration branch
gh repo edit --default-branch stable                          # PRs default to stable (optional)

# Protect main and stable: PR required, tests required, no force-push. Check name = the
# workflow's test job ("Test (EditMode + PlayMode)").
gh api -X PUT repos/<owner>/<repo>/branches/stable/protection --input - <<'EOF'
{"required_status_checks":{"strict":true,"contexts":["Test (EditMode + PlayMode)"]},
 "enforce_admins":false,"required_pull_request_reviews":{"required_approving_review_count":1},
 "restrictions":null,"allow_force_pushes":false,"allow_deletions":false}
EOF
```

Branch protection on private repos needs a paid GitHub plan (Team/Pro); on Free, agree on the rules
and rely on the required PR habit. Rulesets (`gh api repos/<owner>/<repo>/rulesets`) are the newer
alternative with the same plan requirement.

## Record in CLAUDE.md

```markdown
## Branching

- `main` = production (release merges + `v*` tags only). `stable` = integration; PRs target `stable`.
- Branch from `stable`: `feature/<name>` (code), `level/<name>` (levels/characters), `art/<name>`.
- Keep branches short-lived; hide unfinished mechanics behind a flag and merge early.
- Lock scenes before editing (`git lfs lock <path>`); switch branches with `unity vcs switch`.
```

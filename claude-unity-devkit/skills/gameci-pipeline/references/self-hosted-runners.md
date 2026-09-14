# Self-hosted runners for GameCI

The devkit templates default to GitHub-hosted `ubuntu-latest`. Use this page when `setup-ci` is told
the team runs its own runners, or when hosted runners are too small (WebGL/IL2CPP memory, disk).

## Labels

A self-hosted runner automatically carries `self-hosted`, its OS (`linux`), and its architecture
(`x64`); add custom labels when registering it (e.g. `unity`, `gpu`, `bigmem`). `runs-on` with an
array requires **all** listed labels:

```yaml
runs-on: [self-hosted, linux, x64, unity]
```

Record the team's exact label set in CLAUDE.md's CI subsection; `ci-reviewer` checks workflows
against it. Keep different hardware classes on different labels (`bigmem` for WebGL) and route only
the jobs that need them there with a matrix field:

```yaml
strategy:
  matrix:
    include:
      - targetPlatform: WebGL
        runner: [self-hosted, linux, x64, unity, bigmem]
      - targetPlatform: StandaloneLinux64
        runner: [self-hosted, linux, x64, unity]
runs-on: ${{ matrix.runner }}
```

## Host requirements

- **Linux x64 with Docker.** With the default `providerStrategy: local`, the GameCI actions run the
  Editor inside `unityci/editor` containers on Linux, so the runner user needs Docker access.
- **Disk.** Editor images are 5–9 GB compressed per module, plus Libraries and builds — plan for
  100 GB+ and prune old images regularly (`docker image prune`).
- **Memory.** 16 GB+ for WebGL and IL2CPP builds.

## Template changes for self-hosted

1. Replace `runs-on: ubuntu-latest` with the label array.
2. **Delete the "Free disk space" steps** — they delete toolchains from *your* machine.
3. **File ownership** — containers run as root by default, leaving root-owned files in the workspace
   that the next checkout can't clean. Set `runAsHostUser: 'true'` on both GameCI steps (Linux hosts),
   or `chownFilesTo: <uid>:<gid>`.
4. **Library cache** — keep the `actions/cache` step (it still works and keeps jobs independent). A
   persistent workspace Library (`actions/checkout` with `clean: false`) is faster but carries state
   between runs and branches; only use it on a runner dedicated to one repository and one target.
5. **Concurrency** — one runner process runs one job at a time; register several runner instances
   (with separate work directories) on a big machine rather than sharing one.

## Security

- **Never let untrusted code reach a self-hosted runner.** For public repositories, a pull request
  from a fork can run arbitrary code on the machine; keep fork PR workflows on GitHub-hosted runners
  (the test template already skips fork PRs) and require approval for outside contributors.
- Prefer **ephemeral** runners (one job, then re-provisioned) for anything touching secrets.
- The license secrets reach the container environment during the job; don't share the machine with
  untrusted workloads.

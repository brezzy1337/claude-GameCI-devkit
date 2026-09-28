# Unity Build Automation — Dashboard setup checklist

For the human. Every step is in the Unity Cloud Dashboard or GitHub; nothing needs the Editor.
Menu names verified against Unity's docs on 2026-09-28 — Unity reorganizes the Dashboard, so search
for the section name if a path moved.

## 1. Turn on DevOps (free plan)

Dashboard → **Development → Products → DevOps** → choose or create the project for this game →
**Launch** → **Start free trial** (the free plan; *Subscribe* is pay-as-you-go).

## 2. Connect the GitHub repository

Create a GitHub **fine-grained personal access token**:
- Repository access: only this repository.
- Permissions: **Contents: Read-only**. Add **Webhooks: Read and write** only if you want Unity's
  own auto-build (the devkit's workflow triggers builds from GitHub instead, so leave it off).
- Set an expiry and a reminder; builds fail to check out when it expires.

Build Automation → **Settings → Source control** → **GitHub** → paste the token → **Authorize** →
pick the repository → **Save**. (SSH/deploy keys are supported for plain Git, but whether they work
with Git LFS is undocumented — use the token.)

## 3. Service account for GitHub Actions

Dashboard → account menu → **Manage organization → Service Accounts**. Use one per consumer (e.g.
`github-actions-<repo>`); create it with **New** if needed, then **Keys → Add key** — the Key ID and
Secret are shown once. Add the role **Automation → Automation User**, scoped to this project.
Without it every API call returns 403.

## 4. Build target

Build Automation → **Configurations → Target setup**:
- **Name** e.g. `windows-playtest`; **Branch** = the integration branch (e.g. `stable`).
- **Unity version**: **Auto detect** (reads `ProjectSettings/ProjectVersion.txt`) — confirm the
  project's version is offered. If it isn't, stop: wait for Unity to add it or move to a supported LTS.
- **Builder operating system**: Windows (for Windows targets).
- **Advanced settings → Tests**: tick **Run my project's unit tests when building**, **Run EditMode
  tests**, **Run PlayMode tests**, **Mark build as failed if any test fails**.
- **Scheduling → Auto-build: off** — GitHub Actions triggers builds; with both on, every push builds
  twice and spends double minutes.

## 5. Protect the budget

Build Automation → **Build History → Max concurrent builds → Manage → 1**. Unity emails the org owner
at 50%, 75%, and 90% of the free allowance; exceeding it blocks the project until a payment method
is added.

## 6. Find the org ID (GitHub Actions needs the right one)

An org has two IDs (`unity cloud org list` shows both: `id` and `genesisId`); the API docs don't say
which it takes. With the service-account key:

```bash
read -rp "Key ID: " K; read -rsp "Secret: " S; echo
for ORG in <genesisId> <id>; do
  curl -s -o /dev/null -w "$ORG -> %{http_code}\n" -u "$K:$S" \
    "https://build-automation.services.api.unity.com/v2/orgs/$ORG/projects/<project-id>/buildtargets"
done
```

Use the one that returns `200`. Both `403` → the Automation User role isn't assigned yet.

## 7. GitHub repository settings

```bash
gh secret set UNITY_SERVICE_ACCOUNT_ID
gh secret set UNITY_SERVICE_ACCOUNT_SECRET
gh variable set UBA_ORG_ID --body <org id from step 6>
gh variable set UBA_PROJECT_ID --body <project id>
gh variable set UBA_TARGET --body <target id, e.g. windows-playtest>
gh label create cloud-ci --description "Run tests + build in Unity Build Automation" --color 1D76DB
```

In a Codespace the built-in token can't manage secrets or variables: run `unset GITHUB_TOKEN` and
`gh auth login -s repo` in that terminal first.

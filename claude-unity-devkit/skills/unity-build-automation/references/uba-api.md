# UBA v2 REST API crib

From the Build Automation Client API v2.0.0 OpenAPI spec
(https://docs.unity.com/en-us/oas-build-automation-client/2.0.0) and Unity's v1→v2 migration article,
read 2026-09-28. Re-check the spec before using an endpoint or field not listed here.

## Base and auth

- Base: `https://build-automation.services.api.unity.com/v2`
- HTTP Basic with a **service account** key: `curl -u "$KEY_ID:$SECRET"`. No token exchange (the
  `auth/v1/token-exchange` flow returns `401 Untrusted issuer` here).
- Role: **Automation User** (org or project level); without it → 403.
- v1 (`build-api.cloud.unity3d.com/api/v1`, `Bearer <API key>`) is removed 2026-12-21.

`T` below = `/orgs/{orgid}/projects/{projectid}/buildtargets/{buildtargetid}`.

## Endpoints

| Call | Method + path | Notes |
| --- | --- | --- |
| List targets | `GET /orgs/{orgid}/projects/{projectid}/buildtargets` | `limit`, `offset`, `branch`, `include_last_success` |
| Start build | `POST T/builds` | **202** + *array* of builds (`[0].build` = number). **409** = a build is already pending; **422** = refused. Body: `clean`, `delay` (ms), `branch` (override), `commit`, `causedBy`, `machineTypeLabel`, `unityVersion`, `envvars`. `{"clean": false}` uses the target's own config. |
| Build status | `GET T/builds/{number}` | `buildStatus`; `include=testResults,failureDetails,buildReports,links.artifacts` |
| List builds | `GET T/builds?per_page=&page=&buildStatus=` | |
| Log | `GET T/builds/{number}/log` | Redirects (303/307) to a signed URL — use `curl -L`. `offsetlines`, `maxLines`, `progressive` |
| Artifacts | `GET T/builds/{number}/artifacts` | `[{key, name, primary, files:[{filename, size, href}]}]` |
| Download | `GET T/builds/{number}/download/{filename}` | **303 with the signed URL in the JSON body `url`**, no `Location` header — read the body, then GET the URL |
| Share | `POST T/builds/{number}/share` `{shareExpiry}` | 201 `{shareid, shareExpiry}`; calling again revokes the old share. Public share URL format undocumented |
| Cancel | `DELETE T/builds/{number}` | 204; no-op on finished builds. `DELETE T/builds` cancels all |
| Failures | `GET T/builds/{number}/failures` | |
| Free tier | `GET /orgs/{orgid}/free-tier-status` | `{freeTierLimitReached}` — check before starting |
| Concurrency | `GET /orgs/{orgid}/concurrency-limit` | `{limit, maxAllowable}` |
| Machine types | `GET .../machinetypes` | each has `freeTierEligible` |
| Unity versions | `GET .../versions/unity` | check the project's version is supported |

## Fields

- `buildStatus`: `unknown`, `created`, `queued`, `assignedToBuilder`, `sentToBuilder`, `started`,
  `restarted`, `success`, `failure`, `canceled`, `processing`. Terminal: `success`, `failure`,
  `canceled`, `unknown`.
- `queuedReason` (e.g. `concurrency`, `waitingForBuildAgent`, `cooldown`); `canceledBy` (e.g.
  `service-timelimit`, `billing-invalidsubscription`).
- `testResults.{unit_test, unit_test_editmode, unit_test_playmode}` → `{passed, failed, duration}`.
- Also: `scmBranch`, `lastBuiltRevision`, `billableTimeInSeconds`, `totalTimeInSeconds`,
  `buildTimeoutMinutes`, `failureDetails[]`.
- Target test settings (in the target's Unity config): `runUnitTests`, `runEditModeTests`,
  `runPlayModeTests`, `failedUnitTestFailsBuild`.

## Unity CLI (read-only)

`unity pipeline cloud-build targets list|get <id>` and `builds list|get <n> --build-target <id>`,
with `--cloud-org` / `--cloud-project` (env `UNITY_CLOUD_ORG`, `UNITY_CLOUD_PROJECT`). Uses the signed-in
person's session; it cannot start builds.

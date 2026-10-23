# Onboarding guide for application teams

Goal: a new repository goes from "no pipeline" to "governed build and
multi-environment deployment" in under an hour, without writing pipeline logic.

## 0. What the platform team provides (once per application)

| Item | How | Name convention |
|---|---|---|
| Azure DevOps environments with checks | `platform/azure-devops-governance` | `<app>-dev`, `<app>-test`, `<app>-prod` |
| WIF service connections per environment | same | `sc-<app>-<env>` |
| Build service connection with `AcrPush` | portal, or extend the module | `sc-<app>-build` |
| GitHub service connection to this template repo | Project settings (one per project) | `github-platform-templates` |
| AKS namespace + RBAC for the deploy identity | landing zone / cluster bootstrap | `<app>` |

Ask for these with the application name and the list of environments; nothing
else is needed from the team.

## 1. Prepare the repository

```text
.
|-- azure-pipelines.yml
|-- Dockerfile
|-- src/ ... tests/
`-- deploy/
    `-- helm/                 # chart exposing image.repository and image.digest
        |-- Chart.yaml
        |-- values.yaml
        |-- values-dev.yaml
        |-- values-test.yaml
        `-- values-prod.yaml
```

Helm chart contract - render the image by digest:

```yaml
# templates/deployment.yaml (excerpt)
image: "{{ .Values.image.repository }}@{{ .Values.image.digest }}"
```

Using Kustomize instead? Set `method: kustomize`, put overlays in
`deploy/overlays/<env>`, and reference the image as `app` (or set
`kustomizeImageName`).

## 2. Add the pipeline

Copy `examples/aks-web-app/azure-pipelines.yml`, then change the application
name, registry, repository and service connection names. Keep
`ref: refs/tags/vX.Y.Z` pinned to the latest release in
[CHANGELOG.md](../CHANGELOG.md).

## 3. Create the pipeline in Azure DevOps

1. *Pipelines > New pipeline >* select the repository and *Existing Azure
   Pipelines YAML file*.
2. First run: approve access to the template repository resource and to each
   service connection / environment when prompted (one-time authorisation).
3. Open a pull request: the run shows `SecurityBaseline` and `Build`, no deploy
   stages execute (pull requests never deploy).
4. Merge: `Deploy_dev` runs automatically; `Deploy_test` and `Deploy_prod` wait
   for their approvals and business hours.

## 4. What you get without writing it

- Secret scan of the full git history, source SBOM, dependency and IaC scan
- Unit tests with coverage gate and published results
- Image vulnerability gate **before** the push, image SBOM
- The same image digest deployed to every environment
- Approvals, business hours, exclusive lock, Required template checks
- Smoke test and automatic rollback in production
- Run tags (`governed`, `template-library-vX.Y.Z`, `deployed-<env>`) for audits

## 5. Upgrading the template version

1. Read the [CHANGELOG](../CHANGELOG.md) entries between your version and the target.
2. Change `ref: refs/tags/vX.Y.Z` in a pull request; the PR run validates the
   new version end to end without deploying.
3. MAJOR versions list required changes under *Changed* / *Removed*.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Unexpected value 'POLICY VIOLATION - ...'` | The pipeline breaks a governance rule | See [governance-model.md](governance-model.md); move the logic into a library template or request a new one |
| Stage waits with *"Required template check failed"* | Pipeline does not extend the governance template at an allowed tag | Use `extends` and a supported `refs/tags/v...` |
| `imageRef ... is not digest-pinned` | Build stage did not push (pull request or `pushPolicy: never`) | Deploy from `main`; check the `push` step output |
| Terraform `Saved plan is stale` | State changed between plan and apply | Re-run the pipeline; the new plan is reviewed again |
| `AADSTS700213` / no matching federated identity | Service connection renamed or moved project | Update the federated credential subject (Terraform does it automatically) |

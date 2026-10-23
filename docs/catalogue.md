# Template catalogue

Every template in this library, grouped by layer. Each section lists the
parameters exactly as declared in the template - CI fails if a parameter is
added, removed or renamed without updating this page (`scripts/lint-templates.sh`).

Conventions used by every template:

- All parameters are strongly typed and carry a `displayName`; restricted strings use `values`.
- Tool binaries are version-pinned **and** SHA-256 verified; tasks are pinned to a major version.
- Template parameters reach scripts through `env:` - never interpolated into script bodies.
- Inside the library, templates reference each other with relative paths, so a consumer only ever references `@templates`.

| Layer | Purpose | Consumers use it directly? |
|---|---|---|
| `governance/` | `extends` template that wraps every pipeline | Yes - mandatory |
| `stages/` | Opinionated, composable stage blueprints | Yes - preferred entry point |
| `jobs/` | Single-purpose jobs (build, test, plan, deploy) | Yes, inside raw stages |
| `steps/` | Low-level building blocks | Rarely - mostly used by jobs |

## Governance

### `templates/governance/secure-pipeline.yml`

The organisation-wide `extends` template. Injects the mandatory `SecurityBaseline` stage, rewrites consumer stage dependencies and conditions so the baseline cannot be bypassed, and rejects (at compile time) inline scripts, shell-wrapper tasks, raw deployment jobs, templates from foreign repositories and `persistCredentials: true`. See [governance-model.md](governance-model.md) for the full rule set.

```yaml
extends:
  template: templates/governance/secure-pipeline.yml@templates
  parameters:
    securityProfile: strict
    stages:
      - template: templates/stages/container-ci.yml@templates
        parameters: { acrName: acrshop, repository: shop/web, azureServiceConnection: sc-shop-build }
```

| Parameter | Type | Default | Description |
|---|---|---|---|
| `stages` | stageList | `[]` | Consumer stages - raw stages or stage templates from @templates |
| `securityProfile` | string | `standard` | standard blocks HIGH/CRITICAL findings, strict also blocks MEDIUM (one of: `standard`, `strict`) |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool for the injected security stage |

## Stage templates

### `templates/stages/aks-promotion.yml`

Generates one deployment stage per environment (`Deploy_<name>`). Order is declared with `promoteFrom`, which supports fan-out. Pull requests never deploy; only `deployBranch` does. Each stage deploys the same image digest produced by `container-ci.yml`.

Environment object keys: `name` (required), `serviceConnection` (required), `resourceGroup` (required), `cluster` (required), `promoteFrom`, `namespace` (default `appName`), `environment` (default `<appName>-<name>`), `smokeTestUrl`.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `appName` | string | **required** | Application name (default namespace, release name and environment prefix) |
| `environments` | object | **required** | Ordered list of environment objects (see header) |
| `method` | string | `helm` | Deployment tool (one of: `helm`, `kustomize`) |
| `helmChartPath` | string | `deploy/helm` | Helm chart path (helm) |
| `helmValuesDirectory` | string | `''` | Directory with values-&lt;env&gt;.yaml files; empty to use chart defaults only (helm) |
| `kustomizeOverlayRoot` | string | `deploy/overlays` | Directory containing one overlay per environment name (kustomize) |
| `kustomizeImageName` | string | `app` | Image name used in the manifests (kustomize) |
| `rolloutResources` | object | `[]` | Workloads awaited and rolled back (kustomize) |
| `buildStageName` | string | `Build` | Stage that produced the image (container-ci stageName) |
| `deployBranch` | string | `refs/heads/main` | Only this branch may deploy; pull requests never deploy |
| `dependsOn` | object | `[]` | Extra dependencies for the entry stages (the governance template adds SecurityBaseline) |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool |

### `templates/stages/container-ci.yml`

CI for a containerised application: optional unit-test job (.NET or Node, with coverage gate) followed by build, Trivy image scan, image SBOM and a digest-pinned push to ACR. Exposes `stageDependencies.<stageName>.ContainerBuild.outputs['push.imageRef']`.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `stageName` | string | `Build` | Stage identifier (deploy stages reference it) |
| `testStack` | string | `none` | Unit test toolchain (one of: `dotnet`, `node`, `none`) |
| `azureServiceConnection` | string | **required** | ARM service connection (Workload Identity Federation) with AcrPush |
| `acrName` | string | **required** | Azure Container Registry name |
| `repository` | string | **required** | Image repository, e.g. shop/web |
| `dockerfile` | string | `Dockerfile` | Path to the Dockerfile |
| `buildContext` | string | `.` | Docker build context |
| `buildArgs` | object | `[]` | List of KEY=VALUE build arguments |
| `pushPolicy` | string | `nonPullRequest` | When the image is pushed to ACR (one of: `always`, `nonPullRequest`, `never`) |
| `minimumLineCoverage` | number | `80` | Coverage gate for the unit test job |
| `testWorkingDirectory` | string | `.` | Working directory for Node tests |
| `dependsOn` | object | `[]` | Extra stage dependencies (the governance template adds SecurityBaseline) |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool |

### `templates/stages/terraform-promotion.yml`

Generates `Plan_<name>` and `Apply_<name>` stages per environment. Plans run on every build (including pull requests) with an optional read-only identity; applies run only on `deployBranch`, only when the plan has changes, and only after the environment checks pass. A promoted environment is planned only after the previous one applied successfully or had nothing to apply.

Environment object keys: `name` (required), `serviceConnection` (required), `planServiceConnection`, `promoteFrom`, `environment` (default `<environmentPrefix>-<name>`), `varFile`.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `environmentPrefix` | string | **required** | Prefix for Azure DevOps environment names and state keys, e.g. shop-infra |
| `environments` | object | **required** | Ordered list of environment objects (see header) |
| `workingDirectory` | string | **required** | Terraform root module directory |
| `varFileDirectory` | string | `''` | Directory with &lt;env&gt;.tfvars files, relative to workingDirectory; empty for none |
| `terraformVersion` | string | `1.16.5` | Terraform CLI version |
| `backendResourceGroup` | string | **required** | Resource group of the state storage account |
| `backendStorageAccount` | string | **required** | State storage account name |
| `backendContainer` | string | `tfstate` | Blob container holding the state files |
| `iacScan` | boolean | `true` | Trivy misconfiguration scan before every plan |
| `deployBranch` | string | `refs/heads/main` | Only this branch may apply; pull requests only plan |
| `dependsOn` | object | `[]` | Extra dependencies for the entry stages (the governance template adds SecurityBaseline) |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool |

### `templates/stages/security-baseline.yml`

Mandatory first stage, injected by the governance template (consumers do not reference it directly). Runs `SecretScan` and `SupplyChainScan` in parallel and tags the run with `governed`, `template-library-vX.Y.Z` and `security-profile-<profile>` as an audit trail.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `securityProfile` | string | `standard` | standard blocks HIGH and CRITICAL findings, strict also blocks MEDIUM (one of: `standard`, `strict`) |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool |

## Job templates

### `templates/jobs/aks-deploy.yml`

Deployment job (`runOnce`) on an Azure DevOps environment. `deploy` runs Helm (`--rollback-on-failure`) or Kustomize (server-side apply + rollout status), `postRouteTraffic` runs the optional smoke test, `on.failure` performs an automatic rollback that only touches the release if it is running the digest from this run, and `on.success` tags the run with `deployed-<env>`.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | string | `Deploy` | Job identifier |
| `environmentName` | string | **required** | Logical environment name (dev, test, prod...) |
| `environment` | string | **required** | Azure DevOps environment that carries the approvals and checks |
| `azureServiceConnection` | string | **required** | ARM service connection (Workload Identity Federation) with AKS RBAC on the namespace |
| `resourceGroup` | string | **required** | Resource group of the AKS cluster |
| `clusterName` | string | **required** | AKS cluster name |
| `namespace` | string | **required** | Target Kubernetes namespace |
| `imageRef` | string | `$(imageRef)` | Image to deploy in repository@sha256:digest form (usually a runtime variable) |
| `method` | string | `helm` | Deployment tool (one of: `helm`, `kustomize`) |
| `helmChartPath` | string | `deploy/helm` | Helm chart path (helm) |
| `helmReleaseName` | string | `''` | Helm release name (helm) |
| `helmValuesFiles` | object | `[]` | Ordered values files (helm) |
| `helmSetValues` | object | `{}` | Extra non-secret values (helm) |
| `helmImageDigestKey` | string | `image.digest` | Chart value receiving the image digest (helm) |
| `kustomizeOverlayPath` | string | `''` | Overlay directory (kustomize) |
| `kustomizeImageName` | string | `app` | Image name used in the manifests (kustomize) |
| `rolloutResources` | object | `[]` | Workloads awaited and rolled back (kustomize), e.g. [deployment/web] |
| `smokeTestUrl` | string | `''` | Optional HTTPS endpoint probed after deployment; failure triggers rollback |
| `variables` | object | `{}` | Job variables, e.g. imageRef mapped from stageDependencies |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool |
| `timeoutInMinutes` | number | `30` | Job timeout |

### `templates/jobs/container-build.yml`

Build, scan, SBOM and push. Nothing reaches the registry before passing the Trivy gate. Push is skipped for pull requests by default (`pushPolicy: nonPullRequest`). Output: `push.imageRef` (`<registry>/<repo>@sha256:<digest>`).

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | string | `ContainerBuild` | Job identifier |
| `azureServiceConnection` | string | **required** | ARM service connection (Workload Identity Federation) with AcrPush on the registry |
| `acrName` | string | **required** | Azure Container Registry name (without .azurecr.io) |
| `repository` | string | **required** | Image repository inside the registry, e.g. shop/web |
| `imageTag` | string | `$(Build.BuildId)` | Image tag (the digest is what gets deployed; the tag is for humans) |
| `dockerfile` | string | `Dockerfile` | Path to the Dockerfile |
| `buildContext` | string | `.` | Docker build context |
| `buildArgs` | object | `[]` | List of KEY=VALUE build arguments |
| `trivySeverity` | string | `HIGH,CRITICAL` | Severities that block the push (one of: `CRITICAL`, `HIGH,CRITICAL`, `MEDIUM,HIGH,CRITICAL`) |
| `pushPolicy` | string | `nonPullRequest` | When the image is pushed to ACR (one of: `always`, `nonPullRequest`, `never`) |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool |
| `dependsOn` | object | `[]` | Jobs this job depends on |
| `timeoutInMinutes` | number | `30` | Job timeout |

### `templates/jobs/dotnet-test.yml`

`dotnet test` with coverlet (`XPlat Code Coverage`), publishing results to the Tests tab and Cobertura coverage to the Code Coverage tab, followed by the coverage gate.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | string | `DotNetTest` | Job identifier |
| `dotnetVersion` | string | `10.0.x` | .NET SDK version or wildcard (ignored when useGlobalJson is true) |
| `useGlobalJson` | boolean | `false` | Resolve the SDK version from global.json |
| `projects` | string | `**/*Tests.csproj` | Glob of test projects |
| `buildConfiguration` | string | `Release` | Build configuration (one of: `Debug`, `Release`) |
| `minimumLineCoverage` | number | `80` | Minimum line coverage in percent (0 disables the gate) |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool |
| `dependsOn` | object | `[]` | Jobs this job depends on |
| `timeoutInMinutes` | number | `30` | Job timeout |

### `templates/jobs/node-test.yml`

`npm ci` with an npm cache, runs the given npm script, publishes JUnit results and Cobertura coverage, then applies the coverage gate. The npm script must emit JUnit XML and a Cobertura report.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | string | `NodeTest` | Job identifier |
| `nodeVersion` | string | `24.x` | Node.js version spec |
| `workingDirectory` | string | `.` | Directory containing package.json and package-lock.json |
| `testScript` | string | `test:ci` | npm script that runs the tests with coverage |
| `testResultsFiles` | string | `junit.xml` | Glob of JUnit result files, relative to workingDirectory |
| `coverageDirectory` | string | `coverage` | Directory of the Cobertura report, relative to workingDirectory |
| `coverageFileName` | string | `cobertura-coverage.xml` | Cobertura report file name |
| `minimumLineCoverage` | number | `80` | Minimum line coverage in percent (0 disables the gate) |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool |
| `dependsOn` | object | `[]` | Jobs this job depends on |
| `timeoutInMinutes` | number | `30` | Job timeout |

### `templates/jobs/secret-scan.yml`

Full-history gitleaks scan (`fetchDepth: 0`). Also emits the audit run tags passed in `buildTags`.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | string | `SecretScan` | Job identifier |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool |
| `dependsOn` | object | `[]` | Jobs this job depends on |
| `failOnFindings` | boolean | `true` | Fail the job when a secret is detected |
| `buildTags` | object | `[]` | Tags added to the pipeline run (audit trail of governance and template version) |
| `timeoutInMinutes` | number | `15` | Job timeout |

### `templates/jobs/supply-chain-scan.yml`

Source SBOM (syft, SPDX + CycloneDX) and a Trivy filesystem scan covering dependency vulnerabilities and IaC misconfigurations.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | string | `SupplyChainScan` | Job identifier |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool |
| `dependsOn` | object | `[]` | Jobs this job depends on |
| `severity` | string | `HIGH,CRITICAL` | Trivy severities that fail the job (one of: `CRITICAL`, `HIGH,CRITICAL`, `MEDIUM,HIGH,CRITICAL`) |
| `failOnFindings` | boolean | `true` | Fail the job on Trivy findings |
| `timeoutInMinutes` | number | `20` | Job timeout |

### `templates/jobs/terraform-apply.yml`

Deployment job that downloads the reviewed `tfplan-<env>` artifact, restores the lock file, re-initialises the backend and applies exactly that plan. A stale plan fails safely. Infrastructure rolls forward: revert the commit to undo.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | string | `Apply` | Job identifier |
| `environmentName` | string | **required** | Logical environment name (selects the tfplan-&lt;name&gt; artifact) |
| `environment` | string | **required** | Azure DevOps environment that carries the approvals and checks |
| `azureServiceConnection` | string | **required** | ARM service connection used for the apply (Contributor-level, scoped) |
| `backendServiceConnection` | string | `''` | ARM service connection for the state backend (defaults to azureServiceConnection) |
| `workingDirectory` | string | **required** | Terraform root module directory |
| `terraformVersion` | string | `1.16.5` | Terraform CLI version (must match the plan job) |
| `backendResourceGroup` | string | **required** | Resource group of the state storage account |
| `backendStorageAccount` | string | **required** | State storage account name |
| `backendContainer` | string | `tfstate` | Blob container holding the state files |
| `backendKey` | string | **required** | State blob name |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool |
| `timeoutInMinutes` | number | `60` | Job timeout |

### `templates/jobs/terraform-plan.yml`

Trivy IaC scan, `terraform init` (Entra ID backend auth), `fmt -check`, `validate`, `plan` with the Terraform Plan tab, a Markdown plan summary for approvers and the `tfplan-<env>` artifact (plan + lock file). Output: `<name>.plan.changesPresent`.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | string | `Plan` | Job identifier (referenced in output variable paths) |
| `environmentName` | string | **required** | Logical environment name (dev, test, prod...) |
| `azureServiceConnection` | string | **required** | ARM service connection used for the plan (least privilege - Reader) |
| `backendServiceConnection` | string | `''` | ARM service connection for the state backend (defaults to azureServiceConnection) |
| `workingDirectory` | string | **required** | Terraform root module directory |
| `terraformVersion` | string | `1.16.5` | Terraform CLI version |
| `backendResourceGroup` | string | **required** | Resource group of the state storage account |
| `backendStorageAccount` | string | **required** | State storage account name |
| `backendContainer` | string | `tfstate` | Blob container holding the state files |
| `backendKey` | string | **required** | State blob name |
| `varFile` | string | `''` | Optional tfvars file, relative to workingDirectory |
| `iacScan` | boolean | `true` | Run a Trivy misconfiguration scan on the module before planning |
| `pool` | object | `{"vmImage":"ubuntu-24.04"}` | Agent pool |
| `timeoutInMinutes` | number | `30` | Job timeout |

## Step templates

### `templates/steps/acr-push.yml`

`az acr login` through the WIF service connection, `docker push`, and export of the immutable digest as output variable `push.imageRef`.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `azureServiceConnection` | string | **required** | Azure Resource Manager service connection (Workload Identity Federation) with AcrPush on the registry |
| `acrName` | string | **required** | Azure Container Registry name (without .azurecr.io) |
| `imageRef` | string | **required** | Local image reference to push |
| `condition` | string | `succeeded()` | Step condition, e.g. to skip pushes for pull requests |

### `templates/steps/aks-rollback.yml`

Rollback used by `aks-deploy.yml`'s `on.failure` hook. Helm: no-op if Helm already rolled back, otherwise `helm rollback` (or uninstall after a failed first install). Kustomize: `kubectl rollout undo` per workload. Guarded: only acts when the live workload runs this run's digest.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `azureServiceConnection` | string | **required** | Azure Resource Manager service connection (Workload Identity Federation) |
| `resourceGroup` | string | **required** | Resource group of the AKS cluster |
| `clusterName` | string | **required** | AKS cluster name |
| `namespace` | string | **required** | Kubernetes namespace |
| `method` | string | **required** | Deployment method that produced the release (one of: `helm`, `kustomize`) |
| `imageRef` | string | **required** | Image reference (repository@sha256:digest) that this run attempted to deploy |
| `releaseName` | string | `''` | Helm release name (helm only) |
| `imageDigestKey` | string | `image.digest` | Chart value holding the image digest (helm only) |
| `rolloutResources` | object | `[]` | Workloads to undo (kustomize only) |

### `templates/steps/aks-script.yml`

Runs a bash script with AKS credentials obtained via `az aks get-credentials` + `kubelogin convert-kubeconfig -l azurecli` (Entra ID, no static kubeconfig). Building block for the deploy and rollback steps.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `azureServiceConnection` | string | **required** | Azure Resource Manager service connection (Workload Identity Federation) |
| `resourceGroup` | string | **required** | Resource group of the AKS cluster |
| `clusterName` | string | **required** | AKS cluster name |
| `script` | string | **required** | Bash script executed after cluster credentials are configured |
| `displayName` | string | `Run script on AKS` | Step display name |
| `stepName` | string | `''` | Optional step reference name (needed when the script sets output variables) |
| `condition` | string | `succeeded()` | Step condition |
| `env` | object | `{}` | Extra environment variables for the script |

### `templates/steps/coverage-gate.yml`

Sums `lines-covered` / `lines-valid` across Cobertura files and fails below the threshold.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `searchDirectory` | string | **required** | Directory searched recursively for Cobertura files |
| `fileName` | string | `coverage.cobertura.xml` | Cobertura file name to look for |
| `minimumLineCoverage` | number | `80` | Minimum line coverage in percent (0 disables the gate) |

### `templates/steps/docker-build.yml`

BuildKit build with OCI labels (`revision`, `source`, `created`, pipeline run link). Loads the image locally only.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `imageRef` | string | **required** | Full image reference to build, e.g. myacr.azurecr.io/shop-web:1234 |
| `dockerfile` | string | `Dockerfile` | Path to the Dockerfile |
| `buildContext` | string | `.` | Docker build context |
| `buildArgs` | object | `[]` | List of KEY=VALUE build arguments (never pass secrets here; use BuildKit secrets) |
| `target` | string | `''` | Optional multi-stage build target |

### `templates/steps/gitleaks-scan.yml`

Installs a checksum-verified gitleaks and scans history (`git`) or the working tree (`dir`). Findings are redacted; SARIF is published as an artifact.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `scanMode` | string | `git` | git scans the full commit history, dir scans only the working tree (one of: `git`, `dir`) |
| `sourcePath` | string | `$(Build.SourcesDirectory)` | Path to scan |
| `configPath` | string | `''` | Optional gitleaks config file (an in-repo .gitleaks.toml is picked up automatically) |
| `failOnFindings` | boolean | `true` | Fail the step when a secret is detected |
| `artifactName` | string | `security-gitleaks` | Pipeline artifact name for the SARIF report |
| `version` | string | `8.30.1` | gitleaks version |
| `sha256` | string | `551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb` | SHA-256 of the linux_x64 release archive for the chosen version |

### `templates/steps/helm-deploy.yml`

`helm upgrade --install --rollback-on-failure --wait=watcher` with the image set by digest (`image.repository` + `image.digest` by default). Extra values are rendered to a JSON values file. Writes a release summary to the run.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `azureServiceConnection` | string | **required** | Azure Resource Manager service connection (Workload Identity Federation) |
| `resourceGroup` | string | **required** | Resource group of the AKS cluster |
| `clusterName` | string | **required** | AKS cluster name |
| `namespace` | string | **required** | Target Kubernetes namespace (must already exist and be RBAC-scoped to the pipeline identity) |
| `releaseName` | string | **required** | Helm release name |
| `chartPath` | string | **required** | Path to the chart in the application repository |
| `imageRef` | string | **required** | Image reference in repository@sha256:digest form |
| `valuesFiles` | object | `[]` | Ordered list of values files |
| `setValues` | object | `{}` | Mapping of extra values, rendered to a JSON values file (never put secrets here) |
| `imageRepositoryKey` | string | `image.repository` | Chart value that receives the image repository |
| `imageDigestKey` | string | `image.digest` | Chart value that receives the image digest |
| `timeout` | string | `10m` | Helm wait timeout (Go duration) |

### `templates/steps/install-kube-tools.yml`

Pinned `KubectlInstaller@0`, `KubeloginInstaller@0` and `HelmInstaller@1`.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `kubectlVersion` | string | `1.36.4` | kubectl version (keep within one minor version of the cluster) |
| `kubeloginVersion` | string | `0.2.20` | kubelogin version (required for Entra ID enabled AKS clusters) |
| `helmVersion` | string | `v4.3.0` | Helm version |
| `installHelm` | boolean | `true` | Install Helm (not needed for Kustomize deployments) |

### `templates/steps/install-tool.yml`

Generic installer for single-binary tools: downloads, verifies SHA-256, extracts into the agent tool cache and prepends it to `PATH`. Changing a tool version always requires changing its digest.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `name` | string | **required** | Tool name, used for the tool-cache folder and log output |
| `version` | string | **required** | Tool version (informational and part of the cache path) |
| `url` | string | **required** | Download URL of the release asset |
| `sha256` | string | **required** | Expected SHA-256 digest of the downloaded asset |
| `archive` | string | `tar.gz` | Asset packaging (one of: `tar.gz`, `none`) |
| `binary` | string | **required** | Executable name inside the archive (or target name when archive is none) |

### `templates/steps/kustomize-deploy.yml`

Wraps the overlay in a generated kustomization that pins the image by digest, applies it server-side and waits for each listed workload.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `azureServiceConnection` | string | **required** | Azure Resource Manager service connection (Workload Identity Federation) |
| `resourceGroup` | string | **required** | Resource group of the AKS cluster |
| `clusterName` | string | **required** | AKS cluster name |
| `namespace` | string | **required** | Target Kubernetes namespace |
| `overlayPath` | string | **required** | Path to the Kustomize overlay for this environment |
| `imageName` | string | **required** | Image name as written in the manifests (the value that gets replaced) |
| `imageRef` | string | **required** | Image reference in repository@sha256:digest form |
| `rolloutResources` | object | `[]` | Workloads to wait for, e.g. [deployment/web, statefulset/worker] |
| `timeout` | string | `10m` | Rollout timeout (Go duration) |

### `templates/steps/smoke-test.yml`

`curl` with retries against an HTTPS endpoint; a failure fails the deployment job and triggers the rollback hook.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `url` | string | **required** | HTTPS endpoint that must return a 2xx status |
| `attempts` | number | `10` | Number of attempts before the test fails |
| `delaySeconds` | number | `6` | Delay between attempts |

### `templates/steps/syft-sbom.yml`

SBOM in SPDX JSON and CycloneDX JSON for a directory (`dir:`) or image (`docker:`), published as an artifact.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `source` | string | **required** | syft source with scheme, e.g. dir:$(Build.SourcesDirectory) or docker:myacr.azurecr.io/app:1.2.3 |
| `artifactName` | string | `sbom` | Pipeline artifact name for the SBOM files |
| `version` | string | `1.54.1` | syft version |
| `sha256` | string | `c069905b391cc4c20a5ba65ad5c10be2a7ba074f8ea6ad203e24d14e303dad47` | SHA-256 of the linux_amd64 release archive for the chosen version |

### `templates/steps/terraform-init.yml`

`TerraformInstaller@1` plus `TerraformTask@5 init` with `backendAzureRmUseEntraIdForAuthentication` and `-lockfile=readonly` (commit `.terraform.lock.hcl`).

| Parameter | Type | Default | Description |
|---|---|---|---|
| `workingDirectory` | string | **required** | Terraform root module directory |
| `terraformVersion` | string | `1.16.5` | Terraform CLI version |
| `backendServiceConnection` | string | **required** | Service connection used to access the state storage account |
| `backendResourceGroup` | string | **required** | Resource group of the state storage account |
| `backendStorageAccount` | string | **required** | State storage account name |
| `backendContainer` | string | **required** | Blob container holding the state files |
| `backendKey` | string | **required** | State blob name, e.g. shop/dev.tfstate |

### `templates/steps/terraform-plan-summary.yml`

Turns a binary plan into a Markdown run summary (add / change / replace / destroy counts, list of destructive changes, collapsible full plan) and raises a warning on destructive plans.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `workingDirectory` | string | **required** | Terraform root module directory (already initialised) |
| `planFile` | string | **required** | Path to the binary plan file |
| `environmentName` | string | **required** | Environment name shown in the summary title |
| `maxPlanLines` | number | `400` | Truncate the embedded plain-text plan after this many lines |

### `templates/steps/trivy-scan.yml`

Installs a checksum-verified Trivy and scans an image, a filesystem or IaC config. Produces SARIF first, then gates on the chosen severities.

| Parameter | Type | Default | Description |
|---|---|---|---|
| `scanType` | string | **required** | Trivy scan target type (one of: `image`, `fs`, `config`) |
| `target` | string | **required** | Image reference or directory to scan |
| `severity` | string | `HIGH,CRITICAL` | Severities that fail the gate (one of: `CRITICAL`, `HIGH,CRITICAL`, `MEDIUM,HIGH,CRITICAL`) |
| `ignoreUnfixed` | boolean | `true` | Ignore vulnerabilities without an available fix (image and fs only) |
| `failOnFindings` | boolean | `true` | Fail the step when findings at or above the severity are present |
| `artifactName` | string | `security-trivy` | Pipeline artifact name for the SARIF report |
| `version` | string | `0.75.0` | Trivy version |
| `sha256` | string | `c6e65abddb348e25f10549df887045629cf28cc72453cd1c63acb717316b3f3f` | SHA-256 of the Linux-64bit release archive for the chosen version |


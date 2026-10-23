# Versioning and release process

Consumers reference the library through a repository resource pinned to an
immutable tag:

```yaml
resources:
  repositories:
    - repository: templates
      type: github                     # or: git (Azure Repos)
      name: rsk071216-stack/azure-devops-pipeline-templates
      ref: refs/tags/v1.0.0
      endpoint: github-platform-templates
```

Branches (`refs/heads/main`) are never used by production pipelines: a merge to
the library would otherwise change hundreds of pipelines instantly and
untested.

## What counts as a breaking change

Templates are an API. Their **parameters, defaults, outputs, stage/job names and
enforced policies** are the contract.

| Change | Version bump |
|---|---|
| Bug fix, tool patch upgrade with same behaviour, documentation | PATCH |
| New template, new optional parameter, new output variable, new opt-in feature | MINOR |
| Removed or renamed parameter, changed default, renamed stage/job/output, new mandatory policy rule, tool upgrade that changes gate results | MAJOR |

A new governance rule is always MAJOR even if "it only blocks bad things" - it
can break a pipeline that was compliant yesterday.

## Release steps

1. Merge changes to `main` with `CHANGELOG.md` entries under `[Unreleased]`.
2. Validate from a sandbox Azure DevOps project with `ref: refs/heads/main`
   (both example pipelines and the policy-violation example).
3. Create a release PR that:
   - moves `[Unreleased]` entries to `## [X.Y.Z] - YYYY-MM-DD`;
   - bumps the run tag in `templates/stages/security-baseline.yml`
     (`template-library-vX.Y.Z`);
   - bumps `ref: refs/tags/vX.Y.Z` in `examples/`;
   - adds `refs/tags/vX.Y.Z` to `required_template.allowed_refs` in
     `platform/azure-devops-governance`.

   CI (`scripts/lint-templates.sh`) fails if any of these disagree.
4. After merge, tag and push:

   ```bash
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin vX.Y.Z
   ```

   `.github/workflows/release.yml` verifies the tag against the CHANGELOG and
   publishes the GitHub release with the notes and a ready-to-paste resource
   block.
5. Apply `platform/azure-devops-governance` so the Required template checks
   accept the new tag.

## Support window and deprecation

- The latest MAJOR is fully supported; the previous MAJOR receives security
  fixes for 90 days after a new MAJOR is released.
- To retire a version, remove its tag from `allowed_refs`. Pipelines still on it
  keep building but can no longer reach protected environments or service
  connections - a hard, visible signal instead of a wiki page nobody reads.
- Tags are never moved or deleted. A bad release is fixed by a new PATCH.

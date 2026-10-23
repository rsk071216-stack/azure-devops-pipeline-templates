# ADR 0004 - Static validation: contract lint for templates, JSON schema only for root pipelines

- Status: Accepted
- Date: 2026-10-23

## Context

Azure Pipelines YAML is only fully validated by an Azure DevOps organisation:
template expressions (`${{ if }}`, `${{ each }}`), parameter types and template
references are resolved server-side. This repository's CI runs on GitHub
Actions without an Azure DevOps organisation, yet it must catch real mistakes.

Microsoft publishes the JSON schema used by the Azure Pipelines VS Code
extension (`service-schema.json`). We evaluated it against both kinds of files:

| File type | Result |
|---|---|
| Root pipelines in `examples/` (`trigger`, `resources`, `extends`) | Validates correctly; a deliberately broken fixture is rejected |
| Templates in `templates/` | Not meaningful: conditional keys such as `${{ if eq(...) }}:` and `${{ each ... }}:` are not representable in the schema, and template files are fragments (`parameters` + `steps`/`jobs`/`stages`) rather than pipelines |

## Decision

1. **Root pipelines** (`examples/*/azure-pipelines.yml`) are validated against
   `service-schema.json` pinned to an immutable commit of
   `microsoft/azure-pipelines-vscode`, using `check-jsonschema`. A negative
   fixture (`tests/schema/invalid-extends.yml`) must fail validation, proving
   the check is effective rather than silently permissive. The schema uses
   regex escapes (for example `\:`) that are invalid in unicode-mode ECMA
   regular expressions, so validation runs with `--regex-variant nonunicode`;
   with the default variant `check-jsonschema` rejects the schema itself.
2. **Templates** are validated by `scripts/lint-templates.sh`, which enforces
   the library contract: YAML parses without duplicate keys, every parameter
   declares `name`, `type` and `displayName`, every task is pinned to a major
   version, no floating references, every parameter is documented in
   `docs/catalogue.md` (and nothing undocumented is listed), and the release
   version is consistent across CHANGELOG, run tags, examples and the Required
   template allow-list.
3. `yamllint` (strict) and `actionlint` cover formatting and the GitHub
   workflows; `terraform validate` covers the governance-as-code module.

## Consequences

- CI catches structural, documentation and versioning mistakes in seconds.
- Expression logic (e.g. the policy rewrites in `secure-pipeline.yml`) is not
  executed by CI. It is verified in a sandbox Azure DevOps project before each
  release ([release-process.md](../release-process.md), step 2). A future
  improvement is a scheduled pipeline in that project that calls the
  *Runs - Run Pipeline* REST API with `previewRun: true` to compile every
  example and the negative policy example against the release candidate.
- The schema is pinned; Dependabot does not track it, so it is bumped manually
  when new tasks or keywords are needed.

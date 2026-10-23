# ADR 0001 - An extends template plus the Required template check is the governance boundary

- Status: Accepted
- Date: 2026-10-23

## Context

The organisation runs dozens of repositories with copy-pasted pipeline YAML.
Security scanning is inconsistent, some pipelines run arbitrary inline scripts
with production credentials, and nobody can say with confidence which pipelines
are allowed to deploy to production.

Options considered:

1. **Shared step/job templates (`template:` includes)** - easy to adopt, but
   opt-in: a pipeline can simply not include them.
2. **Pipeline decorators** - inject steps into every job organisation-wide, but
   they are invisible to pipeline authors, hard to test, require an extension
   and cannot reject a pipeline.
3. **`extends` template enforced by the Required template check** - the
   pipeline's structure is owned by the platform template, and protected
   resources refuse runs that do not use it.

## Decision

Use option 3. `templates/governance/secure-pipeline.yml` wraps every pipeline,
injects a mandatory security stage, rewrites dependencies and conditions so it
cannot be bypassed, and rejects forbidden constructs at compile time.
Environments and service connections carry a Required template check (managed
by Terraform) that accepts only this template at supported tags.

## Consequences

- Policy violations fail at compile time with an explicit message - no agent
  minutes are spent and nothing partially deploys.
- Consumer pipelines become declarative (a list of library stages).
- Teams lose the ability to write inline scripts in governed pipelines; the
  platform team must offer templates for legitimate needs. This is intended
  friction and is managed through the template backlog.
- Enforcement is only as strong as the checks: the Terraform configuration that
  owns them is part of this repository and reviewed like code.

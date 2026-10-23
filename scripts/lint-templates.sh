#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# lint-templates.sh - structural checks for the template library.
#
# Azure Pipelines template expressions (${{ }}) cannot be evaluated outside an
# Azure DevOps organisation, so this script enforces the library's contract
# statically:
#   1. every YAML file parses (duplicate keys are errors)
#   2. every template parameter declares name, type and displayName
#   3. every task reference pins a major version (Task@N)
#   4. no floating references (ubuntu-latest, :latest images, @latest)
#   5. every parameter is documented in docs/catalogue.md and every documented
#      parameter still exists (no stale docs)
#   6. the library version is consistent across CHANGELOG, run tags, examples
#      and the Required template allow-list
#
# Usage: scripts/lint-templates.sh            (requires mikefarah/yq v4)
#        YQ=/path/to/yq scripts/lint-templates.sh
# -----------------------------------------------------------------------------
set -euo pipefail

YQ="${YQ:-yq}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOGUE="docs/catalogue.md"
cd "${ROOT}"

errors=0
fail() {
  echo "::error file=${1}::${2}"
  errors=$((errors + 1))
}
section_start=0
section() {
  section_start=${errors}
  printf '\n== %s\n' "$1"
}
report() {
  if (( errors == section_start )); then echo "ok"; else echo "$((errors - section_start)) problem(s)"; fi
}

mapfile -t templates < <(find templates -type f -name '*.yml' | sort)
mapfile -t all_yaml < <(find templates examples .github -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)

# 1. YAML parses ---------------------------------------------------------------
section "YAML syntax (${#all_yaml[@]} files)"
for f in "${all_yaml[@]}"; do
  if ! "${YQ}" eval 'true' "${f}" > /dev/null 2>&1; then
    fail "${f}" "invalid YAML: $("${YQ}" eval 'true' "${f}" 2>&1 | head -n 1)"
  fi
done
report

# 2. Strongly typed parameters -------------------------------------------------
section "Parameter typing (${#templates[@]} templates)"
valid_types='^(string|number|boolean|object|step|stepList|job|jobList|deployment|deploymentList|stage|stageList)$'
for f in "${templates[@]}"; do
  count="$("${YQ}" '.parameters | length' "${f}")"
  if [[ "${count}" == "0" ]]; then
    fail "${f}" "template declares no parameters block"
    continue
  fi
  while IFS=$'\t' read -r name type display; do
    [[ -n "${name}" && "${name}" != "null" ]] || fail "${f}" "parameter without a name"
    [[ "${type}" =~ ${valid_types} ]] || fail "${f}" "parameter '${name}' has missing/invalid type '${type}'"
    [[ -n "${display}" && "${display}" != "null" ]] || fail "${f}" "parameter '${name}' has no displayName"
  done < <("${YQ}" -r '.parameters[] | [.name, .type, .displayName] | @tsv' "${f}")
done
report

# 3. Task major versions -------------------------------------------------------
section "Task version pinning"
for f in "${templates[@]}" examples/*/*.yml; do
  while read -r task; do
    [[ -z "${task}" ]] && continue
    [[ "${task}" =~ ^[A-Za-z0-9_.-]+@[0-9]+$ ]] || fail "${f}" "task '${task}' is not pinned to a major version (Name@N)"
  done < <("${YQ}" -r '.. | select(tag == "!!map") | select(has("task")) | .task' "${f}")
done
report

# 4. Floating references -------------------------------------------------------
section "Floating references"
while IFS= read -r hit; do
  fail "${hit%%:*}" "floating reference: ${hit#*:}"
done < <(grep -rnE 'ubuntu-latest|windows-latest|:latest\b|@latest\b' templates examples || true)
report

# 5. Catalogue coverage --------------------------------------------------------
section "Catalogue coverage (docs/catalogue.md)"
for f in "${templates[@]}"; do
  section_text="$(awk -v h="### \`${f}\`" '
    $0 == h { inside = 1; next }
    inside && /^##+ / { exit }
    inside { print }' "${CATALOGUE}")"
  if [[ -z "${section_text}" ]]; then
    fail "${CATALOGUE}" "missing section '### \`${f}\`'"
    continue
  fi
  mapfile -t params < <("${YQ}" -r '.parameters[].name' "${f}")
  for p in "${params[@]}"; do
    grep -qF "| \`${p}\` |" <<< "${section_text}" || fail "${CATALOGUE}" "${f}: parameter '${p}' is not documented"
  done
  # Backticks below are literal Markdown, not command substitution.
  # shellcheck disable=SC2016
  while read -r documented; do
    printf '%s\n' "${params[@]}" | grep -qxF "${documented}" || fail "${CATALOGUE}" "${f}: documents unknown parameter '${documented}'"
  done < <(grep -oE '^\| `[A-Za-z0-9_]+` \|' <<< "${section_text}" | sed -E 's/^\| `([^`]+)` \|/\1/')
done
report

# 6. Version consistency -------------------------------------------------------
section "Version consistency"
version="$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' CHANGELOG.md | head -n 1 | tr -d '#[] ')"
if [[ -z "${version}" ]]; then
  fail CHANGELOG.md "no released version heading (## [x.y.z]) found"
else
  echo "library version from CHANGELOG: ${version}"
  grep -q "template-library-v${version}\$" templates/stages/security-baseline.yml \
    || fail templates/stages/security-baseline.yml "run tag does not match CHANGELOG version ${version}"
  for ex in examples/*/azure-pipelines.yml; do
    grep -q "ref: refs/tags/v${version}\$" "${ex}" || fail "${ex}" "does not pin refs/tags/v${version}"
  done
  grep -q "\"refs/tags/v${version}\"" platform/azure-devops-governance/variables.tf \
    || fail platform/azure-devops-governance/variables.tf "Required template allow-list does not contain refs/tags/v${version}"
fi
report

echo
if (( errors > 0 )); then
  echo "lint-templates: ${errors} problem(s) found"
  exit 1
fi
echo "lint-templates: all checks passed"

#!/usr/bin/env bash
# Lint Helm charts by rendering them, then validate the rendered manifests.
#
#   helm-lint.sh --all          every chart in the repo
#   helm-lint.sh <base-ref>     charts with files changed since <base-ref>
#   helm-lint.sh <chart-dir>... the given charts
#
# Per chart: helm dependency update, helm lint, helm template | kubeconform.
# Charts render with their values.yaml into a namespace named after the chart
# directory, as the Applications in apps-root-config/applications do.
# apps-root-config/applications itself renders once per group values file.
# kubeconform is skipped with a warning when it is not installed.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

ROOT_APPS=apps-root-config/applications
KUBECONFORM_ARGS=(-summary -ignore-missing-schemas)

all_charts() {
  git ls-files '*Chart.yaml' | grep -v '^\.disabled/' | xargs -n1 dirname
}

# Nearest directory at or above the file's directory holding a Chart.yaml.
chart_of() {
  local dir
  dir=$(dirname "$1")
  while [ "$dir" != "." ]; do
    if [ -f "$dir/Chart.yaml" ]; then
      echo "$dir"
      return
    fi
    dir=$(dirname "$dir")
  done
}

changed_charts() {
  local files
  files=$(git diff --name-only "$1"...HEAD | grep -v '^\.disabled/')
  # A change to this check itself re-checks everything.
  if echo "$files" | grep -qxE '\.github/(scripts/helm-lint\.sh|workflows/lint\.yaml)'; then
    all_charts
    return
  fi
  echo "$files" | while read -r file; do
    [ -n "$file" ] || continue
    chart_of "$file"
  done
}

case "${1:-}" in
  "")
    echo "usage: $0 --all | <base-ref> | <chart-dir>..." >&2
    exit 2
    ;;
  --all) charts=$(all_charts) ;;
  *)
    if [ -f "$1/Chart.yaml" ]; then
      charts=$(printf '%s\n' "$@")
    else
      charts=$(changed_charts "$1")
    fi
    ;;
esac
charts=$(echo "$charts" | sed '/^$/d' | sort -u)

if [ -z "$charts" ]; then
  echo "No charts changed."
  exit 0
fi

if command -v kubeconform >/dev/null; then
  validate() { kubeconform "${KUBECONFORM_ARGS[@]}"; }
else
  echo "::warning::kubeconform not found, skipping schema validation"
  validate() { cat >/dev/null; }
fi

# render <chart> <release/namespace> [helm args...]
render() {
  local chart=$1 name=$2
  shift 2
  helm lint --quiet "$chart" --namespace "$name" "$@" &&
    helm template "$name" "$chart" --namespace "$name" "$@" | validate
}

failed=()
for chart in $charts; do
  echo "::group::$chart"
  ok=true
  if grep -q '^dependencies:' "$chart/Chart.yaml"; then
    helm dependency update "$chart" >/dev/null || ok=false
  fi
  if $ok && [ "$chart" = "$ROOT_APPS" ]; then
    for group in "$chart"/*.yaml; do
      case "$(basename "$group")" in Chart.yaml | values.yaml) continue ;; esac
      echo "--- values: $group"
      render "$chart" "$(basename "$group" .yaml)" -f "$group" || ok=false
    done
  elif $ok; then
    render "$chart" "$(basename "$chart")" || ok=false
  fi
  echo "::endgroup::"
  if ! $ok; then
    echo "::error::$chart failed"
    failed+=("$chart")
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  printf 'Failed charts:\n'
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
echo "All $(echo "$charts" | wc -l | tr -d ' ') charts passed."

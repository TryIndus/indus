#!/usr/bin/env bash
set -euo pipefail

version="v3.1.0"
expected_sha256="3d4973d5c4a0cf3d8395450e0f27aa41e24333cef56a1117b6e66d3396ff1b66"
environment="${1:-}"
mode="${2:-}"

[[ "$environment" =~ ^(development|staging|production)$ ]] || {
  echo "Usage: $0 ENVIRONMENT [--apply]" >&2
  exit 2
}

if [[ "$mode" != "--apply" ]]; then
  echo "Dry run: would install Argo CD $version and apply the $environment root application."
  echo "Required context: indus-$environment. No cluster or kubeconfig state changed."
  exit 0
fi

: "${KUBECONFIG:?Set KUBECONFIG to an explicit environment-specific file.}"
for command in curl kubectl shasum; do command -v "$command" >/dev/null 2>&1 || exit 1; done

context="$(kubectl config current-context)"
[[ "$context" == *"indus-${environment}"* ]] || {
  echo "Refusing context '$context'; expected indus-$environment." >&2
  exit 2
}

manifest="$(mktemp "${TMPDIR:-/tmp}/argocd-install.XXXXXX.yaml")"
trap 'rm -f "$manifest"' EXIT
curl -fsSLo "$manifest" "https://raw.githubusercontent.com/argoproj/argo-cd/${version}/manifests/install.yaml"
actual_sha256="$(shasum -a 256 "$manifest" | awk '{print $1}')"
[[ "$actual_sha256" == "$expected_sha256" ]] || { echo "Argo CD manifest checksum mismatch." >&2; exit 1; }

kubectl apply -f infra/gitops/bootstrap/namespaces.yaml
kubectl apply --server-side --field-manager=indus-bootstrap -n argocd -f "$manifest"
kubectl rollout status deployment/argocd-server -n argocd --timeout=10m
kubectl apply -f "infra/gitops/bootstrap/${environment}.yaml"

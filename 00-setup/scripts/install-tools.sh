#!/usr/bin/env bash
# Installe oc, kubectl, helm, tkn et argocd (Linux amd64) dans ~/.local/bin
set -euo pipefail
BIN="${BIN:-$HOME/.local/bin}"
OC_CHANNEL="${OC_CHANNEL:-stable-4.17}"        # canal mirror.openshift.com
mkdir -p "$BIN"
cd "$(mktemp -d)"

install_oc() {
  echo "▶ oc + kubectl ($OC_CHANNEL)"
  curl -fsSL "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OC_CHANNEL}/openshift-client-linux.tar.gz" -o oc.tgz
  tar xzf oc.tgz oc kubectl
  install -m 0755 oc kubectl "$BIN/"
}

install_helm() {
  echo "▶ helm"
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | USE_SUDO=false HELM_INSTALL_DIR="$BIN" bash
}

install_tkn() {
  echo "▶ tkn (Tekton CLI)"
  v=$(curl -fsSL https://api.github.com/repos/tektoncd/cli/releases/latest | grep -m1 '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
  curl -fsSL "https://github.com/tektoncd/cli/releases/download/v${v}/tkn_${v}_Linux_x86_64.tar.gz" | tar xz tkn
  install -m 0755 tkn "$BIN/"
}

install_argocd() {
  echo "▶ argocd CLI"
  curl -fsSL https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 -o argocd
  install -m 0755 argocd "$BIN/"
}

for f in ${@:-oc helm tkn argocd}; do "install_$f"; done
echo "✅ Installé dans $BIN — ajoutez-le au PATH : export PATH=\$PATH:$BIN"
echo "ℹ️  OpenShift Local (crc) se télécharge depuis https://console.redhat.com/openshift/create/local (pull secret requis)."

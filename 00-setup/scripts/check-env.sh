#!/usr/bin/env bash
# Vérifie que l'environnement de formation est prêt
ok=0
check() { # description, commande
  if eval "$2" >/dev/null 2>&1; then echo "✅ $1"; else echo "❌ $1"; ok=1; fi
}
warn() { # description, commande (non bloquant)
  if eval "$2" >/dev/null 2>&1; then echo "✅ $1"; else echo "⚠️  $1 (optionnel)"; fi
}
check "oc installé"                      "oc version --client"
check "connecté au cluster"              "oc whoami"
check "API accessible"                   "oc get --raw /readyz"
warn  "droits cluster-admin (🔑)"        "oc auth can-i '*' '*' --all-namespaces"
warn  "tous les Cluster Operators Available" "[ -z \"\$(oc get co --no-headers | awk '\$3!=\"True\"')\" ]"
warn  "registre interne"                 "oc get route default-route -n openshift-image-registry || oc get svc image-registry -n openshift-image-registry"
warn  "tkn installé"                     "tkn version --component client"
warn  "helm installé"                    "helm version"
warn  "argocd installé"                  "argocd version --client"
exit $ok

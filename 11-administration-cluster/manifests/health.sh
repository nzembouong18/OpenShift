#!/usr/bin/env bash
# Bilan de santé d'un cluster OpenShift — code retour ≠ 0 si un contrôle échoue
rc=0
fail() { echo "❌ $1"; rc=1; }
ok()   { echo "✅ $1"; }

bad_co=$(oc get co --no-headers | awk '$3!="True" || $5=="True"{print $1}')
[ -z "$bad_co" ] && ok "Cluster Operators Available et non Degraded" || fail "Cluster Operators en défaut : $bad_co"

bad_nodes=$(oc get nodes --no-headers | awk '$2!="Ready"{print $1}')
[ -z "$bad_nodes" ] && ok "Tous les nœuds Ready" || fail "Nœuds non Ready : $bad_nodes"

bad_mcp=$(oc get mcp --no-headers | awk '$3!="True" || $5>0{print $1}')
[ -z "$bad_mcp" ] && ok "MachineConfigPools à jour" || fail "MCP en cours/dégradés : $bad_mcp"

pending_csr=$(oc get csr --no-headers 2>/dev/null | grep -c Pending)
[ "$pending_csr" -eq 0 ] && ok "Aucune CSR en attente" || fail "$pending_csr CSR en attente"

crit=$(oc -n openshift-monitoring exec -c alertmanager alertmanager-main-0 -- amtool --alertmanager.url=http://localhost:9093 alert query severity=critical -o simple 2>/dev/null | grep -vc '^Alertname' || true)
[ "${crit:-0}" -eq 0 ] && ok "Aucune alerte critique" || fail "${crit} alerte(s) critique(s)"
exit $rc

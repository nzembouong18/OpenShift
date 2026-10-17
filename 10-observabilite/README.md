# Module 10 — Observabilité : métriques, alertes, logs, traces, diagnostic

⏱ 4 h · 🟡🔴

## Objectifs
- Exploiter la pile de **monitoring** intégrée (Prometheus, Alertmanager, Thanos Querier)
- Activer le **monitoring des projets utilisateurs**, créer ServiceMonitors, alertes, dashboards
- Comprendre **Logging** (Vector + Loki), **Tracing** (Tempo/OTel) et le **Network Observability**
- Diagnostiquer : `events`, `must-gather`, `inspect`, `debug`, `node-logs`

## 1. Cours

### 1.1 Les trois piliers + événements
| Pilier | Question | Outils OpenShift |
|---|---|---|
| **Métriques** | Quel est le comportement dans le temps ? | Prometheus, Alertmanager, console *Observe* |
| **Logs** | Que s'est-il passé ? | `oc logs`, **Logging 6** (Vector → Loki / Elasticsearch / SIEM) |
| **Traces** | Où le temps est-il passé dans la chaîne d'appels ? | **Tempo** + **OpenTelemetry** (Distributed Tracing) |
| **Événements / audit** | Qui a fait quoi ? | `oc get events`, audit API |
Compléments : **Network Observability** (flux eBPF), **Cost Management**, **Power monitoring**.

### 1.2 Monitoring du cluster (`openshift-monitoring`)
Installé par défaut et **géré par le Cluster Monitoring Operator** : Prometheus (x2, HA), Alertmanager (x3), kube-state-metrics, node-exporter, Thanos Querier (point d'entrée unique pour les requêtes), prometheus-adapter / metrics-server (API de métriques pour HPA et `oc adm top`), Telemeter (optionnel).
Configuration : ConfigMap `cluster-monitoring-config` dans `openshift-monitoring`.
```yaml
apiVersion: v1
kind: ConfigMap
metadata: {name: cluster-monitoring-config, namespace: openshift-monitoring}
data:
  config.yaml: |
    enableUserWorkload: true
    prometheusK8s:
      retention: 15d
      volumeClaimTemplate:
        spec: {storageClassName: <sc>, resources: {requests: {storage: 100Gi}}}
    alertmanagerMain:
      volumeClaimTemplate:
        spec: {storageClassName: <sc>, resources: {requests: {storage: 10Gi}}}
```
⚠️ Sans PVC, les métriques sont **perdues** au redémarrage des Pods Prometheus. Les composants de monitoring peuvent être déplacés sur des **nœuds infra** (`nodeSelector`/`tolerations`).

### 1.3 Monitoring des projets utilisateurs (UWM)
`enableUserWorkload: true` démarre une seconde instance Prometheus (`openshift-user-workload-monitoring`) qui collecte vos applications. Configuration dédiée : ConfigMap `user-workload-monitoring-config` (`openshift-user-workload-monitoring`) : rétention, limites, `enforcedSampleLimit`.

Pour exposer les métriques d'une application :
1. L'app expose `/metrics` (format Prometheus, port nommé).
2. Un `Service` avec labels.
3. Un `ServiceMonitor` (ou `PodMonitor`) dans **le même projet**.
4. Les droits : rôle `monitoring-rules-edit` / `monitoring-edit` pour gérer règles et monitors ; `monitoring-rules-view` pour voir.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
spec:
  selector: {matchLabels: {app: vote-api}}
  endpoints: [{port: http, path: /metrics, interval: 30s}]
```

### 1.4 PromQL — les 8 requêtes à connaître
| Besoin | Requête |
|---|---|
| CPU des Pods d'un projet | `sum by (pod)(rate(container_cpu_usage_seconds_total{namespace="lab-obs",container!=""}[5m]))` |
| Mémoire | `sum by (pod)(container_memory_working_set_bytes{namespace="lab-obs",container!=""})` |
| Redémarrages | `increase(kube_pod_container_status_restarts_total{namespace="lab-obs"}[1h])` |
| Pods non prêts | `kube_pod_status_ready{condition="false"}` |
| Taux de requêtes | `sum(rate(http_requests_total[5m])) by (path)` |
| Taux d'erreurs | `sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m]))` |
| Latence p95 | `histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))` |
| Saturation PVC | `kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes` |
Méthodes : **RED** (Rate, Errors, Duration) pour les services, **USE** (Utilization, Saturation, Errors) pour les ressources, **Golden signals** de Google SRE.

### 1.5 Alertes
`PrometheusRule` (dans votre projet pour UWM) → Alertmanager → récepteurs (mail, Slack, PagerDuty, webhook). Configuration : Secret `alertmanager-main` (cluster) ou `alertmanager-user-workload` (UWM). Notions : `for` (durée avant déclenchement), `severity` (`info|warning|critical`), routes, inhibition, silences. Alerte **Watchdog** : toujours active (preuve que la chaîne d'alerte fonctionne – à router vers un dead man's switch).
Bonnes alertes : basées sur les **symptômes** (erreurs/latence vus par l'utilisateur) plus que sur les causes ; chaque alerte a un `runbook_url` et une action claire.

### 1.6 Dashboards
Console → Observe → Dashboards (dashboards Grafana intégrés en lecture seule : Kubernetes / Compute / Namespace, Node Exporter, etcd...). Dashboards personnalisés : ConfigMap étiquetée `console.openshift.io/dashboard: "true"` dans `openshift-config-managed` (🔑). Pour Grafana complet : **Grafana Operator** ou Perses / dashboards de la console (selon version) en s'appuyant sur le Thanos Querier.

### 1.7 Logging (Logging 6.x)
Architecture : **collecteur Vector** (DaemonSet, `ClusterLogForwarder` API `observability.openshift.io/v1`) → **Loki** (`LokiStack` via Loki Operator, stockage objet S3/ODF) + console *Observe → Logs* (plugin) ; ou sorties externes : Splunk, Elasticsearch, Kafka, syslog, CloudWatch.
Types d'entrées : `application`, `infrastructure`, `audit`.
Principes : **logs structurés JSON** sur stdout, pas de fichiers dans le conteneur, pas de secrets dans les logs, labels de projet/pod conservés, politiques de rétention (`LokiStack.spec.limits`).
Anciennes versions (≤ 5.x) : `ClusterLogging` + Elasticsearch/Kibana — en fin de vie ; planifier la migration.

### 1.8 Tracing
Operators **Red Hat build of OpenTelemetry** (collecteur, auto-instrumentation `Instrumentation` CR) et **Tempo** (stockage des traces). Pipeline : app (SDK OTel) → `OpenTelemetryCollector` → `TempoStack` → console / Jaeger UI. Propager `traceparent` ; échantillonnage (head/tail).

### 1.9 Diagnostic : pas à pas
| Étape | Commande |
|---|---|
| Vue d'ensemble | `oc status`, `oc get events --sort-by=.lastTimestamp`, `oc get pods -o wide` |
| Pourquoi un Pod ne démarre pas | `oc describe pod` (section **Events**), `oc get pod -o yaml` (`status.containerStatuses`) |
| Logs | `oc logs -f`, `-p` (précédent), `-c <conteneur>`, `--since=10m`, `oc logs -l app=x --all-containers` |
| Shell / réseau | `oc rsh`, `oc debug`, `oc port-forward`, `oc exec ... -- curl` |
| Ressources | `oc adm top pods/nodes`, `oc describe node` |
| Cluster | `oc get co`, `oc adm must-gather`, `oc adm inspect ns/<x>`, `oc adm node-logs <node> -u kubelet`, `oc adm release info` |
| Réseau | `oc get ep`, `oc get route -o wide`, `oc -n openshift-ingress logs deploy/router-default` |
**Must-gather** : collecte standard pour un ticket de support Red Hat : `oc adm must-gather --dest-dir=./mg` ; spécialisés : `-- /usr/bin/gather_audit_logs`, images ODF, Virtualization, Service Mesh.

### 1.10 Scénarios de pannes classiques
| Symptôme | Cause probable | Réflexe |
|---|---|---|
| `ImagePullBackOff` | image/registre/secret | `describe pod`, pull secret, ImageStream |
| `CrashLoopBackOff` | application ou probe | `logs -p`, `debug` |
| `Pending` | ressources/quota/PVC/taint/SCC | `describe pod`, `get events`, quota |
| `CreateContainerConfigError` | ConfigMap/Secret manquant | `describe pod` |
| `OOMKilled` | limite mémoire | `describe pod`, ajuster |
| Route `503` | aucun Endpoint prêt | `oc get ep`, probes |
| Route timeout | NetworkPolicy, mauvais port | NetPol, `targetPort` |
| `forbidden: unable to validate against any security context constraint` | SCC | module 07 |

## 2. 🎬 Démo (50 min)

```bash
# 1. UWM
oc apply -f manifests/01-cluster-monitoring-config.yaml         # 🔑
oc -n openshift-user-workload-monitoring get pods -w
# 2. Application instrumentée
oc new-project lab-obs
oc apply -f manifests/02-app-metrics.yaml
oc apply -f manifests/03-servicemonitor-rules.yaml
# Console → Observe → Metrics : http_requests_total
for i in $(seq 200); do curl -sk https://$(oc get route metrics-app -o jsonpath='{.spec.host}')/ >/dev/null; done
# 3. Alerte
oc scale deploy/metrics-app --replicas=0 ; # alerte MetricsAppDown après 1 min
# 4. Dashboard / API
TOKEN=$(oc whoami -t) ; HOST=$(oc get route thanos-querier -n openshift-monitoring -o jsonpath='{.spec.host}')
curl -sk -H "Authorization: Bearer $TOKEN" "https://$HOST/api/v1/query?query=up" | head -c 300
# 5. Diagnostic
oc apply -f manifests/04-broken-apps.yaml ; oc get pods ; oc describe pod -l app=broken-config
oc adm must-gather --dest-dir=/tmp/mg ; ls /tmp/mg
```

## 3. 🧪 Labos

> Projet : `lab-obs`

### Lab 10.1 ⭐ — Explorer la console Observe
Dans *Observe → Metrics*, tracez le CPU de votre projet. Dans *Dashboards*, ouvrez « Kubernetes / Compute Resources / Namespace (Pods) ». Dans *Alerting*, repérez l'alerte `Watchdog`.

<details><summary>Corrigé</summary>
Requête : `sum(rate(container_cpu_usage_seconds_total{namespace="lab-obs",container!=""}[5m])) by (pod)`. Watchdog est toujours *Firing* : normal.
</details>

### Lab 10.2 ⭐⭐ — Activer le monitoring utilisateur 🔑
Appliquez `01-cluster-monitoring-config.yaml`, vérifiez les Pods dans `openshift-user-workload-monitoring`.

<details><summary>Corrigé</summary>

```bash
oc -n openshift-user-workload-monitoring get pods     # prometheus-user-workload-0/1, thanos-ruler-user-workload-0/1, prometheus-operator
```
</details>

### Lab 10.3 ⭐⭐ — Instrumenter une application
Déployez `metrics-app` (02), créez le ServiceMonitor (03), vérifiez la cible `Up` dans *Observe → Targets* et la métrique `http_requests_total`.

<details><summary>Corrigé</summary>

```bash
oc get servicemonitor,prometheusrule
# console : Observe → Metrics → http_requests_total
```
Si la cible n'apparaît pas : labels du Service, nom du port, droits (`monitoring-edit`).
</details>

### Lab 10.4 ⭐⭐⭐ — Alerte utile
Écrivez une `PrometheusRule` : taux d'erreur 5xx > 5 % pendant 5 minutes (`severity: critical`) et application absente (`absent(up{job="metrics-app"})`). Déclenchez-la.

<details><summary>Corrigé</summary>
Voir `03-servicemonitor-rules.yaml`. Provoquer : `curl .../fail` en boucle ; `oc scale ... --replicas=0` pour `MetricsAppDown`.
</details>

### Lab 10.5 ⭐⭐⭐ — Notifications Alertmanager 🔑
Configurez un récepteur webhook (service de test dans le cluster) pour les alertes `critical`; vérifiez la réception.

<details><summary>Corrigé</summary>

```bash
oc -n openshift-monitoring get secret alertmanager-main --template='{{ index .data "alertmanager.yaml" }}' | base64 -d > am.yaml
# ajouter route + receiver webhook_configs: [{url: http://webhook.lab-obs.svc:8080}] puis :
oc -n openshift-monitoring create secret generic alertmanager-main --from-file=alertmanager.yaml=am.yaml --dry-run=client -o=yaml | oc -n openshift-monitoring replace secret --filename=-
```
Avec UWM, utilisez `AlertmanagerConfig` dans le projet si activé (`alertmanagerMain.enableUserAlertmanagerConfig: true`).
</details>

### Lab 10.6 ⭐⭐ — Diagnostiquer 5 pannes
Appliquez `04-broken-apps.yaml` : 4 Deployments cassés (`broken-image`, `broken-config`, `broken-memory`, `broken-pending`). Diagnostiquez chacun, corrigez, rédigez 1 ligne de cause racine.

<details><summary>Corrigé</summary>

| App | Cause | Correction |
|---|---|---|
| `broken-image` | tag inexistant → `ImagePullBackOff` | corriger l'image |
| `broken-config` | ConfigMap `absent-cm` référencée → `CreateContainerConfigError` | créer le ConfigMap |
| `broken-memory` | limite 8Mi → `OOMKilled` | augmenter la limite |
| `broken-pending` | requests CPU 100 → `Pending` (`Insufficient cpu`) | réduire les requests |
</details>

### Lab 10.7 ⭐⭐⭐ — Logging avec Loki 🔑
Installez Loki Operator + OpenShift Logging, créez un `LokiStack` (taille `1x.demo`) avec stockage objet et un `ClusterLogForwarder`. Retrouvez les logs de l'application dans *Observe → Logs*.

<details><summary>Corrigé</summary>
Voir `05-logging.yaml` (adapter secret S3, StorageClass, nom du SA). Requête LogQL : `{kubernetes_namespace_name="lab-obs"} |= "error"`. Sur CRC, ressources insuffisantes : lecture seule.
</details>

### Lab 10.8 ⭐⭐⭐⭐ — SLO et burn rate
Définissez un SLO de disponibilité à 99,5 % sur `metrics-app`. Écrivez des alertes multi-fenêtres (burn rate 14,4× sur 5 min/1 h, 6× sur 30 min/6 h) en recording rules.

<details><summary>Corrigé</summary>
Recording rule : `job:http_error_ratio:rate5m`. Alerte : `job:http_error_ratio:rate5m > (14.4 * 0.005) and job:http_error_ratio:rate1h > (14.4 * 0.005)`. Voir la méthode du *Google SRE Workbook*, chapitre « Alerting on SLOs ».
</details>

### Lab 10.9 ⭐⭐⭐⭐ — Collecte pour support 🔑
Générez un `must-gather` ciblé (réseau ou Operator), triez les fichiers utiles (`cluster-scoped-resources`, `namespaces/<x>/pods`, `events`), expliquez comment anonymiser avant envoi.

<details><summary>Corrigé</summary>

```bash
oc adm must-gather --dest-dir=/tmp/mg -- /usr/bin/gather
oc adm inspect ns/lab-obs --dest-dir=/tmp/inspect
tar czf mg.tgz /tmp/mg   # puis relire / retirer secrets ; les Secrets ne sont pas collectés par défaut
```
</details>

## 4. Quiz
1. Que faut-il activer pour surveiller vos applications ? → `enableUserWorkload: true`.
2. Quelle CR indique à Prometheus de scraper un Service ? → `ServiceMonitor`.
3. Pourquoi mettre un `for:` dans une alerte ? → éviter le bruit des pics courts.
4. Quel est le collecteur de logs de Logging 6 ? → Vector (`ClusterLogForwarder`).
5. À quoi sert `must-gather` ? → collecter l'état du cluster pour le support/diagnostic.

Nettoyage : `oc delete project lab-obs`

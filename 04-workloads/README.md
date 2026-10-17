# Module 04 — Workloads sur OpenShift

⏱ 3 h 30 · 🟡

## Objectifs
- Déployer et mettre à jour avec **Deployment** ; comprendre pourquoi **DeploymentConfig** est déprécié
- Concevoir des applications compatibles avec les contraintes OpenShift (UID arbitraire, non-root)
- Maîtriser probes, ressources, HPA, StatefulSet, Job/CronJob, PDB

## 1. Cours

### 1.1 Deployment vs DeploymentConfig
| | `Deployment` (Kubernetes) | `DeploymentConfig` (OpenShift) |
|---|---|---|
| Statut | **Recommandé** | **Déprécié** depuis OCP 4.14 (plus de nouvelles fonctionnalités) |
| Contrôleur | controller-manager | controller dédié |
| Mises à jour | RollingUpdate / Recreate | Rolling / Recreate / **custom**, hooks `pre/mid/post` |
| Triggers d'image | annotation `image.openshift.io/triggers` | `triggers.imageChange` natif |
| Pods | ReplicaSet | ReplicationController |
Pour migrer : traduire les hooks en Jobs/initContainers (ou Argo Rollouts), les triggers en annotation. L'existant continue de fonctionner mais **ne démarrez plus de projets avec DC**. Commande utile : `oc get dc -A`.

Déclencheur d'image sur un Deployment :
```bash
oc set triggers deploy/web --from-image=web:latest -c web
# équivaut à l'annotation image.openshift.io/triggers: [{"from":{"kind":"ImageStreamTag","name":"web:latest"},"fieldPath":"spec.template.spec.containers[?(@.name==\"web\")].image"}]
```

### 1.2 Contraintes de la SCC `restricted-v2` (aperçu, détail module 07)
Chaque Pod est admis par une **SecurityContextConstraints**. Par défaut :
- pas de root : l'UID est **assigné au hasard** dans la plage du projet (annotation `openshift.io/sa.scc.uid-range`), GID = 0 pour les fichiers
- `allowPrivilegeEscalation: false`, capacités `ALL` supprimées, seccomp `RuntimeDefault`
- pas de `hostPath`, `hostNetwork`, ports < 1024 impossibles à lier sans capacité

→ **Conséquences pour vos images** : écrire dans des répertoires `chgrp 0 / g=u`, écouter sur un port ≥ 1024, ne pas dépendre d'un UID fixe dans `/etc/passwd`, ne pas utiliser `USER root`.

### 1.3 Probes
| Probe | Question | Échec |
|---|---|---|
| `startupProbe` | l'application a-t-elle fini de démarrer ? | tue et redémarre |
| `readinessProbe` | peut-elle recevoir du trafic ? | retire de l'Endpoint (et du Router) |
| `livenessProbe` | est-elle en vie ? | redémarre le conteneur |
Pour la Route : un Pod `NotReady` est retiré du backend HAProxy. Utilisez `httpGet`, `tcpSocket`, `exec` ou `grpc`.

### 1.4 Ressources et QoS
`requests` guident le scheduling, `limits` plafonnent. Classes QoS : `Guaranteed` (requests = limits), `Burstable`, `BestEffort` (évincés en premier). Mémoire dépassée → `OOMKilled` ; CPU dépassé → throttling. OpenShift expose `oc adm top pods|nodes` (metrics API). Bonne pratique : requests réalistes, limite mémoire = ~1,25× request, limite CPU souvent omise.

### 1.5 Autoscaling
| Outil | Rôle |
|---|---|
| **HPA** | nombre de réplicas selon CPU/mémoire/métriques personnalisées (module 10) |
| **VPA** (Operator) | recommande/ajuste requests |
| **KEDA** (Custom Metrics Autoscaler) | scale sur événements (Kafka, files, Prometheus…), scale-to-zero |
| **Cluster Autoscaler / MachineAutoscaler** | ajoute/retire des nœuds (module 11) |
HPA nécessite des **requests CPU** définis. `oc autoscale deploy/web --min=2 --max=8 --cpu-percent=70`.

### 1.6 StatefulSet, DaemonSet, Job, CronJob
Comme sur Kubernetes (cf. formation K8s module 03). Spécificités OpenShift :
- StatefulSet : le PVC suit l'UID via `fsGroup` géré par la SCC (le `fsGroup` est affecté automatiquement).
- DaemonSet : ne peut cibler les nœuds master/infra qu'avec tolerations ET SCC adaptée (souvent `privileged` → à éviter).
- Job/CronJob : `oc create job --from=cronjob/x`, `ttlSecondsAfterFinished`.

### 1.7 Disponibilité : PDB, anti-affinité, topologie
- **PodDisruptionBudget** : `minAvailable`/`maxUnavailable`. Il **bloque `oc adm drain`** s'il ne peut être respecté (cf. module 11).
- `topologySpreadConstraints` sur `topology.kubernetes.io/zone` et `kubernetes.io/hostname`.
- `priorityClassName` : `system-cluster-critical` est réservé à la plateforme.

### 1.8 Placer des workloads : nœuds infra, labels, taints
Machines dédiées par rôle : `node-role.kubernetes.io/infra=""` (monitoring, router, registre), `...worker` pour les applications. Utilisation côté projet : annotation `openshift.io/node-selector` (🔑, force un `nodeSelector` pour tout un projet) :
```bash
oc annotate namespace lab-workloads openshift.io/node-selector='tier=app' --overwrite
```

### 1.9 Debugger
| Commande | Usage |
|---|---|
| `oc debug deploy/web` | copie du Pod en mode debug (entrypoint remplacé, utile pour CrashLoop) |
| `oc debug deploy/web --as-root` | idem en root (🔑 SCC `anyuid`) |
| `oc rsh pod/x` / `oc exec` | shell dans un conteneur |
| `oc logs -p pod/x` | logs du conteneur précédent |
| `oc debug node/x` | shell sur un nœud |
| `oc get events --sort-by=.lastTimestamp` | historique d'événements |
| `oc adm inspect` / `must-gather` | collecte pour support |

## 2. 🎬 Démo (40 min)

```bash
oc new-project lab-workloads
oc apply -f manifests/01-deployment.yaml
oc get deploy,rs,pods
oc set image deploy/web web=registry.access.redhat.com/ubi9/nginx-124:1-1                  # rolling update
oc rollout status deploy/web ; oc rollout history deploy/web ; oc rollout undo deploy/web
oc set triggers deploy/web --from-image=nginx-stream:latest -c web
# Contrainte SCC : image root
oc create deployment root --image=docker.io/library/nginx:1.27 ; oc get pods ; oc logs deploy/root
oc debug deploy/web ; oc rsh deploy/web id           # uid=1000710000 gid=0
# Probes et crash volontaire
oc apply -f manifests/02-crashloop.yaml ; oc get pods -w ; oc describe pod -l app=crash
# HPA
oc apply -f manifests/03-hpa-pdb.yaml ; oc get hpa -w
# Ancien monde : DeploymentConfig
oc apply -f manifests/05-deploymentconfig-legacy.yaml ; oc get dc,rc
```

## 3. 🧪 Labos

> Projet : `lab-workloads`

### Lab 4.1 ⭐ — Déployer et scaler
Déployez `manifests/01-deployment.yaml` (3 réplicas). Passez à 5 puis revenez à 2 avec `oc scale`. Supprimez un Pod.

<details><summary>Corrigé</summary>

```bash
oc new-project lab-workloads
oc apply -f manifests/01-deployment.yaml
oc scale deploy/web --replicas=5 ; oc scale deploy/web --replicas=2
oc delete pod $(oc get pods -l app=web -o name | head -1)
```
Le ReplicaSet recrée un Pod avec un nouveau nom et une nouvelle IP.
</details>

### Lab 4.2 ⭐ — Quel UID ?
Affichez l'UID du processus dans un Pod. Comparez avec l'annotation du projet.

<details><summary>Corrigé</summary>

```bash
oc rsh deploy/web id
oc get project lab-workloads -o jsonpath='{.metadata.annotations.openshift\.io/sa\.scc\.uid-range}{"\n"}'
oc get pod -l app=web -o jsonpath='{.items[0].metadata.annotations.openshift\.io/scc}{"\n"}'   # restricted-v2
```
</details>

### Lab 4.3 ⭐⭐ — Réparer une image root
Déployez `docker.io/library/nginx:1.27` : constatez l'échec. Remplacez par `nginxinc/nginx-unprivileged` (port 8080). Quelle autre option existe (à éviter) ?

<details><summary>Corrigé</summary>

```bash
oc create deployment nginx --image=docker.io/nginxinc/nginx-unprivileged:1.27
oc expose deployment nginx --port=8080
```
Option à éviter : `oc adm policy add-scc-to-user anyuid -z default` (🔑) — abaisse la sécurité du projet.
</details>

### Lab 4.4 ⭐⭐ — Rolling update maîtrisé et rollback
4 réplicas, `maxSurge: 1`, `maxUnavailable: 0`. Mise à jour vers une image inexistante : constatez que le service reste servi, puis `oc rollout undo`.

<details><summary>Corrigé</summary>

```bash
oc set image deploy/web web=registry.access.redhat.com/ubi9/nginx-124:inexistant
oc rollout status deploy/web --timeout=30s
oc rollout undo deploy/web
```
</details>

### Lab 4.5 ⭐⭐ — Probes
Appliquez `manifests/02-crashloop.yaml`. Diagnostiquez la `CrashLoopBackOff` avec `oc logs -p` et `oc describe`. Corrigez la liveness probe.

<details><summary>Corrigé</summary>
La liveness probe cible `/healthz` alors que l'application n'écoute que `/` → échec → redémarrages. Corriger le chemin ou ajouter une `startupProbe` si démarrage lent.
</details>

### Lab 4.6 ⭐⭐ — HPA 🔑 (ou Sandbox si metrics dispo)
Appliquez `manifests/03-hpa-pdb.yaml`, générez de la charge (`oc run load --image=registry.access.redhat.com/ubi9/ubi-minimal -- sh -c 'while true; do curl -s web:8080 >/dev/null; done'`), observez le scale-out.

<details><summary>Corrigé</summary>

```bash
oc get hpa web -w
oc adm top pods
oc delete pod load
```
Si la cible affiche `<unknown>` : requests CPU absentes ou métriques indisponibles.
</details>

### Lab 4.7 ⭐⭐⭐ — Migrer un DeploymentConfig vers un Deployment
Appliquez `manifests/05-deploymentconfig-legacy.yaml`, puis écrivez le Deployment équivalent (image trigger inclus). Quelle différence sur les hooks ?

<details><summary>Corrigé</summary>

```bash
oc get dc legacy -o yaml > /tmp/dc.yaml
# traduction : strategy.rollingParams → strategy.rollingUpdate ; triggers → annotation image.openshift.io/triggers ; hook pre → Job
oc create deployment legacy-new --image=... --dry-run=client -o yaml
```
Les hooks `pre/post` n'existent pas : utiliser un Job (Helm hook, Argo CD PreSync) ou un initContainer.
</details>

### Lab 4.8 ⭐⭐⭐ — Job, CronJob et StatefulSet
Créez un CronJob `backup` (toutes les 2 min, `concurrencyPolicy: Forbid`), un StatefulSet `db` (2 réplicas, PVC 1 Gi) et vérifiez la persistance après suppression d'un Pod.

<details><summary>Corrigé</summary>
Voir `manifests/04-statefulset-cronjob.yaml`.

```bash
oc exec db-0 -- sh -c 'echo ok > /data/test'
oc delete pod db-0 ; oc wait --for=condition=ready pod/db-0 ; oc exec db-0 -- cat /data/test
```
</details>

### Lab 4.9 ⭐⭐⭐⭐ — Projet dédié aux workloads sur nœuds ciblés 🔑
Étiquetez deux workers `tier=app`, imposez le `nodeSelector` par annotation de projet, vérifiez le placement, puis ajoutez un `topologySpreadConstraint`.

<details><summary>Corrigé</summary>

```bash
oc label node <w1> <w2> tier=app
oc annotate namespace lab-workloads openshift.io/node-selector='tier=app' --overwrite
oc rollout restart deploy/web ; oc get pods -o wide
```
Sur CRC (1 nœud), simulez uniquement l'annotation.
</details>

## 4. Quiz
1. Pourquoi privilégier Deployment à DeploymentConfig ? → DC déprécié, Deployment standard K8s, outillage GitOps/Helm.
2. Que provoque une liveness probe qui échoue ? → redémarrage du conteneur.
3. Quel UID reçoit un Pod sous `restricted-v2` ? → un UID arbitraire de la plage du projet, GID 0.
4. Qu'est-ce qui bloque `oc adm drain` ? → un PDB non satisfaisable, des Pods sans contrôleur, DaemonSets non ignorés.
5. Prérequis du HPA CPU ? → `requests.cpu` + metrics API disponible.

Nettoyage : `oc delete project lab-workloads`

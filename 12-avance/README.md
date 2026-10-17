# Module 12 — Avancé et écosystème : Serverless, Mesh, Virtualisation, Multi-cluster

⏱ 5 h · 🔴⚫ (expert)

> Ces sujets reposent sur des **Operators** (module 08). Les canaux et versions évoluent vite : vérifiez avec `make operators-info`. La plupart des labos exigent 🔑 et des ressources supérieures à CRC : prévoir un cluster formateur ou OKD/SNO 32 Go.

## Objectifs
- Déployer du **serverless** (Knative) et de l'autoscaling événementiel (KEDA)
- Sécuriser et observer le trafic avec un **service mesh**
- Exécuter des **machines virtuelles** aux côtés des conteneurs (OpenShift Virtualization)
- Gouverner une **flotte** de clusters (ACM, Hosted Control Planes, politiques)
- Concevoir une **architecture de référence** (HA, DR, multi-tenant, edge)

## 1. Cours

### 1.1 OpenShift Serverless (Knative)
Operator `serverless-operator` : `KnativeServing` (HTTP, scale-to-zero) et `KnativeEventing` (CloudEvents, Brokers, Triggers, Sources Kafka/Ping/API).
| Objet | Rôle |
|---|---|
| `Service` (`serving.knative.dev/v1`) | application + révisions + route + autoscaling en une ressource |
| `Revision` | version immuable (image + config) |
| `Route` (Knative) | répartition du trafic entre révisions (canary, blue/green) |
| `Broker` / `Trigger` | bus d’événements ; filtrage par attributs |
| `Function` (`kn func`) | fonctions en Go/Node/Python/Quarkus… |
Autoscaler KPA : concurrence cible (`autoscaling.knative.dev/target`), `min-scale`, `max-scale`, scale-to-zero après `scale-to-zero-pod-retention-period`. Cold start : minimiser l’image, `min-scale: 1` pour les chemins critiques.
Quand l’utiliser : charges irrégulières, traitement événementiel, APIs à faible trafic. Pas pour : tâches très longues, protocoles non HTTP/gRPC (utiliser KEDA).

### 1.2 KEDA — Custom Metrics Autoscaler
`ScaledObject` (Deployment) / `ScaledJob` (Jobs) avec des *scalers* : Kafka, RabbitMQ, Prometheus, cron, Azure/AWS queues… Capacité `minReplicaCount: 0`. Se base sur HPA en interne ; authentification via `TriggerAuthentication`.

### 1.3 Service Mesh
Deux générations :
| | Service Mesh 2 (Maistra/Istio 1.2x) | **Service Mesh 3** (Istio upstream, Sail Operator) |
|---|---|---|
| CR | `ServiceMeshControlPlane`, `ServiceMeshMemberRoll` | `Istio`, `IstioCNI` (+ labels d’injection par namespace) |
| Multi-tenant | dans le control plane | via revisions/`discoverySelectors` |
Apports : **mTLS** automatique (`PeerAuthentication`), autorisation fine (`AuthorizationPolicy`), traffic management (`VirtualService`, `DestinationRule`, `Gateway` / Gateway API), résilience (timeouts, retries, circuit breaking, outlier detection), observabilité (Kiali, Tempo, métriques).
Coût : sidecars (CPU/mémoire, latence) ou **ambient mode** (ztunnel, sans sidecar – selon version). Un mesh n’est pas un pare-feu réseau : combinez avec NetworkPolicy. À éviter si le besoin = « HTTPS entre services » (Service CA + re-encrypt suffit).

### 1.4 OpenShift Virtualization (KubeVirt)
VMs KVM exécutées **comme des Pods** (`virt-launcher`) : mêmes réseau, stockage, RBAC, monitoring, GitOps que les conteneurs.
| Objet | Rôle |
|---|---|
| `HyperConverged` | CR racine de l’Operator `kubevirt-hyperconverged` |
| `VirtualMachine` | définition persistante (`running`/`runStrategy`) |
| `VirtualMachineInstance` | exécution courante |
| `DataVolume` / `DataSource` | import d’images disque (HTTP, registre, PVC clone) |
| `Template` / `InstanceType` + `Preference` | gabarits |
| `VirtualMachineSnapshot`, `Clone`, `Restore`, `LiveMigration` | cycle de vie |
Prérequis : nœuds avec virtualisation matérielle (bare metal recommandé), stockage **RWX + Block** pour la migration à chaud, réseau secondaire (Multus/bridge/SR-IOV/UDN). Outil de migration depuis VMware/RHV/OpenStack : **Migration Toolkit for Virtualization (MTV)**. Console : *Virtualization*. CLI : `virtctl` (`console`, `ssh`, `start`, `migrate`).

### 1.5 Gestion de flotte : ACM, GitOps, politiques
**Red Hat Advanced Cluster Management** (hub) : `MultiClusterHub`, `ManagedCluster`, `ManagedClusterSet`, `Placement`, `Policy` (gouvernance déclarative : conformité de configuration sur tous les clusters), `Application` / `ApplicationSet` Argo CD, observabilité multi-cluster (Thanos), `ClusterClaim`, import/création de clusters. Modèle **Hub-Spoke** : agent `klusterlet` sur chaque cluster géré.
Politiques (`Policy` + `PlacementBinding`) : ex. « tous les clusters de prod ont ce `LimitRange`, ce `NetworkPolicy`, cet IdP » ; remédiation `inform` ou `enforce`. Complément : **Open Cluster Management**, **Submariner** (réseau multi-cluster), **Global load balancing** (DNS/GSLB).

### 1.6 Hosted Control Planes (HyperShift)
Le control plane d’un cluster *invité* est exécuté comme **Pods** dans un cluster de gestion (namespaces `clusters-<nom>`), les workers sont des NodePools (AWS, Azure, KubeVirt, bare metal Agent). Avantages : démarrage en minutes, coût (pas de 3 VMs CP par cluster), densité, isolation. CR : `HostedCluster`, `NodePool`. CLI : `hcp create cluster`. ROSA HCP est basé dessus.

### 1.7 Architectures de référence
| Besoin | Réponse |
|---|---|
| **HA** dans un site | 3 CP, workers sur ≥ 3 zones, `topologySpreadConstraints`, PDB, stockage répliqué |
| **DR** | cluster passif (warm) + GitOps + OADP/ODF Regional DR (Ramen) + DNS/GSLB ; objectifs RPO/RTO documentés |
| **Multi-environnements** | clusters dev/préprod/prod séparés (ou projets + quotas pour petits besoins) |
| **Multi-tenant fort** | clusters dédiés / HCP / nœuds dédiés + SCC + NetworkPolicy + quotas |
| **Edge** | SNO + ZTP (GitOps ZTP, `SiteConfig`/ClusterInstance) + RHACM + mises à jour planifiées |
| **Air-gap** | registre miroir, OSUS local, `oc-mirror`, Agent-based Installer |
| **Conformité** | Compliance Operator, ACS, FIPS, etcd chiffré, audit centralisé |
| **Coûts** | requests justes, VPA/KEDA, descheduler, Cost Management Operator, bin-packing |

### 1.8 Développement : Dev Spaces, Odo, Web Terminal
- **OpenShift Dev Spaces** : IDE web (VS Code) dans le cluster, `devfile.yaml` (workspaces reproductibles).
- **odo** : CLI inner-loop (`odo dev`) basée sur devfile.
- **Web Terminal** : terminal `oc` dans la console.
- **Telepresence / mirrord / Skaffold / Tilt** : développement avec cluster distant.
- **Red Hat Developer Hub** (Backstage) : portail développeur, templates, catalogue.

### 1.9 IA / GPU (aperçu)
**NVIDIA GPU Operator** + **Node Feature Discovery**, **Red Hat OpenShift AI** (notebooks, pipelines, serving KServe/vLLM, modèles), **Kueue** (files de jobs, quotas), **Node Tuning**/hugepages. Les ressources `nvidia.com/gpu` se demandent comme CPU/mémoire (`limits`).

### 1.10 Performance et fiabilité à grande échelle
Limites usuelles testées : ~2 000 nœuds, 150 000 Pods par cluster (selon version, voir *Scalability and performance*). Leviers : etcd sur disque NVMe dédié, API Priority & Fairness (`FlowSchema`), `maxPods`, sharding des routers, Thanos/rétention, `ClusterResourceOverride`, `PerformanceProfile`, tests de charge (`kube-burner`, `cluster-loader2`).

## 2. 🎬 Démo (60 min — au choix selon l’équipement)

```bash
oc new-project lab-avance
# Serverless
oc apply -f manifests/01-knative-service.yaml ; oc get ksvc,revision,pods -w     # scale-to-zero
curl $(oc get ksvc hello -o jsonpath='{.status.url}')
# KEDA
oc apply -f manifests/02-keda-scaledobject.yaml
# Mesh : mTLS strict + AuthorizationPolicy
oc apply -f manifests/03-mesh-policies.yaml
# Virtualization
oc apply -f manifests/04-virtualmachine.yaml ; oc get vm,vmi ; virtctl console demo-vm
# ACM : une politique de conformité
oc apply -f manifests/05-acm-policy.yaml
# HCP : création d'un cluster invité (cloud/KubeVirt)
hcp create cluster kubevirt --name demo --node-pool-replicas 2 --memory 8Gi --cores 2
```

## 3. 🧪 Labos

### Lab 12.1 ⭐⭐ — Service Knative et scale-to-zero 🔑
Installez Serverless + `KnativeServing`, déployez `01-knative-service.yaml`, observez la montée/descente à 0.

<details><summary>Corrigé</summary>

```bash
oc get knativeserving -n knative-serving
oc apply -f manifests/01-knative-service.yaml
watch oc get pods -l serving.knative.dev/service=hello
for i in $(seq 50); do curl -s $(oc get ksvc hello -o jsonpath='{.status.url}') >/dev/null & done
```
Après ~60-90 s sans trafic, plus aucun Pod.
</details>

### Lab 12.2 ⭐⭐⭐ — Canary Knative
Publiez une 2ᵉ révision, répartissez 80/20 puis 100 % sur la nouvelle, puis rollback.

<details><summary>Corrigé</summary>

```bash
kn service update hello --env TARGET=v2
kn service update hello --traffic hello-00001=80 --traffic @latest=20
kn revision list
```
</details>

### Lab 12.3 ⭐⭐⭐ — Autoscaling par événement (KEDA) 🔑
Scalez un Deployment `worker` de 0 à N selon une métrique Prometheus (ou cron).

<details><summary>Corrigé</summary>
Voir `02-keda-scaledobject.yaml` (trigger `cron` pour tester sans dépendance externe ; remplacer par `prometheus`). `oc get scaledobject,hpa -w`.
</details>

### Lab 12.4 ⭐⭐⭐⭐ — mTLS strict avec un mesh 🔑
Activez l’injection dans un projet, déployez deux services, imposez `STRICT`, prouvez qu’un Pod hors mesh est refusé, écrivez une `AuthorizationPolicy` `deny-all` + autorisation ciblée.

<details><summary>Corrigé</summary>
Voir `03-mesh-policies.yaml`. Test : `oc run outsider --rm -it --image=ubi-minimal -- curl -m3 http://svc.projet:8080` (connexion réinitialisée). Visualiser les flux dans Kiali.
</details>

### Lab 12.5 ⭐⭐⭐ — Une VM sur OpenShift 🔑
Installez l’Operator Virtualization, créez une VM Fedora/CentOS (cloud-init), exposez SSH par Service, prenez un snapshot, effectuez une migration à chaud (RWX).

<details><summary>Corrigé</summary>

```bash
oc apply -f manifests/04-virtualmachine.yaml
virtctl ssh cloud-user@vmi/demo-vm
virtctl migrate demo-vm
oc get vmim
```
Sans virtualisation imbriquée, utiliser l’émulation (`useEmulation: true`, très lent) en lab seulement.
</details>

### Lab 12.6 ⭐⭐⭐⭐ — Gouverner une flotte avec ACM 🔑
Importez un 2ᵉ cluster, créez un `ManagedClusterSet` et un `Placement`, appliquez une `Policy` imposant un `LimitRange` par défaut dans les namespaces `env=prod`, constatez la conformité.

<details><summary>Corrigé</summary>
Voir `05-acm-policy.yaml` : `Policy` + `PlacementBinding` + `Placement`. `oc get policy -A` ; console ACM → Governance. Passer `remediationAction` de `inform` à `enforce` pour corriger.
</details>

### Lab 12.7 ⭐⭐⭐⭐ — Cluster invité HCP 🔑
Créez un cluster hébergé (KubeVirt ou cloud), récupérez son kubeconfig (`hcp create kubeconfig`), déployez-y une application, observez les Pods du control plane côté management.

<details><summary>Corrigé</summary>

```bash
hcp create kubeconfig --name demo > demo.kubeconfig
KUBECONFIG=demo.kubeconfig oc get nodes
oc get pods -n clusters-demo
```
</details>

### Lab 12.8 ⭐⭐⭐⭐ — Revue d’architecture
Pour un cahier des charges fourni par l’instructeur (RPO 15 min / RTO 1 h, 3 sites, 200 microservices, 30 VMs héritées, conformité ISO/ANSSI), produisez un schéma, une topologie de clusters, une stratégie de DR, de sécurité et de mise à jour, et un budget de capacité. Défendez-le en 10 minutes.

<details><summary>Corrigé</summary>
Grille d’évaluation : cohérence HA/DR (RPO/RTO atteignables), séparation des environnements, gouvernance (GitOps+ACM), sécurité (SCC, NetPol, signature d’images, chiffrement), mises à jour (EUS, fenêtres), observabilité centralisée, coût, plan de migration des VMs (MTV), compétences et exploitation.
</details>

## 4. Quiz
1. Que permet le scale-to-zero ? → supprimer tous les Pods d’un service inactif (Knative/KEDA).
2. Différence Service Mesh / NetworkPolicy ? → L7 (mTLS, authz, routage) vs L3/L4.
3. Où s’exécute une VM OpenShift Virtualization ? → dans un Pod `virt-launcher` sur un nœud.
4. Que fait ACM Policy ? → vérifie/impose la configuration sur plusieurs clusters.
5. Avantage principal des Hosted Control Planes ? → control planes en Pods : coût, rapidité, densité.

Nettoyage : supprimer les CR et Operators installés pour le module.

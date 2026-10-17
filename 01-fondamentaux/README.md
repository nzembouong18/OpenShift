# Module 01 — Fondamentaux : architecture d'OpenShift

⏱ 3 h · 🟢

## Objectifs
- Situer OpenShift par rapport à Kubernetes (ce qui est ajouté, ce qui est différent)
- Comprendre l'architecture : nœuds, Cluster Operators, RHCOS, CVO, MCO
- Lire l'état d'un cluster et naviguer avec `oc`

## 1. Cours

### 1.1 OpenShift = Kubernetes + plateforme
OpenShift est une **distribution Kubernetes** « batteries incluses », opinionnée et supportée :

| Besoin | Kubernetes « nu » | OpenShift |
|---|---|---|
| Système des nœuds | libre (Ubuntu, etc.) | **RHCOS** (CoreOS, immuable, géré par le cluster) |
| Installation | kubeadm, à assembler | `openshift-install` (IPI/UPI), Assisted Installer, Agent-based |
| Mises à jour | manuelles, nœud par nœud | **automatiques** par le *Cluster Version Operator* (CVO) |
| Authentification | à intégrer (OIDC…) | **OAuth server** intégré (HTPasswd, LDAP, OIDC, GitHub…) |
| Sécurité des Pods | PSA (facultatif) | **SCC** + PSA ; conteneurs non-root par défaut |
| Exposition HTTP | Ingress + contrôleur au choix | **Router (HAProxy)** + objet `Route` |
| Builds d'images | externe | **BuildConfig, S2I**, Builds v2 (Shipwright) |
| Registre d'images | externe | **Registre interne** + `ImageStream` |
| Observabilité | à assembler | **Prometheus/Alertmanager/Grafana-dashboards** préinstallés, Logging |
| Extensions | Helm, manifests | **Operators / OLM** (OperatorHub) |
| Console | Dashboard optionnel | **Console web** complète (Admin + Developer) |
| Multi-tenant | namespaces | **Projects** (namespace + annotations + RBAC par défaut) |

> Slogan utile : *tout est un Operator*. Le cluster se gère lui-même par des contrôleurs qui réconcilient l'état désiré.

### 1.2 Architecture d'un cluster

```
                         ┌───────────── Control plane (3 nœuds, RHCOS) ─────────────┐
 oc / console / API ───► │ kube-apiserver  openshift-apiserver  oauth-apiserver      │
                         │ etcd (x3)  kube-controller-manager  kube-scheduler        │
                         │ + ~30 Cluster Operators (openshift-*)                     │
                         └───────────────────────────────────────────────────────────┘
                         ┌───────────── Workers (2+ nœuds RHCOS) ───────────────────┐
 Utilisateurs ─► Router  │ kubelet  CRI-O  OVN-Kubernetes  Pods applicatifs          │
                         └───────────────────────────────────────────────────────────┘
                         Infra nodes (optionnel) : router, registre, monitoring, logging
```

- **CRI-O** est le runtime (pas Docker/containerd). Outils : `crictl`, `podman` (hors cluster).
- **RHCOS** : image immuable, configurée par **Ignition** au premier boot, mise à jour par `rpm-ostree` sous la conduite du *Machine Config Operator* (MCO). **On ne se connecte pas en SSH pour configurer un nœud** : on crée un `MachineConfig`.
- **Control plane** : 3 nœuds pour la HA (etcd quorum). Variantes : *compact* (3 nœuds CP+worker), *SNO* (1 nœud), *Hosted Control Planes* (control plane hébergé comme Pods, module 12).

### 1.3 Les Cluster Operators
Chaque composant d'OpenShift est piloté par un Operator de premier niveau, dont l'état se lit avec `oc get clusteroperators` (`co`) :

| Operator | Rôle |
|---|---|
| `kube-apiserver`, `etcd`, `kube-controller-manager`, `kube-scheduler` | control plane Kubernetes |
| `authentication`, `oauth-apiserver` | OAuth, identités |
| `ingress` | Router HAProxy (`IngressController`) |
| `network`, `dns` | OVN-Kubernetes, CoreDNS |
| `image-registry`, `openshift-samples` | registre, ImageStreams d'exemple |
| `machine-config`, `machine-api` | système des nœuds, MachineSets |
| `monitoring`, `console`, `storage`, `operator-lifecycle-manager` | monitoring, UI, CSI, OLM |

Trois colonnes à lire : **AVAILABLE** (fonctionne), **PROGRESSING** (changement en cours), **DEGRADED** (problème). Un cluster sain : `True False False` partout.

Le **Cluster Version Operator** (`ClusterVersion/version`) applique la « release image » : il mettra à jour tous les autres Operators dans un ordre précis (*run levels*), puis le MCO redémarre les nœuds (module 11).

### 1.4 Les objets propres à OpenShift (API `*.openshift.io`)
| Objet | Rôle | Module |
|---|---|---|
| `Project` | namespace + méta-données + RBAC initial | 02 |
| `Route` | exposition HTTP/HTTPS/TLS | 05 |
| `ImageStream`, `ImageStreamTag` | abstraction sur les images, déclencheurs | 03 |
| `BuildConfig`, `Build` | construction d'images | 03 |
| `DeploymentConfig` | ancien contrôleur (déprécié, préférer `Deployment`) | 04 |
| `SecurityContextConstraints` | politique de sécurité des Pods | 07 |
| `OAuth`, `User`, `Identity`, `Group` | authentification | 07 |
| `ClusterOperator`, `ClusterVersion` | état du produit | 01, 11 |
| `Template` | paramétrage d'ensembles d'objets (`oc process`) | 02 |
| `MachineSet`, `Machine`, `MachineConfig(Pool)` | infrastructure et OS | 11 |

Découvrir : `oc api-resources | grep openshift.io`, `oc explain route.spec.tls`.

### 1.5 Projects et espaces `openshift-*`
Un **Project** est un namespace enrichi. Les espaces `openshift-*` et `kube-*` appartiennent à la plateforme : **ne jamais y déployer vos applications.** Projets utiles : `openshift` (ImageStreams et Templates globaux), `openshift-config` (config du cluster), `openshift-monitoring`, `openshift-marketplace`, `openshift-operators`.

### 1.6 `oc` : les commandes qu'il faut connaître
| Famille | Commandes |
|---|---|
| Session | `login`, `logout`, `whoami`, `project`, `projects`, `config` |
| Lecture | `get`, `describe`, `explain`, `status`, `logs`, `events`, `api-resources` |
| Création | `new-project`, `new-app`, `new-build`, `create`, `apply`, `process`, `expose` |
| Exécution | `rsh`, `exec`, `debug`, `port-forward`, `cp`, `run` |
| Admin | `adm top/policy/upgrade/must-gather/node-logs/drain/cordon/certificate/inspect` |
| Cycle | `rollout`, `scale`, `autoscale`, `set`, `start-build`, `import-image`, `tag` |

`oc status` donne une vue d'ensemble d'un project ; `oc get all` ne liste pas **tout** (CRD absentes).

### 1.7 L'API et les Operators : réconciliation
Boucle générale : `spec` (désiré) → contrôleur → action → `status` (observé). Les **CRD** étendent l'API : un Operator = un contrôleur + une ou plusieurs CRD (module 08). Une ressource `status.conditions` (`Available`, `Progressing`, `Degraded`) est la convention de lecture.

### 1.8 Rôles et personas
| Persona | Besoin | Modules |
|---|---|---|
| Développeur | Builder, déployer, exposer, debugger | 02-06, 09 |
| Admin plateforme | Opérer le cluster, sécurité, mises à jour | 07, 10, 11 |
| SRE / exploitant | Observabilité, incidents, capacité | 10, 11 |
| Architecte | Topologies, multi-cluster, conformité | 11, 12 |

## 2. 🎬 Démo (40 min)

```bash
oc login -u kubeadmin ...
oc get clusterversion                     # version, channel, upgradeable
oc get co                                 # tous Available / non Degraded
oc get nodes -o wide                      # RHCOS, CRI-O, versions kubelet
oc get machineconfigpool                  # master / worker : UPDATED ?
oc get pods -n openshift-apiserver        # openshift-apiserver est un Deployment de Pods statiques/containers
oc get ingresscontroller -n openshift-ingress-operator
oc get route -A | head                    # consoles et OAuth sont des Routes
oc api-resources --api-group=route.openshift.io
oc explain project.spec ; oc explain route.spec.tls.termination
oc debug node/$(oc get nodes -o name | head -1 | cut -d/ -f2) -- chroot /host bash -c 'cat /etc/os-release; crictl ps | head -5; rpm-ostree status'
oc new-project demo-1 && oc new-app --image=docker.io/openshift/hello-openshift && oc status
```
Faire prédire : « que contient `oc get all` dans un project vide ? » ; « pourquoi `oc debug node` demande-t-il `chroot /host` ? »

## 3. 🧪 Labos

> Projet : `lab-fondamentaux`

### Lab 1.1 ⭐ — Lire l'état d'un cluster 🔑
Listez : la version et le canal du cluster, le nombre de nœuds et leurs rôles, les Operators `Progressing` ou `Degraded`, le domaine d'applications.

<details><summary>Corrigé</summary>

```bash
oc get clusterversion version -o jsonpath='{.status.desired.version} {.spec.channel}{"\n"}'
oc get nodes --show-labels | sed 's/,/\n/g' | grep node-role
oc get co | awk '$4=="True" || $5=="True"'
oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}{"\n"}'
```
</details>

### Lab 1.2 ⭐ — Découvrir l'API
Trouvez, avec `oc api-resources` et `oc explain`, la liste des champs de `Route.spec.tls` et de `BuildConfig.spec.strategy`.

<details><summary>Corrigé</summary>

```bash
oc explain route.spec.tls --recursive | head -30
oc explain buildconfig.spec.strategy
oc api-resources --namespaced=true | grep -E 'openshift.io'
```
</details>

### Lab 1.3 ⭐⭐ — Inspecter un nœud sans SSH 🔑
Avec `oc debug node/...`, affichez la version de RHCOS, la liste des conteneurs CRI-O du nœud et la configuration kubelet. Pourquoi ne modifie-t-on rien ici ?

<details><summary>Corrigé</summary>

```bash
NODE=$(oc get nodes -o name | head -1)
oc debug $NODE -- chroot /host bash -c 'cat /etc/os-release | head -3; crictl ps | head; cat /etc/kubernetes/kubelet.conf | head -20'
```
Le système est géré par le MCO : toute modification manuelle serait écrasée ou provoquerait un `Degraded`. Pour configurer : `MachineConfig` (module 11).
</details>

### Lab 1.4 ⭐⭐ — Suivre la boucle de réconciliation
Créez un Deployment dans `lab-fondamentaux`, supprimez-en un Pod et observez les événements (`oc get events --sort-by=.lastTimestamp`). Identifiez quel contrôleur a agi.

<details><summary>Corrigé</summary>

```bash
oc new-project lab-fondamentaux
oc create deployment web --image=registry.access.redhat.com/ubi9/nginx-124 --replicas=2
oc delete pod -l app=web --wait=false
oc get events --sort-by=.lastTimestamp | tail
```
Le ReplicaSet (via le controller-manager) recrée les Pods ; le scheduler place, le kubelet démarre.
</details>

### Lab 1.5 ⭐⭐⭐ — Cartographier les Operators
Dressez un tableau `Operator → namespace → Pods → CRD gérées` pour 5 Cluster Operators de votre choix.

<details><summary>Corrigé</summary>

```bash
oc get co ingress -o yaml | grep -A12 relatedObjects
oc get pods -n openshift-ingress-operator
oc get pods -n openshift-ingress
oc get crd | grep -E 'ingresscontroller|operator.openshift.io' | head
```
`status.relatedObjects` d'un ClusterOperator liste les ressources qu'il surveille — très utile pour diagnostiquer.
</details>

### Lab 1.6 ⭐⭐⭐⭐ — Comparer à Kubernetes
Rédigez (10 lignes) les différences d'**exposition HTTP**, de **sécurité des Pods** et de **mise à jour** entre ce cluster et un cluster kubeadm. Démontrez par la pratique qu'un conteneur exécutant `nginx` (image Docker Hub officielle, qui tourne en root) échoue ici.

<details><summary>Corrigé</summary>

```bash
oc create deployment nginx-root --image=docker.io/library/nginx:1.27
oc get pods ; oc logs deploy/nginx-root     # permission denied sur /var/cache/nginx ou bind 80
```
Raison : la SCC `restricted-v2` impose un UID arbitraire dans une plage du projet (annotation `openshift.io/sa.scc.uid-range`) et interdit root. Solution propre : image non-root (`nginxinc/nginx-unprivileged`, `ubi9/nginx-124`). Voir module 07.
</details>

## 4. Quiz
1. Quel composant applique les mises à jour de plateforme ? → CVO (Cluster Version Operator).
2. Comment configure-t-on un paramètre kernel sur les workers ? → `MachineConfig` (MCO), jamais en SSH.
3. Différence Project / Namespace ? → un Project est un namespace enrichi (annotations, quotas, RBAC par défaut) créé via `oc new-project`.
4. Quel runtime de conteneurs ? → CRI-O.
5. Que signifie `DEGRADED=True` pour un ClusterOperator ? → l'Operator ne peut plus garantir l'état désiré ; consulter `oc describe co <nom>`.

Nettoyage : `oc delete project lab-fondamentaux demo-1`

# Module 08 — Operators, OLM et OperatorHub

⏱ 3 h 30 · 🟡🔴

## Objectifs
- Comprendre le pattern **Operator** (CRD + contrôleur) et le **Operator Lifecycle Manager**
- Installer, mettre à jour, contrôler des Operators (console, CLI, GitOps)
- Gérer catalogues, canaux, approbations, installations déconnectées
- Écrire un premier Operator (Helm / Ansible / Go) avec l'Operator SDK

## 1. Cours

### 1.1 Le pattern Operator
Un Operator encode la connaissance d'un exploitant : **CRD** (ex. `PostgresCluster`) + **contrôleur** qui réconcilie l'état souhaité (installation, sauvegarde, bascule, mise à jour). Niveaux de maturité (Operator Capability Levels) : 1 Install · 2 Upgrades · 3 Lifecycle · 4 Insights · 5 Autopilot.

Deux familles :
| Famille | Exemples | Gestion |
|---|---|---|
| **Cluster Operators** (plateforme) | `authentication`, `ingress`, `network` | CVO (module 01, 11) — pas d'OLM |
| **Operators optionnels** (add-ons) | Pipelines, GitOps, ODF, Logging, Service Mesh, CloudNativePG | **OLM** via OperatorHub |

### 1.2 Operator Lifecycle Manager (OLM)
| Objet | Rôle |
|---|---|
| `CatalogSource` | source de catalogue (image d'index) : `redhat-operators`, `certified-operators`, `community-operators`, `redhat-marketplace` |
| `PackageManifest` | un Operator disponible (canaux, versions) — lecture seule |
| `OperatorGroup` | définit la **portée** : `AllNamespaces`, `OwnNamespace`, `SingleNamespace`, `MultiNamespace` |
| `Subscription` | « je veux cet Operator sur ce canal » ; `installPlanApproval: Automatic|Manual` |
| `InstallPlan` | plan d'installation/upgrade (à approuver si Manual) |
| `ClusterServiceVersion` (CSV) | une version installée : permissions, déploiement, CRD, ses `status.phase: Succeeded` |

```
CatalogSource ──► PackageManifest ──► Subscription ──► InstallPlan ──► CSV ──► Deployment (Operator)
                                                                           └──► CRD  ──► vos CR
```
Un seul `OperatorGroup` par namespace. Les installs en `AllNamespaces` vont dans `openshift-operators` ; les autres dans un namespace dédié (`openshift-<nom>`) avec son OperatorGroup.

**OLM v1** (nouvelle architecture : `ClusterExtension`, `ClusterCatalog`) arrive en aperçu puis GA progressif sur 4.18+ ; les concepts restent proches mais la gestion est cluster-scoped et plus simple. Vérifiez l'état dans votre version.

### 1.3 Installer un Operator
**Console** : Operators → OperatorHub → rechercher → Install (choix canal, mode d'installation, approbation).
**CLI** (idempotent, GitOps-friendly) :
```yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata: {name: monop, namespace: openshift-monop}
spec: {targetNamespaces: [openshift-monop]}
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata: {name: monop, namespace: openshift-monop}
spec:
  channel: stable
  name: <nom-du-package>
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Manual
```
Commandes : `oc get packagemanifest | head`, `oc describe packagemanifest <nom> -n openshift-marketplace`, `oc get sub,ip,csv -n <ns>`, `oc get csv -w`.

### 1.4 Mises à jour et canaux
- Chaque canal (`stable`, `stable-1.2`, `fast`, `tech-preview`) a un chemin d'upgrade (« graph »).
- `Automatic` : mise à jour dès qu'une nouvelle version est publiée dans le canal (risque en production).
- `Manual` : l'InstallPlan reste `RequiresApproval` → `oc patch installplan <ip> --type=merge -p '{"spec":{"approved":true}}'`.
- `startingCSV` pour épingler une version initiale.
- Compatibilité avec la version OCP : `olm.maxOpenShiftVersion`, le CVO bloque les mises à niveau si un Operator est incompatible (`Upgradeable=False`).

### 1.5 Utiliser un Operator
Une fois le CSV `Succeeded`, vous créez des **Custom Resources** (CR) : par exemple un `Cluster` (CloudNativePG), un `ArgoCD`, un `TektonConfig`. `oc explain <crd>.spec`, `oc get crd | grep <groupe>`, exemples « alm-examples » dans le CSV : `oc get csv <csv> -o jsonpath='{.metadata.annotations.alm-examples}' | jq`.

### 1.6 Catalogues : Red Hat, communauté, privés
- Par défaut 4 catalogues (désactivables : `operatorhub/cluster` → `spec.disableAllDefaultSources`).
- **Déconnecté / air-gapped** : `oc-mirror` (v2) copie les images vers un registre miroir ; `ImageDigestMirrorSet`/`ImageTagMirrorSet` redirigent les pulls ; `CatalogSource` filtré pointe vers l'index miroir. Désactiver les catalogues publics.
- **Catalogue privé** : construire un index `opm` (`opm index add` / catalogs FBC) avec seulement les Operators approuvés → gouvernance.

### 1.7 Dépannage OLM
| Symptôme | Piste |
|---|---|
| Subscription `UpgradePending` | InstallPlan `RequiresApproval` |
| CSV `Failed` / `InstallCheckFailed` | `oc describe csv` ; pod de l'Operator, quotas, SCC |
| `ConstraintsNotSatisfiable` | dépendance manquante ou conflit (même CRD fournie par 2 Operators) |
| `no operator group found` | OperatorGroup absent ou multiple dans le namespace |
| Catalogue `TRANSIENT_FAILURE` | image d'index inaccessible, pull secret manquant |
| Operator disparu après suppression de namespace | supprimer d'abord les CR, puis Subscription + CSV |
`oc get events -n openshift-marketplace`, `oc logs -n openshift-operator-lifecycle-manager deploy/olm-operator`.

### 1.8 Écrire un Operator
| Framework | Quand | Complexité |
|---|---|---|
| **Helm** (Operator SDK) | chart existant → CRD | faible |
| **Ansible** | logique d'exploitation scriptée | moyenne |
| **Go** (controller-runtime / kubebuilder) | contrôle total, performance | élevée |
Workflow : `operator-sdk init` → `create api` (CRD) → implémenter `Reconcile` → `make install run` (test local) → `make docker-build bundle` → `operator-sdk run bundle` (OLM) → publier dans un catalogue.
Bon contrôleur : **idempotent**, basé sur le `status`, avec finalizers, gestion d'erreurs/re-queue, conditions standard, métriques.

### 1.9 Sécurité des Operators
Un Operator est souvent **cluster-admin de fait** : audit des permissions (`oc get csv -o yaml | grep -A40 clusterPermissions`), catalogue maîtrisé, `Manual` en prod, `ResourceQuota` pour `openshift-operators`, NetworkPolicy, signature de bundles.

## 2. 🎬 Démo (45 min)

```bash
oc get catalogsource -n openshift-marketplace
oc get packagemanifest -n openshift-marketplace | wc -l
oc get packagemanifest cloud-native-postgresql -n openshift-marketplace -o jsonpath='{.status.channels[*].name}'   # ou autre Operator du catalogue
# Installer un Operator par YAML (Subscription Manual)
oc apply -f manifests/01-subscription-example.yaml
oc get ip -n openshift-operators ; oc patch ip <ip> -n openshift-operators --type=merge -p '{"spec":{"approved":true}}'
oc get csv -n openshift-operators -w
# Créer une CR et regarder le contrôleur agir
oc get csv <csv> -n openshift-operators -o jsonpath='{.metadata.annotations.alm-examples}' | jq '.[0]'
# Les CRD d'un Operator
oc get crd | grep -i postgresql ; oc explain cluster.spec | head
# Désinstaller proprement
oc delete sub <nom> -n <ns> ; oc delete csv <csv> -n <ns>
```

## 3. 🧪 Labos

> Les Operators de ce module sont **communautaires/publics** : choisissez ceux disponibles dans votre catalogue (`oc get packagemanifest`).

### Lab 8.1 ⭐ — Explorer OperatorHub
Via la console puis la CLI : combien d'Operators par catalogue ? Quel est le canal par défaut de `openshift-gitops-operator` ? Quelles sont les CRD fournies par `openshift-pipelines-operator-rh` ?

<details><summary>Corrigé</summary>

```bash
oc get packagemanifest -n openshift-marketplace -o custom-columns=NAME:.metadata.name,CAT:.status.catalogSource | sort -k2 | uniq -c -f1
oc get packagemanifest openshift-gitops-operator -n openshift-marketplace -o jsonpath='{.status.defaultChannel}{"\n"}'
oc get packagemanifest openshift-pipelines-operator-rh -n openshift-marketplace -o jsonpath='{.status.channels[0].currentCSVDesc.customresourcedefinitions.owned[*].name}'
```
</details>

### Lab 8.2 ⭐⭐ — Installer un Operator en mode Manual 🔑
Installez l'Operator de votre choix (ex. *Web Terminal*, *cert-manager*, *CloudNativePG*) avec `installPlanApproval: Manual`, approuvez l'InstallPlan, vérifiez le CSV.

<details><summary>Corrigé</summary>
Adapter `manifests/01-subscription-example.yaml` (nom de package, canal, source). Puis `oc get ip -n <ns>` → `approved: false` → patch `approved: true` → `oc get csv -w` jusqu'à `Succeeded`.
</details>

### Lab 8.3 ⭐⭐ — Utiliser une CR
Créez une instance de la ressource fournie par l'Operator (exemple `alm-examples`), constatez les objets créés (Pods, Services, Secrets), puis supprimez une dépendance (Pod, Secret généré) pour voir la **réconciliation**.

<details><summary>Corrigé</summary>

```bash
oc get csv -n <ns> <csv> -o jsonpath='{.metadata.annotations.alm-examples}' | jq '.[0]' | oc apply -f -
oc get all,secrets -l <label>
oc delete pod <pod-geré>      # l'Operator le recrée
oc logs deploy/<operator> -n <ns> | tail
```
</details>

### Lab 8.4 ⭐⭐ — Diagnostiquer une installation bloquée
Appliquez `manifests/02-broken-subscription.yaml` (nom de package erroné, pas d'OperatorGroup). Trouvez et corrigez les deux causes.

<details><summary>Corrigé</summary>

```bash
oc get sub -n lab-operators -o yaml | grep -A8 conditions     # ResolutionFailed : package inconnu
oc get operatorgroup -n lab-operators                         # aucun → "no operator group found"
oc get packagemanifest | grep <nom>
```
</details>

### Lab 8.5 ⭐⭐⭐ — Gouvernance de catalogues 🔑
Désactivez les sources communautaires, ajoutez un `CatalogSource` privé (image d'index fournie par l'instructeur), vérifiez qu'un Operator communautaire n'est plus installable.

<details><summary>Corrigé</summary>

```bash
oc patch operatorhub cluster --type=json -p '[{"op":"add","path":"/spec/sources","value":[{"name":"community-operators","disabled":true}]}]'
oc apply -f manifests/03-catalogsource.yaml
oc get catalogsource -n openshift-marketplace -w
```
</details>

### Lab 8.6 ⭐⭐⭐ — Operator Helm avec l'Operator SDK
Créez un Operator à partir d'un chart nginx, déployez-le localement (`make install run`), créez une CR `Nginx` et changez `replicaCount`.

<details><summary>Corrigé</summary>

```bash
operator-sdk init --plugins helm --domain formation.io --group demo --version v1 --kind Nginx --helm-chart bitnami/nginx
make install
make run &            # contrôleur en local
oc apply -f config/samples/demo_v1_nginx.yaml
oc patch nginx nginx-sample --type=merge -p '{"spec":{"replicaCount":3}}'
oc get pods -l app.kubernetes.io/instance=nginx-sample
```
Les images Bitnami ne sont plus toutes publiques : substituez un chart/images UBI si besoin.
</details>

### Lab 8.7 ⭐⭐⭐⭐ — Operator Go minimal
Générez un Operator Go (`App` CRD → Deployment + Service + Route). Implémentez `Reconcile`, un finalizer, la mise à jour du `status.conditions`, puis `operator-sdk run bundle`.

<details><summary>Corrigé</summary>
Squelette dans `manifests/04-app-crd-sample.yaml` (CRD et CR d'exemple). Étapes : `operator-sdk init --repo`, `create api --resource --controller`, markers kubebuilder, `controllerutil.CreateOrUpdate`, `SetControllerReference` (garbage collection), `make generate manifests bundle bundle-build`.
</details>

### Lab 8.8 ⭐⭐⭐⭐ — Mise à niveau contrôlée
Pour un Operator installé en `stable-x`, simulez la montée de version : épingler `startingCSV`, observer l'InstallPlan de la version suivante, rollback par réinstallation à la version précédente (sans perdre les CR).

<details><summary>Corrigé</summary>
OLM ne sait pas revenir en arrière automatiquement : conserver les CR (`oc get <cr> -o yaml > backup.yaml`), `Manual` en production, test sur un cluster de préproduction, lecture des *release notes* et du graphe de mise à jour (`oc get packagemanifest -o yaml`, `replaces`/`skips`).
</details>

## 4. Quiz
1. Que contient un CSV ? → métadonnées, permissions RBAC, déploiement de l'Operator, CRD fournies/requises.
2. Quelle différence `Automatic` / `Manual` ? → upgrades appliquées seules vs InstallPlan à approuver.
3. À quoi sert un OperatorGroup ? → définir les namespaces surveillés par l'Operator (et ses RBAC).
4. Comment installer des Operators sans Internet ? → `oc-mirror`, registre miroir, `CatalogSource` filtré, `ImageDigestMirrorSet`.
5. Cluster Operators vs Operators OLM ? → plateforme (CVO) vs add-ons (OLM).

Nettoyage : `oc delete project lab-operators` et désinstallation des Operators de test.

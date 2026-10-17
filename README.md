# Formation OpenShift — du débutant à l'expert confirmé

Formation pratique orientée *labs*, construite sur le même modèle que la formation Kubernetes du même auteur. Chaque module contient : un **cours**, une **démo** (formateur), des **labos** (apprenants) avec **corrigés**, et un **quiz**.

- **Durée** : 6 jours (≈ 42 h) — ou 12 demi-journées en format distanciel
- **Public** : développeurs, admins système, DevOps/SRE, architectes, exploitants de plateforme
- **Niveau** : débutant → intermédiaire → avancé → expert (préparation indicative aux examens Red Hat EX280 / EX288 / EX380)
- **Langue** : français (commandes et YAML en anglais, comme dans l'écosystème)
- **Plateformes cibles** : OpenShift Container Platform (OCP) **4.16 → 4.19**, OpenShift Local (CRC), OKD, Developer Sandbox

## Prérequis

| Domaine | Niveau attendu |
|---|---|
| Linux / shell | À l'aise (fichiers, processus, réseau de base) |
| Conteneurs | Savoir lancer un conteneur et lire un Dockerfile |
| Kubernetes | Notions de Pod, Deployment, Service (la [formation K8s](https://github.com/nzembouong18/K8s) est un excellent préalable, mais le module 01 refait les bases) |
| YAML / Git | Lecture / écriture, `git clone/commit/push` |
| Matériel | 16 Go RAM, 6 vCPU, 50 Go disque pour OpenShift Local ; **ou** un navigateur seul pour le Developer Sandbox |

## Parcours

| Jour | Module | Objectifs | Niveau |
|---|---|---|---|
| J1 | [00 — Setup](00-setup/README.md) | CRC / Sandbox / OKD, `oc`, console web | 🟢 |
| J1 | [01 — Fondamentaux](01-fondamentaux/README.md) | Architecture, Cluster Operators, RHCOS, `oc` vs `kubectl` | 🟢 |
| J1 | [02 — Projets & applications](02-projets-applications/README.md) | Projects, `oc new-app`, console Developer, quotas | 🟢 |
| J2 | [03 — Builds & S2I](03-builds-s2i/README.md) | ImageStreams, BuildConfig, Source-to-Image, Builds v2 | 🟢🟡 |
| J2 | [04 — Workloads](04-workloads/README.md) | Deployments, DeploymentConfig (legacy), probes, HPA, Jobs | 🟡 |
| J3 | [05 — Réseau](05-reseau/README.md) | Routes, TLS, Ingress, OVN-Kubernetes, NetworkPolicy, Multus | 🟡 |
| J3 | [06 — Config & stockage](06-config-stockage/README.md) | ConfigMap, Secret, PV/PVC, CSI, LVMS/ODF, snapshots | 🟡 |
| J4 | [07 — Sécurité](07-securite/README.md) | OAuth, RBAC, SCC, Pod Security, certificats, conformité | 🟡🔴 |
| J4 | [08 — Operators](08-operators/README.md) | OLM, OperatorHub, Subscriptions, CRD, Operator SDK | 🟡🔴 |
| J5 | [09 — Pipelines & GitOps](09-pipelines-gitops/README.md) | Tekton (OpenShift Pipelines), Argo CD (OpenShift GitOps) | 🟡🔴 |
| J5 | [10 — Observabilité](10-observabilite/README.md) | Monitoring, UWM, alertes, logging, tracing, must-gather | 🟡🔴 |
| J6 | [11 — Administration du cluster](11-administration-cluster/README.md) | MachineConfig, MachineSet, mises à jour, etcd, autoscaling, installation | 🔴 |
| J6 | [12 — Avancé & écosystème](12-avance/README.md) | Serverless, Service Mesh, Virtualization, ACM, HCP, multi-tenant | 🔴⚫ |
| J6 | [13 — Projet final](13-projet-final/README.md) | Application 3-tiers de bout en bout, qualité « production » | 🔴 |

Documents transverses : [Guide formateur](docs/formateur.md) · [Aide-mémoire `oc`](docs/cheatsheet.md) · [Troubleshooting](docs/troubleshooting.md) · [Évaluation & certifications](docs/evaluation.md) · [Glossaire](docs/glossaire.md)

## Quel environnement pour quel module ?

Les labos qui exigent les droits **cluster-admin** sont marqués 🔑. Les autres tournent partout, y compris sur le **Developer Sandbox** (gratuit, sans installation).

| Environnement | Droits | Modules complets | Limites |
|---|---|---|---|
| **OpenShift Local (CRC)** | `kubeadmin` | 00 → 10, 12 (partiel) | 1 nœud, pas de MachineSet réel, pas de mise à jour |
| **OKD / SNO** (Single Node) | cluster-admin | 00 → 12 | Plus de ressources, 100 % open source |
| **Developer Sandbox** | utilisateur, 2 projects | 00 → 06, 09 (partiel), 10 (partiel) | Pas de 🔑, ressources plafonnées, mise en veille |
| **Cluster formateur / OCP cloud** | cluster-admin | tout | Coût, à détruire après la session |

## Démarrage rapide

```bash
git clone https://github.com/nzembouong18/OpenShift && cd OpenShift
./00-setup/scripts/install-tools.sh      # oc, kubectl, helm, tkn, argocd (Linux amd64)
make crc-start PULL_SECRET=~/pull-secret.txt   # ou : oc login <url> (Sandbox / cluster existant)
make check                               # vérifie l'environnement
```

Chaque module se travaille depuis son dossier :

```bash
cd 04-workloads && cat README.md
oc apply -f manifests/<fichier>.yaml
```

Nettoyage d'un module : `oc delete project <projet-du-module>` — chaque module utilise son propre projet (`lab-apps`, `lab-builds`, …). `make clean-labs` supprime tous les projets `lab-*`.

## Méthode pédagogique

1. **Comprendre** (cours, 25 %) — schémas et concepts, peu de slides
2. **Voir** (démo, 20 %) — le formateur exécute, les apprenants suivent
3. **Faire** (labos, 50 %) — énoncé + indices + corrigé repliable
4. **Vérifier** (quiz + `make check-<module>`)

Les labos sont gradués : ⭐ guidé · ⭐⭐ semi-guidé · ⭐⭐⭐ autonome · ⭐⭐⭐⭐ expert (énoncé seul, pour les rapides).

## Fil rouge

Une même application, **`vote-app`** (code dans [`13-projet-final/app`](13-projet-final/app)), évolue module après module : image bâtie par S2I → Deployment → Route TLS → ConfigMap/Secret → PVC PostgreSQL → SCC / NetworkPolicy → Pipeline Tekton → Argo CD → monitoring → Serverless. Le module 13 la porte au niveau production.

## Versions de référence

OpenShift **4.16–4.19** (Kubernetes 1.29–1.32), `oc` correspondant, OVN-Kubernetes, Operators : OpenShift Pipelines 1.1x (Tekton `v1`), OpenShift GitOps 1.1x (Argo CD 2.x), Logging 6.x (Vector + Loki), Service Mesh 3.x, Serverless 1.3x, Virtualization 4.1x. Les noms de canaux d'Operators évoluent : **vérifiez toujours** avec `oc get packagemanifest <nom> -n openshift-marketplace -o jsonpath='{.status.defaultChannel}'` avant d'appliquer une `Subscription`.

## Licence

Contenu libre pour usage pédagogique. Adaptez-le à votre contexte. « OpenShift » et « Red Hat » sont des marques de Red Hat, Inc.

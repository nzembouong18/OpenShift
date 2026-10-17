# Module 09 — CI/CD : OpenShift Pipelines (Tekton) et OpenShift GitOps (Argo CD)

⏱ 4 h · 🟡🔴

## Objectifs
- Construire des pipelines cloud-native avec **Tekton** (Tasks, Pipelines, Triggers, Results, Chains)
- Livrer par **GitOps** avec **Argo CD** (Applications, ApplicationSets, sync waves, hooks)
- Structurer dépôts, environnements, promotion, sécurité de la chaîne de livraison

## 1. Cours

### 1.1 CI vs CD, push vs pull
| | CI (intégration) | CD (livraison) |
|---|---|---|
| But | construire, tester, scanner, publier l'artefact | déployer l'état désiré, le **réconcilier en continu** |
| Outil ici | **Tekton** (OpenShift Pipelines) | **Argo CD** (OpenShift GitOps) |
| Mode | exécution de pipelines (événementiel) | **pull** : le cluster tire Git |
Le flux : `git push` → webhook → PipelineRun (build/test/scan/push image + commit du tag dans le dépôt de config) → Argo CD détecte → sync → application à jour. **Aucun** identifiant du cluster hors du cluster.

### 1.2 Tekton : les objets
| Objet | Rôle |
|---|---|
| `Task` / `ClusterTask`* | suite d'étapes (conteneurs) dans un même Pod |
| `Pipeline` | graphe de Tasks (`runAfter`, `when`, `finally`) |
| `PipelineRun` / `TaskRun` | exécution d'un Pipeline / d'une Task |
| `Workspace` | volume partagé (PVC, emptyDir, ConfigMap, Secret) |
| `Results`, `Params` | sorties/entrées typées |
| `Trigger*` (EventListener, TriggerBinding, TriggerTemplate) | déclenchement par webhook |
| `PipelinesAsCode` | pipelines versionnés dans `.tekton/` du dépôt, déclenchés par Git |
| `Tekton Chains` | signature + attestations (SLSA) des artefacts |
| `Tekton Results` | historique long terme des exécutions |
\* `ClusterTask` est déprécié : utilisez le **Tekton Hub / Artifact Hub**, ou des *resolvers* (`git`, `hub`, `cluster`, `bundles`) qui référencent les Tasks sans les copier.

API actuelle : `tekton.dev/v1`. Les tâches fournies par l'Operator sont dans `openshift-pipelines` (`git-clone`, `buildah`, `s2i-*`, `openshift-client`, `maven`…), accessibles via resolver `cluster`.

### 1.3 Installation et sécurité
Operator `openshift-pipelines-operator-rh` (installation `AllNamespaces`, CR `TektonConfig` créée automatiquement). Dans chaque projet, le SA `pipeline` est créé et reçoit les droits nécessaires au build (SCC `pipelines-scc` pour buildah en utilisateur non-root). Secrets de push : `oc secrets link pipeline regcred`, annotation `tekton.dev/git-0` pour Git.

### 1.4 Pipeline type
```
 git-clone ─► tests ─► buildah (build+push) ─► scan (ACS/trivy) ─► update-gitops-repo (kustomize edit) ─► (Argo CD sync)
                               └─ finally : notification
```
`when` conditionne une tâche (`input: $(params.deploy)`), `finally` s'exécute toujours, `timeouts` limitent les durées, `retries` rejouent les étapes instables.

### 1.5 Pipelines as Code (PaC)
Le dépôt Git contient `.tekton/pull-request.yaml` ; un `Repository` CR (CRD `pipelinesascode.tekton.dev`) relie le dépôt au cluster ; la GitHub App ou le webhook déclenche. Statut renvoyé dans la PR. Avantage : pipeline versionné avec le code, un pipeline par événement (PR / push / tag).

### 1.6 Argo CD (OpenShift GitOps)
Operator `openshift-gitops-operator` : installe une instance `openshift-gitops` (namespace `openshift-gitops`), intégrée à l'authentification OpenShift (SSO via Dex/OAuth). CRD `ArgoCD` pour créer des instances supplémentaires par équipe.
| Objet | Rôle |
|---|---|
| `Application` | source Git (repo/chemin/révision) → destination (cluster/namespace) ; `syncPolicy` |
| `AppProject` | frontière multi-tenant : dépôts, destinations, types d'objets autorisés |
| `ApplicationSet` | génère des Applications (liste, git directories, clusters, matrix) |
| `Repository`/`Cluster` secrets | accès aux dépôts et clusters |
`syncPolicy.automated {prune, selfHeal}` + `syncOptions: [CreateNamespace=true]`. États : `Synced/OutOfSync`, `Healthy/Progressing/Degraded`.

### 1.7 Organiser les dépôts GitOps
```
app-repo/                       gitops-repo/
  src/ , Containerfile            base/ (Deployment, Service, Route)
  .tekton/ (PaC)                  overlays/dev | staging | prod  (Kustomize)
                                  apps/ (Application, ApplicationSet)
```
- Séparer **code** et **configuration** (cycles de vie et droits différents).
- Promotion = **Pull Request** vers l'overlay suivant (revue = contrôle de changement).
- Kustomize (natif `oc apply -k`) ou Helm ; les `Template` OpenShift sont possibles mais moins adaptés.

### 1.8 Fonctions avancées Argo CD
| Besoin | Mécanisme |
|---|---|
| Ordonnancement | `argocd.argoproj.io/sync-wave: "-1"` ; hooks `PreSync/PostSync` (Jobs de migration) |
| Ignorer des champs gérés ailleurs | `ignoreDifferences` (ex. `replicas` si HPA) |
| Secrets | Sealed Secrets, SOPS, External Secrets, Vault plugin |
| Progressive delivery | **Argo Rollouts** (canary/blue-green avec analyse Prometheus) |
| Multi-clusters | `Cluster` secrets, ApplicationSet cluster generator + RHACM |
| Notifications | `argocd-notifications` (Slack, mail, webhook) |
| Cycle de promotion | Image Updater, ou commit du pipeline Tekton |

### 1.9 Sécurité de la chaîne d'approvisionnement (supply chain)
- Builds **hermétiques**, base images approuvées, scan (ACS/Clair/Trivy), SBOM (syft), **signatures** (cosign, Tekton Chains), attestations SLSA.
- Politique à l'admission (module 07) : n'autoriser que les images signées/digest.
- Comptes de service **par pipeline**, droits minimaux ; secrets via gestionnaires externes ; branches protégées et revues obligatoires.

## 2. 🎬 Démo (55 min)

```bash
# Prérequis 🔑 : installer les Operators OpenShift Pipelines et OpenShift GitOps (module 08)
oc new-project lab-cicd
# Pipeline Tekton : clone + build S2I/Buildah + déploiement
oc apply -f manifests/01-pipeline-build-deploy.yaml
tkn pipeline start build-and-deploy -p git-url=https://github.com/nzembouong18/OpenShift -p image=image-registry.openshift-image-registry.svc:5000/lab-cicd/vote-api --workspace name=source,volumeClaimTemplateFile=manifests/pvc-template.yaml --showlog
tkn pipelinerun list ; oc get pods
# Triggers (webhook)
oc apply -f manifests/02-triggers.yaml ; oc get route el-vote-listener
# Argo CD
oc get route openshift-gitops-server -n openshift-gitops
oc apply -f manifests/03-argocd-application.yaml ; argocd app list  # ou console Argo CD
oc get applications.argoproj.io -n openshift-gitops
# Dérive : modifier à la main, observer selfHeal
oc scale deploy/vote-api --replicas=5 ; oc get deploy vote-api -w
```

## 3. 🧪 Labos

> Projet : `lab-cicd` — 🔑 pour l'installation des Operators

### Lab 9.1 ⭐ — Installer les Operators 🔑
Installez *OpenShift Pipelines* et *OpenShift GitOps* via OperatorHub (canal par défaut). Vérifiez les CSV et les CRD.

<details><summary>Corrigé</summary>

```bash
oc get csv -n openshift-operators | grep -E 'pipelines|gitops'
oc get tektonconfig config ; oc get argocd -n openshift-gitops
oc get crd | grep -E 'tekton.dev|argoproj.io' | wc -l
```
Sur le Sandbox, ces Operators sont déjà installés.
</details>

### Lab 9.2 ⭐ — Première Task
Créez une Task `hello` à deux étapes (`echo`, `date`) et lancez-la : `tkn task start hello --showlog`.

<details><summary>Corrigé</summary>
Voir la Task `hello` dans `manifests/01-pipeline-build-deploy.yaml`. Chaque `step` est un conteneur dans le même Pod ; `workingDir` et `/workspace` partagés.
</details>

### Lab 9.3 ⭐⭐ — Pipeline build + déploiement
Exécutez le pipeline `build-and-deploy` (git-clone → buildah → `oc rollout`). Le résultat : l'application `vote-api` répond sur sa route.

<details><summary>Corrigé</summary>

```bash
tkn pipeline start build-and-deploy -p git-url=... -p image=... --use-param-defaults --workspace name=source,volumeClaimTemplateFile=manifests/pvc-template.yaml --showlog
oc get route vote-api
```
Si buildah échoue en `permission denied`, vérifier que le SA `pipeline` est utilisé et que la SCC `pipelines-scc` existe (`oc get scc pipelines-scc`).
</details>

### Lab 9.4 ⭐⭐ — Paramètres, `when` et `finally`
Ajoutez un paramètre `deploy` (true/false) : la tâche de déploiement ne s'exécute que si `true`. Ajoutez un `finally` qui affiche le statut.

<details><summary>Corrigé</summary>

```yaml
- name: deploy
  when: [{input: "$(params.deploy)", operator: in, values: ["true"]}]
finally:
  - name: notify
    taskSpec: {steps: [{name: s, image: registry.access.redhat.com/ubi9/ubi-minimal, script: 'echo statut=$(tasks.status)'}]}
```
</details>

### Lab 9.5 ⭐⭐⭐ — Déclenchement par webhook (Triggers)
Appliquez `02-triggers.yaml`, exposez l'EventListener, envoyez un `curl` simulant un push GitHub, vérifiez qu'un PipelineRun démarre.

<details><summary>Corrigé</summary>

```bash
URL=http://$(oc get route el-vote-listener -o jsonpath='{.spec.host}')
curl -X POST $URL -H 'Content-Type: application/json' -d '{"repository":{"clone_url":"https://github.com/nzembouong18/OpenShift"},"head_commit":{"id":"abc1234"}}'
tkn pipelinerun list
```
En production : valider la signature (intercepteur `github`) et un secret.
</details>

### Lab 9.6 ⭐⭐ — Première Application Argo CD
Créez un dépôt de config (ou utilisez `13-projet-final/manifests` de ce dépôt), déclarez une `Application` avec sync automatique, observez les ressources dans la console Argo CD.

<details><summary>Corrigé</summary>
Voir `03-argocd-application.yaml`. Pour que l'instance par défaut puisse déployer dans `lab-cicd`, labelliser le namespace :
`oc label namespace lab-cicd argocd.argoproj.io/managed-by=openshift-gitops`.
</details>

### Lab 9.7 ⭐⭐⭐ — Dérive et selfHeal
Modifiez manuellement le Deployment (réplicas, image). Constatez `OutOfSync` puis la correction automatique. Désactivez `selfHeal` et comparez.

<details><summary>Corrigé</summary>

```bash
oc scale deploy/vote-api --replicas=5
argocd app get vote-api            # OutOfSync → Synced
argocd app set vote-api --self-heal=false
```
</details>

### Lab 9.8 ⭐⭐⭐ — Environnements avec Kustomize et ApplicationSet
Générez 3 Applications (`dev`, `staging`, `prod`) depuis un seul `ApplicationSet` de type `list`, chacune pointant sur un overlay.

<details><summary>Corrigé</summary>
Voir `04-applicationset.yaml`. Les overlays sont dans `13-projet-final/manifests/overlays/*`.
</details>

### Lab 9.9 ⭐⭐⭐⭐ — Boucle complète CI → GitOps
Le pipeline Tekton, après build, modifie le tag d'image dans le dépôt de config (`kustomize edit set image`) et pousse un commit ; Argo CD déploie. Ajoutez un scan (`trivy`/ACS) bloquant et une signature `cosign`.

<details><summary>Corrigé</summary>
Étapes : Task `git-clone` (config repo) → `kustomize edit set image vote-api=$(params.image)@$(tasks.build.results.IMAGE_DIGEST)` → `git commit/push` avec un SA/secret dédié (deploy key en écriture sur le dépôt de config **seulement**) → Argo CD sync. Toujours déployer par **digest**. Chains signe automatiquement si activé : `oc patch tektonconfig config --type=merge -p '{"spec":{"chain":{"artifacts.taskrun.format":"slsa/v1"}}}'`.
</details>

### Lab 9.10 ⭐⭐⭐⭐ — Progressive delivery (Rollouts)
Installez Argo Rollouts (Operator communautaire ou Helm) et remplacez le Deployment par un `Rollout` canary 20 % → 50 % → 100 % avec pause et analyse.

<details><summary>Corrigé</summary>
`Rollout` `strategy.canary.steps: [{setWeight: 20}, {pause: {duration: 60s}}, {setWeight: 50}, {pause: {}}]`, `trafficRouting.openshift`/ou Route avec backends pondérés. `kubectl argo rollouts get rollout vote-api -w`.
</details>

## 4. Quiz
1. Pourquoi GitOps est dit « pull » ? → l'agent dans le cluster tire l'état désiré depuis Git.
2. Que fait `selfHeal` ? → écrase les modifications manuelles pour revenir à l'état Git.
3. Rôle de `finally` ? → tâches toujours exécutées (nettoyage, notification).
4. Différence Pipeline / PipelineRun ? → définition vs exécution.
5. Comment promouvoir d'un environnement à l'autre ? → PR sur l'overlay / même digest d'image.

Nettoyage : `oc delete project lab-cicd` ; `oc delete application vote-api -n openshift-gitops`

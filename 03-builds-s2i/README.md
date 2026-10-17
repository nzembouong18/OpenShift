# Module 03 — Builds, ImageStreams et Source-to-Image

⏱ 3 h 30 · 🟢🟡

## Objectifs
- Construire des images **dans** le cluster (S2I, Docker/Containerfile, binaire)
- Comprendre les **ImageStreams** et les déclencheurs (triggers)
- Utiliser le registre interne, promouvoir une image entre projets
- Découvrir **Builds for OpenShift (Shipwright / Builds v2)**

## 1. Cours

### 1.1 Pourquoi construire dans le cluster ?
Reproductibilité, sécurité (builds non privilégiés, images de base maintenues), automatisation des mises à jour (une image de base corrigée → rebuild → redéploiement automatique). Les builds s'exécutent dans des **Pods de build** (`<bc>-<n>-build`) ; l'image produite est poussée dans le **registre interne** (`image-registry.openshift-image-registry.svc:5000`).

### 1.2 Stratégies de build (`BuildConfig.spec.strategy`)
| Stratégie | Entrée | Particularité |
|---|---|---|
| **Source (S2I)** | code source + image *builder* | pas de Dockerfile ; scripts `assemble`/`run` du builder |
| **Docker** | `Dockerfile`/`Containerfile` dans le dépôt | utilise Buildah ; rootless/user namespaces |
| **Custom** | image de build personnalisée | cas rares, privilèges élevés |
| **Pipeline** (Jenkins) | *obsolète* | remplacé par Tekton (module 09) |

### 1.3 Source-to-Image (S2I)
```
 code source ──► [ image builder ]  assemble  ──► image applicative (builder + code compilé)
                  (ubi9/python-312)   run        démarrage via script run
```
Avantages : développeurs sans Dockerfile, images de base **gouvernées** par la plateforme, cache incrémental. Builders standards (ImageStreams du projet `openshift`) : `python`, `nodejs`, `java`/`openjdk`, `dotnet`, `golang`, `php`, `ruby`, `perl`, `httpd`, `nginx`. Variables d'environnement de build via `--env` ou `spec.strategy.sourceStrategy.env` ; fichier `.s2i/environment` dans le dépôt.

### 1.4 ImageStreams
Un `ImageStream` est un **pointeur nommé** vers des images (tags). Il n'héberge pas les couches par défaut : il référence (`spec.tags[].from`) ou suit les images poussées dans le registre interne.

| Concept | Rôle |
|---|---|
| `ImageStream` | `monapp` : ensemble de tags |
| `ImageStreamTag` | `monapp:latest` → un digest précis |
| `importPolicy.scheduled` | ré-importe périodiquement un tag externe (CVE de l'image de base) |
| `lookupPolicy.local` | permet à un Pod de référencer simplement `monapp:latest` |
| `referencePolicy: Local` | tire via le registre interne (cache) |

Déclencheurs (**triggers**) : un changement de l'ImageStream peut lancer un build (`triggers.imageChange`) ou redéployer un Deployment (annotation `image.openshift.io/triggers`). Sans cela, un `ImageStreamTag` mis à jour ne change **pas** le Pod.

### 1.5 Le cycle d'un build
1. `oc start-build` / webhook (GitHub, GitLab, Bitbucket, générique) / changement d'image de base / changement de config.
2. Le Pod de build clone le dépôt, exécute S2I ou Buildah.
3. L'image est poussée vers `ImageStream` (`output.to`).
4. Le trigger redéploie l'application.

Webhooks : `oc describe bc/monapp | grep -i webhook` — URL à coller dans GitHub. Politique : `runPolicy: Serial` (défaut), `SerialLatestOnly`, `Parallel`.

### 1.6 Registre interne
- Accès interne : `image-registry.openshift-image-registry.svc:5000/<projet>/<is>:<tag>`.
- Accès externe : exposer une route (`oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge -p '{"spec":{"defaultRoute":true}}'`).
- Push/pull : `podman login -u $(oc whoami) -p $(oc whoami -t) $(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')`.
- Partager entre projets : `oc policy add-role-to-user system:image-puller system:serviceaccount:<ns-dest>:default -n <ns-source>`.
- Stockage du registre : PVC RWX recommandé en production (ou S3/objet). CRC : `emptyDir`/local.

### 1.7 Promotion entre environnements
Ne reconstruisez pas pour chaque environnement : **promouvez** le même digest.
```bash
oc tag lab-builds/vote-api:latest lab-prod/vote-api:1.0.0         # copie la référence
oc tag --alias=true ...                                           # alias
skopeo copy docker://reg1/img@sha256:... docker://reg2/img:1.0.0  # entre registres
```

### 1.8 Builds for OpenShift (Shipwright, « Builds v2 »)
Opérateur **Builds for Red Hat OpenShift** basé sur le projet CNCF Shipwright. Il remplace progressivement les `BuildConfig` :
- `ClusterBuildStrategy` (buildah, s2i, buildpacks, kaniko…), `Build` (définition), `BuildRun` (exécution).
- Intégration Tekton (exécute les BuildRuns), API déclarative portable, **sécurité renforcée** (build non privilégié, signature possible).
- Les `BuildConfig` restent supportés aujourd'hui ; pour un nouveau projet, évaluer Shipwright ou Tekton + buildah.

### 1.9 Bonnes pratiques
- Images **non-root**, `USER` numérique, ports > 1024 ; répertoires inscriptibles par le groupe 0 (`chgrp -R 0 /app && chmod -R g=u /app`).
- Une application = un ImageStream par composant ; tags sémantiques (`1.4.2`) pour la production, jamais `latest` seul.
- Builds avec ressources limitées (`spec.resources`), `successfulBuildsHistoryLimit`, `failedBuildsHistoryLimit`.
- Secret de pull/push, proxies et CA d'entreprise : `spec.source.sourceSecret`, `build.config.openshift.io/cluster` (`proxy`, `additionalTrustedCA`).
- **Supply chain** : SBOM, signature (cosign / Sigstore), scan (ACS, Quay Clair) : module 07/09.

## 2. 🎬 Démo (45 min)

```bash
oc new-project lab-builds
# S2I en une commande
oc new-app python:3.12-ubi9~https://github.com/sclorg/django-ex --name=django
oc logs -f bc/django
oc get is,bc,build
oc expose svc/django
# Rebuild + trigger
oc start-build django --follow
oc get pods -w                                     # nouveau Pod après le build
# Déclencheurs et webhooks
oc describe bc/django | grep -A3 -i 'triggered\|webhook'
# Build "Docker" binaire (sans git)
oc apply -f manifests/01-buildconfig-docker.yaml
oc start-build hello-bin --from-dir=manifests/app-docker --follow
# Importer une image externe et suivre ses mises à jour
oc import-image ubi-minimal --from=registry.access.redhat.com/ubi9/ubi-minimal --confirm --scheduled=true
```

## 3. 🧪 Labos

> Projet : `lab-builds`

### Lab 3.1 ⭐ — Mon premier build S2I
Déployez `https://github.com/sclorg/nodejs-ex` avec le builder `nodejs`. Exposez, ouvrez la route, relancez le build et observez les Pods.

<details><summary>Corrigé</summary>

```bash
oc new-project lab-builds
oc new-app nodejs~https://github.com/sclorg/nodejs-ex --name=nodeapp
oc logs -f bc/nodeapp ; oc expose svc/nodeapp
oc start-build nodeapp --follow
```
Si `nodejs` n'est pas trouvé : `oc get is -n openshift | grep node` (le tag peut être `nodejs:20-ubi9`).
</details>

### Lab 3.2 ⭐ — Lire les objets générés
Listez ImageStream, BuildConfig, Build, Deployment. Dans quel ImageStream l'image est-elle poussée ? Quel est son digest ?

<details><summary>Corrigé</summary>

```bash
oc get is nodeapp -o yaml | grep -A6 tags
oc get istag nodeapp:latest -o jsonpath='{.image.metadata.name}{"\n"}'
oc get deploy nodeapp -o jsonpath='{.metadata.annotations.image\.openshift\.io/triggers}'
```
</details>

### Lab 3.3 ⭐⭐ — Build « Docker » depuis un Containerfile
Appliquez `manifests/01-buildconfig-docker.yaml` (build depuis le dépôt de la formation, contexte `03-builds-s2i/manifests/app-docker`). Lancez le build, déployez l'image, exposez.

<details><summary>Corrigé</summary>

```bash
oc apply -f manifests/01-buildconfig-docker.yaml
oc start-build hello-docker --follow
oc new-app --image-stream=hello-docker:latest --name=hello-docker
oc expose svc/hello-docker
```
Le Containerfile utilise une image UBI non-root et le port 8080.
</details>

### Lab 3.4 ⭐⭐ — Build binaire
Sans Git, construisez une image à partir d'un répertoire local avec `oc start-build --from-dir`. Utile en développement.

<details><summary>Corrigé</summary>

```bash
oc new-build --name=hello-bin --binary --strategy=docker
oc start-build hello-bin --from-dir=manifests/app-docker --follow
```
</details>

### Lab 3.5 ⭐⭐ — Variables de build et cache
Passez `NPM_MIRROR` ou `PIP_INDEX_URL` (selon langage) en variable d'environnement au build ; observez dans les logs. Vérifiez l'effet de `incremental: true`.

<details><summary>Corrigé</summary>

```bash
oc set env bc/nodeapp NPM_MIRROR=https://registry.npmjs.org
oc patch bc/nodeapp -p '{"spec":{"strategy":{"sourceStrategy":{"incremental":true}}}}'
oc start-build nodeapp --follow | grep -i npm
```
</details>

### Lab 3.6 ⭐⭐ — Webhook et déclenchement automatique
Récupérez l'URL du webhook GitHub, simulez un push avec `curl`, et vérifiez qu'un build démarre.

<details><summary>Corrigé</summary>

```bash
oc describe bc/nodeapp | grep -A1 'Webhook GitHub'
SECRET=$(oc get bc nodeapp -o jsonpath='{.spec.triggers[?(@.type=="GitHub")].github.secret}')
# Si le webhook n'existe pas : oc set triggers bc/nodeapp --from-github
curl -k -X POST -H 'X-GitHub-Event: ping' https://api.<cluster>:6443/apis/build.openshift.io/v1/namespaces/lab-builds/buildconfigs/nodeapp/webhooks/$SECRET/github
```
Un `ping` ne lance pas de build ; envoyer l'événement `push` (en-tête `X-GitHub-Event: push` et un corps JSON minimal avec `ref`).
</details>

### Lab 3.7 ⭐⭐⭐ — Promotion entre projets
Créez `lab-builds-prod`. Promouvez `nodeapp:latest` en `nodeapp:1.0.0` dans ce projet, donnez le droit de pull, déployez-y la version.

<details><summary>Corrigé</summary>

```bash
oc new-project lab-builds-prod
oc policy add-role-to-group system:image-puller system:serviceaccounts:lab-builds-prod -n lab-builds
oc tag lab-builds/nodeapp:latest lab-builds-prod/nodeapp:1.0.0
oc new-app --image-stream=lab-builds-prod/nodeapp:1.0.0 --name=nodeapp -n lab-builds-prod
```
</details>

### Lab 3.8 ⭐⭐⭐ — Déclencheur d'image de base
Importez `ubi9/ubi-minimal` en `--scheduled`, basez un BuildConfig Docker dessus (`FROM`) et prouvez que la modification du tag de l'ImageStream relance un build (`imageChange` trigger).

<details><summary>Corrigé</summary>
Dans le BuildConfig : `triggers: [{type: ImageChange, imageChange: {from: {kind: ImageStreamTag, name: "ubi-minimal:latest"}}}]` et `strategy.dockerStrategy.from` sur le même ImageStreamTag. Simulez avec `oc tag registry.access.redhat.com/ubi9/ubi-minimal:9.4 ubi-minimal:latest`.
</details>

### Lab 3.9 ⭐⭐⭐⭐ — Shipwright 🔑
Installez l'Operator *Builds for Red Hat OpenShift* (ou Shipwright upstream), créez un `Build` avec la `ClusterBuildStrategy` `buildah-shipwright-managed-push`, lancez un `BuildRun` sur le dépôt `13-projet-final/app` et déployez le résultat.

<details><summary>Corrigé</summary>
Voir `manifests/02-shipwright-build.yaml`. Après `oc apply`, `oc get buildrun -w` ; l'image est poussée dans `image-registry.openshift-image-registry.svc:5000/lab-builds/vote-api-sw:latest`. Le nom exact des stratégies dépend de la version : `oc get clusterbuildstrategy`.
</details>

## 4. Quiz
1. Que contient le script S2I `assemble` ? → compilation/installation de l'application dans l'image builder.
2. Un ImageStream stocke-t-il les couches ? → non par défaut : pointeurs (tags → digests).
3. Comment éviter de reconstruire pour la production ? → promouvoir le même digest (`oc tag`).
4. Quelle limite principale d'un Dockerfile d'une image Docker Hub standard ? → tourne en root, incompatible avec UID arbitraire.
5. Que remplace Shipwright ? → les BuildConfig (et la stratégie Pipeline/Jenkins).

Nettoyage : `oc delete project lab-builds lab-builds-prod`

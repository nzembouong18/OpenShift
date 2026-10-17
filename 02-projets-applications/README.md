# Module 02 — Projects et premières applications

⏱ 3 h · 🟢

## Objectifs
- Créer et configurer un **Project** (quotas, limites, rôles, templates)
- Déployer une application de 3 manières : image, source, template
- Utiliser la console Developer (Topology) et les labels `app.kubernetes.io/*`

## 1. Cours

### 1.1 Project = namespace + gouvernance
`oc new-project` crée un namespace, ajoute des annotations (`openshift.io/display-name`, `description`, `requester`, plages `sa.scc.uid-range` / `mcs`), et accorde au créateur le rôle `admin`. Les projets sont créés selon le **template de projet** (personnalisable cluster-wide, voir 1.6).

| Rôle (par projet) | Droits |
|---|---|
| `admin` | tout dans le projet, gère les droits |
| `edit` | crée/modifie les objets, pas de RBAC |
| `view` | lecture seule |
| `basic-user` / `self-provisioner` | niveau cluster : voir son projet / créer des projets |

```bash
oc adm policy add-role-to-user edit alice -n lab-apps
oc adm policy add-role-to-group view equipe-qa -n lab-apps
oc get rolebinding -n lab-apps
```

### 1.2 Trois façons de déployer avec `oc new-app`
| Source | Exemple | Ce qui est créé |
|---|---|---|
| **Image** | `oc new-app --image=quay.io/...` | ImageStream, Deployment, Service |
| **Code source** | `oc new-app https://github.com/sclorg/nodejs-ex` | ImageStream(s), BuildConfig (S2I), Deployment, Service |
| **Template** | `oc new-app --template=postgresql-ephemeral -p ...` | tous les objets du Template |
| **ImageStreamTag** | `oc new-app openshift/python:3.12-ubi9~https://...` | idem source avec builder explicite |

`oc new-app` devine le langage (détection par fichiers : `package.json`, `requirements.txt`, `pom.xml`…). Inspecter sans créer : `--dry-run -o yaml`.

> En 2025, `oc new-app` génère des **Deployments** (plus des DeploymentConfig, dépréciés depuis la 4.14).

### 1.3 Labels et conventions
`oc new-app` pose `app=<nom>` et `app.kubernetes.io/*`. Regroupement visuel dans la Topology : `app.kubernetes.io/part-of=<application>`. Liens entre composants : annotation `app.openshift.io/connects-to`.
```bash
oc label deployment/api app.kubernetes.io/part-of=vote-app
oc annotate deployment/web app.openshift.io/connects-to='[{"apiVersion":"apps/v1","kind":"Deployment","name":"api"}]'
```

### 1.4 Quotas et limites : protéger le cluster
| Objet | Portée | Effet |
|---|---|---|
| `ResourceQuota` | projet | plafonne CPU/mémoire/objets/stockage totaux |
| `LimitRange` | projet | valeurs par défaut et min/max **par conteneur/Pod** |
| `ClusterResourceQuota` | plusieurs projets (par label/annotation) | plafond global par équipe/utilisateur |
Si un quota de calcul existe, tout Pod **doit** déclarer requests/limits (ou hériter d'un `LimitRange`) sinon il est refusé.

### 1.5 Templates (les « charts » d'OpenShift)
Un `Template` est une liste d'objets avec des `parameters` (`${NOM}`). `oc process -f tpl.yaml -p NAME=x | oc apply -f -`. Les templates globaux sont dans le projet `openshift` (`oc get templates -n openshift`). Aujourd'hui : Helm et Kustomize sont préférés pour de nouvelles applications (module 09), les Templates restent partout dans l'existant.

### 1.6 Gouvernance de la création de projets (🔑)
- **Template de projet** : `oc adm create-bootstrap-project-template -o yaml` → ajoutez quota/LimitRange/NetworkPolicy → `oc create -n openshift-config -f ...` → `oc edit projects.config.openshift.io cluster` (`spec.projectRequestTemplate.name`).
- **Retirer l'auto-provisionnement** : `oc adm policy remove-cluster-role-from-group self-provisioner system:authenticated:oauth`.
- **Message de demande** : `spec.projectRequestMessage`.

### 1.7 Console Developer
Vue **Topology** : chaque Deployment est un nœud ; icône de build, route, statut des Pods ; ajout « From Git / Container image / Samples / Operator Backed ». Idéal pour les débutants ; en production on reste en YAML + GitOps.

## 2. 🎬 Démo (35 min)

```bash
oc new-project lab-apps --display-name="Lab apps" --description="Module 02"
# (1) depuis une image
oc new-app --image=docker.io/openshift/hello-openshift --name=hello
oc expose svc/hello && oc get route
# (2) depuis le code source (S2I)
oc new-app https://github.com/sclorg/nodejs-ex --name=nodeapp
oc logs -f buildconfig/nodeapp
oc expose svc/nodeapp && oc status
# (3) depuis un template
oc get templates -n openshift | head
oc new-app --template=openshift/httpd-example -p NAME=httpd-demo   # ou: oc process ...
# Inspecter ce qui a été généré
oc new-app --image=docker.io/openshift/hello-openshift --name=test --dry-run=client -o yaml | head -60
# Quotas
oc apply -f manifests/01-quota-limitrange.yaml
oc describe quota ; oc describe limitrange
oc scale deploy/hello --replicas=10 ; oc get events | tail
```

## 3. 🧪 Labos

> Projet : `lab-apps` (Sandbox : utilisez votre projet `<user>-dev`)

### Lab 2.1 ⭐ — Mon premier projet
Créez `lab-apps`, déployez `hello-openshift`, exposez-le, testez avec `curl`. Supprimez le Pod et vérifiez le retour du service.

<details><summary>Corrigé</summary>

```bash
oc new-project lab-apps
oc new-app --image=docker.io/openshift/hello-openshift --name=hello
oc expose svc/hello
curl -s http://$(oc get route hello -o jsonpath='{.spec.host}')
oc delete pod -l deployment=hello
```
</details>

### Lab 2.2 ⭐ — Console Developer
Ajoutez via la console (+Add → Import from Git) l'application `https://github.com/sclorg/django-ex`. Repérez la Topology, le build en cours, l'URL de la route.

<details><summary>Corrigé</summary>
Choisir le builder Python, cocher *Create a route*. Le pastille ronde de la Topology ouvre l'URL ; le petit icône de build mène aux logs.
</details>

### Lab 2.3 ⭐⭐ — Gérer les accès
Donnez le rôle `view` à un second utilisateur, `edit` à un autre. Vérifiez avec `oc auth can-i` et `oc policy who-can`.

<details><summary>Corrigé</summary>

```bash
oc adm policy add-role-to-user view bob -n lab-apps
oc adm policy add-role-to-user edit carol -n lab-apps
oc auth can-i create deployment -n lab-apps --as=bob     # no
oc auth can-i create deployment -n lab-apps --as=carol   # yes
oc policy who-can delete pods -n lab-apps
```
(`--as` nécessite le droit d'impersonation, donc admin de cluster ou rôle équivalent.)
</details>

### Lab 2.4 ⭐⭐ — Quota et LimitRange
Appliquez `manifests/01-quota-limitrange.yaml`. Déployez une application sans requests/limits : que se passe-t-il ? Tentez un 11ᵉ Pod.

<details><summary>Corrigé</summary>
Avec un `LimitRange`, les Pods reçoivent des valeurs par défaut (`defaultRequest`/`default`) ; sans LimitRange et avec quota CPU/mémoire, la création du Pod est refusée (`must specify limits.cpu`). Le 11ᵉ Pod est refusé par `pods: "10"`. Les erreurs apparaissent dans `oc get events` et dans `oc describe rs/<nom>`, pas dans `oc get pods`.
</details>

### Lab 2.5 ⭐⭐ — Template paramétré
Traitez `manifests/02-template-webapp.yaml` : `oc process -f ... -p NAME=site1 -p REPLICAS=2 | oc apply -f -`. Comparez avec `oc new-app -f ... -p`.

<details><summary>Corrigé</summary>

```bash
oc process -f manifests/02-template-webapp.yaml -p NAME=site1 -p REPLICAS=2 | oc apply -f -
oc get all -l app=site1
oc process --parameters -f manifests/02-template-webapp.yaml
```
</details>

### Lab 2.6 ⭐⭐⭐ — Template de projet 🔑
Configurez le cluster pour qu'un nouveau projet reçoive automatiquement un `ResourceQuota`, un `LimitRange` et une NetworkPolicy « default-deny ». Vérifiez avec un nouveau projet.

<details><summary>Corrigé</summary>

```bash
oc adm create-bootstrap-project-template -o yaml > /tmp/project-template.yaml
# ajouter sous objects: ResourceQuota, LimitRange, NetworkPolicy (voir manifests/03-fragment-project-template.yaml)
oc create -f /tmp/project-template.yaml -n openshift-config
oc patch projects.config.openshift.io cluster --type=merge -p '{"spec":{"projectRequestTemplate":{"name":"project-request"}}}'
oc new-project test-tpl && oc get quota,limitrange,networkpolicy
```
Attendre le redéploiement de l'apiserver (quelques minutes). Attention : une NetworkPolicy deny-all bloque aussi le Router → ajouter `allow-from-openshift-ingress` (voir module 05).
</details>

### Lab 2.7 ⭐⭐⭐⭐ — Self-service encadré 🔑
Retirez le droit `self-provisioner` aux utilisateurs authentifiés, créez un groupe `plateforme` autorisé à créer des projets, et un message personnalisé de demande de projet.

<details><summary>Corrigé</summary>

```bash
oc adm policy remove-cluster-role-from-group self-provisioner system:authenticated:oauth
oc adm groups new plateforme alice
oc adm policy add-cluster-role-to-group self-provisioner plateforme
oc patch projects.config.openshift.io cluster --type=merge -p '{"spec":{"projectRequestMessage":"Contactez la plateforme : demande via le portail ITSM"}}'
```
Si `oc adm policy remove...` ne persiste pas (le ClusterRoleBinding est géré), appliquez `oc patch clusterrolebinding.rbac self-provisioners -p '{"metadata":{"annotations":{"rbac.authorization.kubernetes.io/autoupdate":"false"}}}'`.
</details>

## 4. Quiz
1. Que crée `oc new-app <url-git>` en plus du Deployment ? → ImageStream, BuildConfig, Service.
2. Quel rôle permet de gérer les droits dans un projet ? → `admin`.
3. Différence ResourceQuota / LimitRange ? → total du projet vs valeurs/limites par conteneur ou Pod.
4. Comment générer le YAML d'un `new-app` sans créer ? → `--dry-run=client -o yaml`.
5. Pourquoi ne pas déployer dans `openshift-*` ? → réservés à la plateforme, risque de casser le cluster/supportabilité.

Nettoyage : `oc delete project lab-apps`

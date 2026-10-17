# Module 00 — Mise en place de l'environnement

⏱ 1 h · 🟢 Débutant

## Objectifs
- Choisir l'environnement adapté (CRC, OKD, Developer Sandbox, cluster cloud)
- Installer `oc` et se connecter (CLI **et** console web)
- Configurer le shell (autocomplétion, alias, prompt de projet)

## 1. Cours : choisir son OpenShift

| Option | Usage | Droits | Ressources | Remarque |
|---|---|---|---|---|
| **OpenShift Local (CRC)** | Poste de dev, labs | `kubeadmin` | 10,5 Go RAM min. (16 recommandé), 4+ vCPU, 35+ Go | VM unique (Linux KVM, macOS, Windows Hyper-V). Compte Red Hat gratuit pour le *pull secret* |
| **Developer Sandbox** | Découverte, dev | utilisateur | aucune (SaaS) | Gratuit, 2 projects, quotas, 🔑 impossible |
| **OKD (SNO)** | 100 % open source | cluster-admin | 16 Go+ | Base communautaire d'OpenShift (Fedora CoreOS, images `quay.io/openshift/okd`) |
| **OCP sur cloud (IPI)** | Production, formation de groupe | cluster-admin | 3 CP + 2+ workers | `openshift-install create cluster` |
| **ROSA / ARO / OSD** | Production managée | admin délégué | — | Control plane géré par Red Hat/Microsoft |
| **Single Node OpenShift** | Edge, labs | cluster-admin | 8 vCPU / 32 Go | Un nœud = control plane + worker |

### Les pré-requis CRC
1. Créer un compte sur <https://console.redhat.com/openshift/create/local> et télécharger `crc` + le **pull secret** (`pull-secret.txt`).
2. Machine avec virtualisation : `egrep -c '(vmx|svm)' /proc/cpuinfo` > 0 sur Linux. Dans une VM : *nested virtualization*.
3. `crc setup` configure l'hyperviseur, le réseau (DNS `*.crc.testing`, `*.apps-crc.testing`).
4. `crc start -p pull-secret.txt` : 10 à 15 min la première fois. Le cluster expose `https://api.crc.testing:6443` et la console `https://console-openshift-console.apps-crc.testing`.

> Un cluster CRC n'est **pas** destiné à la production et ne se met pas à jour comme un OCP classique (il faut une nouvelle version de `crc`). Pour les modules 11-12, utilisez un cluster formateur ou OKD.

### Le Developer Sandbox
Connexion via <https://developers.redhat.com/developer-sandbox>. Depuis la console : menu utilisateur → *Copy login command* → jeton. Vous disposez de deux projets (`<user>-dev`, `<user>-stage`) : **adaptez les noms de projets** des labos (`oc project <user>-dev`) ; `oc new-project` y est restreint.

### La CLI `oc`
`oc` = `kubectl` + des commandes spécifiques OpenShift (`new-app`, `new-build`, `start-build`, `expose`, `adm`, `login`, `project`, `rollout`, `debug`, `rsh`, `import-image`, `policy`…). Une seule version de `oc` doit être proche de celle du cluster (écart toléré : ±1 mineure). Elle embarque `kubectl` : `oc get` ≡ `kubectl get`.

### Authentification
| Méthode | Commande |
|---|---|
| Identifiants | `oc login -u <user> -p <pwd> https://api...:6443` |
| Jeton (copié depuis la console) | `oc login --token=sha256~xxx --server=https://api...:6443` |
| Certificat admin (installation) | `export KUBECONFIG=<dir>/auth/kubeconfig` |
Un jeton OAuth expire (24 h par défaut). `oc whoami -t` l'affiche, `oc whoami --show-server`, `oc whoami --show-console`.

## 2. 🎬 Démo (20 min)

```bash
./scripts/install-tools.sh
crc version && crc setup && crc start -p ~/pull-secret.txt
eval $(crc oc-env)                       # ajoute oc au PATH
crc console --credentials                # kubeadmin / developer
oc login -u developer -p developer https://api.crc.testing:6443
oc whoami ; oc version ; oc get nodes    # developer : Forbidden → normal
oc login -u kubeadmin -p <pwd> ; oc get nodes ; oc get co
oc whoami --show-console                 # ouvrir la console, comparer vues Administrator / Developer
```

Configurer le shell :
```bash
source <(oc completion bash)             # ou zsh
echo 'source <(oc completion bash)' >> ~/.bashrc
alias k=oc ; complete -o default -F __start_oc k
alias ocp='oc project'
```
Prompt avec le projet courant (`oc project` en lecture seule, sans appel réseau) :
```bash
export PS1='[\u@\h \W $(oc project -q 2>/dev/null)]\$ '
```

## 3. 🧪 Labos

### Lab 0.1 ⭐ — Installer et se connecter
1. Exécutez `scripts/install-tools.sh`, puis `scripts/check-env.sh`.
2. Démarrez CRC (ou connectez-vous au Sandbox / cluster formateur).
3. Connectez-vous en CLI **et** ouvrez la console web.

<details><summary>Corrigé</summary>

```bash
./00-setup/scripts/install-tools.sh && ./00-setup/scripts/check-env.sh
oc login -u developer -p developer https://api.crc.testing:6443
oc whoami --show-console
```
</details>

### Lab 0.2 ⭐ — Explorer la console
Repérez : la perspective **Administrator** vs **Developer** (menu en haut à gauche), la page *Home → Overview*, *Operators → OperatorHub*, *Observe → Dashboards*, *Workloads → Pods*, le bouton **`>_`** (terminal web) et *Copy login command*.

<details><summary>Corrigé</summary>
Aucun piège : l'objectif est de savoir où chercher. La perspective Developer propose *Topology* (vue graphique des applications), *Builds*, *Pipelines*, *Observe* limités au projet courant.
</details>

### Lab 0.3 ⭐⭐ — Premier projet et première application
```bash
oc new-project lab-setup
oc new-app --image=docker.io/openshift/hello-openshift --name=hello
oc expose svc/hello
oc get route hello
curl http://$(oc get route hello -o jsonpath='{.spec.host}')
```
Expliquez chaque objet créé (`oc get all`). Quel est le nom d'hôte de la route et d'où vient-il ?

<details><summary>Corrigé</summary>
`oc new-app` crée un `ImageStream` (suivi de l'image), un `Deployment`, un `Service`. `oc expose` crée une `Route` dont l'hôte est `<service>-<projet>.<domaine-apps>` (domaine défini par l'IngressController par défaut, ex. `apps-crc.testing`). Note : `hello-openshift` écoute en 8080/8888, utilisateur non root → compatible avec la SCC `restricted-v2`.
</details>

### Lab 0.4 ⭐⭐ — Diagnostic d'environnement 🔑
Avec `kubeadmin`, vérifiez que tous les *Cluster Operators* sont `Available=True`, qu'aucun nœud n'est `NotReady`, que le registre interne est présent.

<details><summary>Corrigé</summary>

```bash
oc get co | awk 'NR==1 || $3!="True" || $4!="False" || $5!="False"'
oc get nodes
oc get pods -n openshift-image-registry
oc get clusterversion
```
Des Operators `Progressing` juste après le démarrage de CRC sont normaux pendant quelques minutes.
</details>

## 4. Quiz
1. Quelle commande donne la version du cluster ? → `oc get clusterversion` (ou `oc version`).
2. Pourquoi le Sandbox n'est-il pas adapté au module 11 ? → pas de droits cluster-admin.
3. Où se trouve le domaine par défaut des routes ? → `oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'`.
4. Différence `oc` / `kubectl` ? → `oc` ajoute authentification, projects, builds, `adm`, etc. ; compatible avec les commandes kubectl.
5. Que contient le *pull secret* ? → identifiants pour `registry.redhat.io` / `quay.io` des images du produit.

Nettoyage : `oc delete project lab-setup`

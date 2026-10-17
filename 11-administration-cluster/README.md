# Module 11 — Administration du cluster

⏱ 5 h · 🔴

> Ce module suppose un cluster où vous êtes **cluster-admin** (OKD/SNO, cluster formateur, OCP cloud). Sur CRC, les manipulations de MachineSet, mise à jour et redémarrage de nœuds sont à **observer en démo uniquement**.

## Objectifs
- Choisir une méthode d'installation et une topologie
- Gérer l'OS des nœuds (`MachineConfig`, `MachineConfigPool`) et l'infrastructure (`MachineSet`, autoscaling)
- Piloter les mises à jour (canaux, `oc adm upgrade`, stratégies de rollout)
- Sauvegarder / restaurer etcd, gérer capacité, maintenance, incidents

## 1. Cours

### 1.1 Méthodes d'installation
| Méthode | Description | Quand |
|---|---|---|
| **IPI** (Installer-Provisioned) | `openshift-install create cluster` crée l'infra (AWS, Azure, GCP, vSphere, OpenStack, bare metal) | cloud, automatisation maximale |
| **UPI** (User-Provisioned) | vous fournissez réseau, LB, DNS, machines | contraintes spécifiques |
| **Assisted Installer** | service web (console.redhat.com) + ISO de découverte | bare metal, simplifié |
| **Agent-based Installer** | ISO autonome, pour environnements déconnectés | air-gap |
| **SNO / compact / HCP** | topologies particulières | edge / petite taille / multi-clusters |
| **ROSA / ARO / OSD / OKE** | managé | délégation de l'exploitation |
Fichier `install-config.yaml` : `baseDomain`, `metadata.name`, `networking` (clusterNetwork, serviceNetwork, machineNetwork, `OVNKubernetes`), `compute`/`controlPlane`, `platform`, `pullSecret`, `sshKey`, `fips`, `capabilities`. **Réseau et domaine ne se changent pas après installation** : les dimensionner avec soin (`10.128.0.0/14`, `172.30.0.0/16` par défaut).
Artefacts : `openshift-install create manifests|ignition-configs|cluster`, `auth/kubeconfig`, `auth/kubeadmin-password`, `.openshift_install.log`.
Pré-requis réseau : DNS `api.<cluster>.<domaine>`, `api-int`, wildcard `*.apps`, NTP, LB API (6443, 22623) et Ingress (80/443).

### 1.2 Topologies et dimensionnement
| Topologie | Nœuds | Usage |
|---|---|---|
| Standard | 3 CP + ≥ 2 workers (+ infra) | production |
| Compact | 3 nœuds CP+worker | petites tailles, edge |
| **SNO** | 1 | edge, labs |
| Two-node (arbitre) | 2 + arbitre | edge (selon version) |
| **Hosted Control Planes** | CP hébergé dans un cluster de gestion | flotte de clusters |
Dimensionnement CP (indicatif) : jusqu’à 25 workers → 4 vCPU/16 Go ; 100 → 8 vCPU/32 Go ; 250 → 16 vCPU/64 Go (+ SSD rapides pour etcd : p99 fsync < 10 ms). Un nœud accepte par défaut **250 Pods** (`maxPods`, ajustable via `KubeletConfig`).
**Nœuds infra** : router, registre, monitoring, logging ne comptent pas dans les abonnements worker. Création : MachineSet avec label `node-role.kubernetes.io/infra` + taint, puis déplacer les composants (`nodePlacement`).

### 1.3 Machine API (infrastructure pilotée par Kubernetes)
| Objet | Rôle |
|---|---|
| `Machine` | une VM/serveur décrite en YAML |
| `MachineSet` | N Machines identiques (comme un ReplicaSet) |
| `MachineHealthCheck` | remplace automatiquement un nœud `NotReady` |
| `MachineAutoscaler` + `ClusterAutoscaler` | scale-out/in des MachineSets selon les Pods `Pending` |
| `ControlPlaneMachineSet` | gère les 3 machines du control plane (rolling replace) |
```bash
oc get machinesets -n openshift-machine-api
oc scale machineset <ms> -n openshift-machine-api --replicas=3
oc get machines -n openshift-machine-api -o wide
```
Sur bare metal : **Bare Metal Operator** + `BareMetalHost` (provisionnement Redfish/IPMI/Metal³).

### 1.4 Machine Config Operator (MCO)
```
MachineConfig (YAML Ignition : fichiers, unités systemd, kargs, extensions)
        ▼ fusion
Rendered MachineConfig (par pool) ──► MachineConfigPool (master / worker / infra / custom)
        ▼ rolling : cordon + drain + rpm-ostree + reboot, un nœud (maxUnavailable) à la fois
```
Exemple : désactiver SELinux n'est **pas** supporté ; typiquement : NTP/chrony, sysctl, kernel args, fichiers (`/etc/...`), certificats CA, kubelet (`KubeletConfig`), CRI-O (`ContainerRuntimeConfig`), extensions (usbguard, kernel-devel).
- Nommage : `NN-<pool>-<objet>` (`99-worker-chrony`) ; le label `machineconfiguration.openshift.io/role: worker` rattache au pool.
- **Pause** d’un pool : `oc patch mcp/worker --type=merge -p '{"spec":{"paused":true}}'` (utile avant une mise à jour pour la maîtriser).
- `maxUnavailable` : vitesse du rolling reboot (`spec.maxUnavailable` du pool, défaut 1).
- Un nœud modifié à la main (SSH) → `Degraded` : le MCO attend l’état rendu (`oc describe node` → `machineconfiguration.openshift.io/state`).

### 1.5 Mises à jour (`ClusterVersion`)
Canaux : `stable-4.N`, `fast-4.N`, `candidate-4.N`, `eus-4.N` (EUS pour les versions paires, avec chemin accéléré EUS→EUS). Graphe de mise à jour (OSUS, Cincinnati). 
```bash
oc get clusterversion
oc adm upgrade                               # versions disponibles et recommandées
oc adm upgrade channel stable-4.17
oc adm upgrade --to=4.17.12                  # lancer
oc adm upgrade --to-latest
watch oc get co ; oc get mcp ; oc get nodes
```
Séquence : CVO → Cluster Operators (control plane) → MCO (CP, puis pools workers). **Avant** : sauvegarde etcd, `oc get co` sain, Operators OLM compatibles (`Upgradeable`), APIs dépréciées (`oc get apirequestcounts`), capacité pour drainer, PDB réalistes, fenêtre de maintenance. **Mise à jour des Operators OLM** : avant ou après selon leurs annotations de compatibilité. 
Stratégies pour pools workers : pause du pool `worker`, mise à jour du CP, puis dépause **par lots** (pools personnalisés/canary) ; `MachineConfigPool.spec.maxUnavailable` ; mise à jour **en place** vs **blue/green** (nouveau MachineSet + drain des anciens).
**Environnements déconnectés** : miroir de la release (`oc-mirror`), `ImageContentSourcePolicy` / `ImageDigestMirrorSet`, **OpenShift Update Service** local.
`oc adm upgrade --allow-explicit-upgrade --to-image=<digest>` pour une release hors graphe (déconseillé).

### 1.6 etcd : sauvegarde, restauration, santé
- etcd = base de données de l’état du cluster : **perte = perte du cluster**. 3 membres (quorum 2).
- Sauvegarde (depuis un nœud CP) : 
```bash
oc debug node/<cp> -- chroot /host /usr/local/bin/cluster-backup.sh /home/core/assets/backup
```
Produit `snapshot_*.db` + `static_kuberesources_*.tar.gz`. **Copier hors du cluster**, chiffrer, automatiser (CronJob avec SA privilégié ou outil externe), tester la restauration.
- Restauration : `cluster-restore.sh` sur un CP « récupérateur » après arrêt des static pods des autres CP (procédure documentée « Restoring to a previous cluster state ») ; cas particulier : remplacement d’un seul membre défectueux (`oc get etcd -o=jsonpath='{.items[0].status.conditions}'`, supprimer le `Machine`).
- Santé : `oc get etcd cluster -o yaml`, `oc exec -n openshift-etcd etcd-<cp> -c etcdctl -- etcdctl endpoint status -w table`, alerte `etcdHighFsyncDurations`. Défragmentation automatique par l’Operator ; `etcd` ne doit pas dépasser son quota (8 Gio par défaut).
- Rotation des certificats/expiration : les certificats du CP se renouvellent seuls ; un cluster éteint plusieurs jours (CRC, labs) peut nécessiter l’approbation des CSR : `oc get csr` ; `oc get csr -o name | xargs oc adm certificate approve`.

### 1.7 Maintenance des nœuds
```bash
oc adm cordon <node>                       # plus de nouveaux Pods
oc adm drain <node> --ignore-daemonsets --delete-emptydir-data --force --grace-period=60
# ... maintenance ...
oc adm uncordon <node>
oc debug node/<node> -- chroot /host journalctl -u kubelet --since "1 hour ago"
oc adm node-logs <node> -u crio
oc adm top node
```
Le drain respecte les **PDB** : un PDB trop strict (`minAvailable` = replicas) bloque la maintenance. Étiquettes/taints : `oc label node`, `oc adm taint nodes`. Un nœud `NotReady` : kubelet, réseau, disque plein (`DiskPressure`), CSR en attente.

### 1.8 Capacité et optimisation
- **Overcommit** : requests vs limits ; `ClusterResourceOverride` Operator.
- **Descheduler** (Kube Descheduler Operator) : rééquilibre les Pods.
- **Quotas** : `ClusterResourceQuota`, `LimitRange` par défaut (template de projet, module 02).
- **Profils de planification** (`Scheduler` CR : `LowNodeUtilization`, `HighNodeUtilization`).
- **Tuning** : Node Tuning Operator (profils `tuned`), Performance Addon (`PerformanceProfile` : CPU isolés, hugepages, RT) pour télécom/latence.
- **Ressources système réservées** : `KubeletConfig` (`systemReserved`, `autoSizingReserved: true`).
- **Garbage collection** : images (`imageGCHighThresholdPercent`), pruning (`oc adm prune builds|deployments|images`) ; `ImagePruner` CR automatique.

### 1.9 Proxy, CA, registres
`proxy/cluster` (httpProxy, httpsProxy, noProxy, `trustedCA`) ; `image.config.openshift.io/cluster` (registres autorisés/bloqués, `additionalTrustedCA`) ; miroirs : `ImageDigestMirrorSet`, `ImageTagMirrorSet` (appliquent un redémarrage progressif via MCO).

### 1.10 Administration quotidienne : checklist
| Fréquence | Actions |
|---|---|
| Continu | alertes critiques, `Watchdog`, capacité, expiration certificats |
| Quotidien | `oc get co`, `oc get nodes`, `oc get mcp`, `oc get csr`, backup etcd |
| Hebdo | revue des mises à jour disponibles, vulnérabilités, quotas, PVC proches du plein |
| Mensuel/trimestriel | upgrade mineure (stable), test de restauration, exercice de panne |
| Annuel | audit RBAC/SCC, renouvellement IdP/CA, revue de topologie |

## 2. 🎬 Démo (60 min)

```bash
# État de santé
oc get clusterversion,co,nodes,mcp
# MachineSets (cloud) ou BareMetalHosts
oc get machineset,machine -n openshift-machine-api
# MachineConfig : NTP ou sysctl sur un pool dédié
oc apply -f manifests/01-mc-sysctl.yaml ; oc get mcp -w            # UPDATING → UPDATED (reboot progressif)
oc debug node/<w> -- chroot /host sysctl vm.max_map_count
# Pool personnalisé « infra »
oc apply -f manifests/02-mcp-infra.yaml
# Drain / PDB
oc adm drain <w> --ignore-daemonsets --delete-emptydir-data ; oc adm uncordon <w>
# Mise à jour : lecture seule en formation
oc adm upgrade
# etcd
oc debug node/<cp> -- chroot /host /usr/local/bin/cluster-backup.sh /home/core/assets/backup
oc get etcd cluster -o jsonpath='{.status.conditions[?(@.type=="EtcdMembersAvailable")].message}{"\n"}'
```

## 3. 🧪 Labos

### Lab 11.1 ⭐ — Bilan de santé 🔑
Rédigez un script `health.sh` qui échoue si : un ClusterOperator n’est pas `Available`/est `Degraded`, un nœud n’est pas `Ready`, un pool MCP n’est pas `Updated`, une CSR est en attente, une alerte `critical` est active.

<details><summary>Corrigé</summary>
Voir `manifests/health.sh`.

```bash
bash manifests/health.sh && echo "Cluster sain"
```
</details>

### Lab 11.2 ⭐⭐ — Préparer l’installation
Écrivez un `install-config.yaml` (cloud ou bare metal) pour 3 CP + 3 workers, réseau personnalisé, FIPS désactivé. Validez-le avec `openshift-install create manifests`.

<details><summary>Corrigé</summary>
Voir `manifests/install-config.example.yaml`. Les secrets (`pullSecret`, `sshKey`) sont à renseigner : **ne jamais les commiter**. Sauvegardez le fichier avant `create cluster` : l’installateur le consomme.
</details>

### Lab 11.3 ⭐⭐ — Nœuds de rôle « infra »
Créez un pool `infra` et déplacez-y le router et le registre. Vérifiez le placement.

<details><summary>Corrigé</summary>

```bash
oc label node <n> node-role.kubernetes.io/infra=
oc apply -f manifests/02-mcp-infra.yaml
oc patch ingresscontroller/default -n openshift-ingress-operator --type=merge -p '{"spec":{"nodePlacement":{"nodeSelector":{"matchLabels":{"node-role.kubernetes.io/infra":""}},"tolerations":[{"effect":"NoSchedule","key":"node-role.kubernetes.io/infra","value":"reserved"}]}}}'
oc patch configs.imageregistry.operator.openshift.io/cluster --type=merge -p '{"spec":{"nodeSelector":{"node-role.kubernetes.io/infra":""}}}'
oc get pods -n openshift-ingress -o wide
```
</details>

### Lab 11.4 ⭐⭐⭐ — MachineConfig sysctl
Appliquez `01-mc-sysctl.yaml` (`vm.max_map_count=262144`) au pool worker. Observez le rolling reboot, vérifiez la valeur, puis supprimez le MachineConfig et constatez le retour.

<details><summary>Corrigé</summary>

```bash
oc apply -f manifests/01-mc-sysctl.yaml
oc get mcp worker -w          # UPDATING=True puis UPDATED
oc debug node/<w> -- chroot /host sysctl vm.max_map_count
oc delete -f manifests/01-mc-sysctl.yaml
```
Chaque changement = un redémarrage des nœuds : regrouper les modifications (pause du pool, puis dépause).
</details>

### Lab 11.5 ⭐⭐ — KubeletConfig
Augmentez `maxPods` à 400 pour un pool personnalisé et réservez des ressources système.

<details><summary>Corrigé</summary>
Voir `03-kubeletconfig.yaml` : un `KubeletConfig` sélectionne un pool via `machineConfigPoolSelector` (label `custom-kubelet: big-nodes` à poser sur le pool).
</details>

### Lab 11.6 ⭐⭐ — Maintenance d’un nœud
Drainez un worker hébergeant des Pods avec PDB, constatez le blocage si PDB trop strict, corrigez, terminez la maintenance.

<details><summary>Corrigé</summary>

```bash
oc adm drain <w> --ignore-daemonsets --delete-emptydir-data
# "Cannot evict pod as it would violate the pod's disruption budget"
oc patch pdb web -n lab-workloads -p '{"spec":{"minAvailable":1}}'
oc adm uncordon <w>
```
</details>

### Lab 11.7 ⭐⭐⭐ — Sauvegarde etcd automatisée
Sauvegardez etcd à la main puis écrivez un CronJob (SA dédié, `hostPID`, SCC privilégiée sur un projet réservé) qui exécute `cluster-backup.sh` et exporte vers S3.

<details><summary>Corrigé</summary>
Approche recommandée par Red Hat : un CronJob dans `openshift-etcd`-adjacent est **déconseillé** sans contrôle ; préférer un outil externe (ou OADP pour les ressources API) et la commande d’un administrateur. Voir `04-etcd-backup-cronjob.yaml` pour une base à durcir, à tester sur cluster jetable.
</details>

### Lab 11.8 ⭐⭐⭐ — Simulation de mise à jour (lecture) 🔑
Sur un cluster de test : changez de canal, consultez les mises à jour, listez les APIs dépréciées en usage, vérifiez `Upgradeable`, préparez le plan de pause des pools.

<details><summary>Corrigé</summary>

```bash
oc adm upgrade channel stable-4.17
oc adm upgrade
oc get apirequestcounts -o jsonpath='{range .items[?(@.status.removedInRelease!="")]}{.metadata.name}{"\t"}{.status.removedInRelease}{"\n"}{end}'
oc get clusterversion version -o jsonpath='{.status.conditions[?(@.type=="Upgradeable")]}'
oc patch mcp/worker --type=merge -p '{"spec":{"paused":true}}'
```
</details>

### Lab 11.9 ⭐⭐⭐⭐ — Panne de nœud et MachineHealthCheck
Provoquez l’arrêt du kubelet sur un worker (`systemctl stop kubelet` via `oc debug`), observez le passage `NotReady`, la reprogrammation des Pods, et le remplacement automatique par un `MachineHealthCheck`.

<details><summary>Corrigé</summary>
Voir `05-machinehealthcheck.yaml`. Délais : `unhealthyConditions` (`Ready` Unknown 300 s) ; `maxUnhealthy: 40%` empêche les remplacements en cascade. Seulement sur une plateforme avec Machine API (cloud/bare metal).
</details>

### Lab 11.10 ⭐⭐⭐⭐ — Exercice de reprise après sinistre
Documentez et jouez le scénario « perte de 2 control planes sur 3 » : décision, restauration etcd depuis snapshot, réattachement des nœuds, validation.

<details><summary>Corrigé</summary>
Plan type : (1) geler les changements, (2) identifier le CP sain et le snapshot, (3) arrêter les static pods etcd/kube-apiserver sur les autres CP, (4) `cluster-restore.sh` sur le CP de récupération, (5) redémarrer kubelet, (6) recréer/rejoindre les CP, (7) `oc get co`, approuver CSR, (8) vérifier workloads/PVC, (9) post-mortem. À répéter une fois par an.
</details>

## 4. Quiz
1. Quel objet modifie la configuration système d’un nœud ? → `MachineConfig` (via MCO).
2. Comment mettre à jour le cluster ? → `oc adm upgrade` ; le CVO orchestre, le MCO redémarre les nœuds.
3. Que doit-on sauvegarder impérativement ? → etcd (+ ressources via OADP, données persistantes).
4. Pourquoi mettre un pool en pause ? → maîtriser le moment de la mise à jour des workers.
5. Qu’est-ce qui bloque un drain ? → PDB, Pods sans contrôleur, volumes locaux.

Nettoyage : supprimer les MachineConfig/pools de test (`oc delete -f manifests/01-mc-sysctl.yaml` ...) — chaque suppression provoque un rolling reboot.

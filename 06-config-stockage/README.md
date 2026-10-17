# Module 06 — Configuration et stockage

⏱ 3 h 30 · 🟡

## Objectifs
- Externaliser la configuration (ConfigMap, Secret) et la mettre à jour proprement
- Comprendre PV / PVC / StorageClass / CSI sur OpenShift
- Connaître les options de stockage : LVMS, ODF (Ceph), NFS, cloud ; snapshots et clones
- Sauvegarder / restaurer (OADP)

## 1. Cours

### 1.1 ConfigMap et Secret
| | ConfigMap | Secret |
|---|---|---|
| Contenu | configuration non sensible | données sensibles (base64, **non chiffré** par défaut dans la couche objet) |
| Injection | variables d'environnement, fichiers, args | idem |
| Mise à jour | volume : propagé en ~1 min (sauf `subPath`) ; env : redémarrage requis | idem |

Création : `oc create configmap app-cfg --from-literal=K=V --from-file=conf/`, `oc create secret generic db --from-literal=password=...`. Types : `kubernetes.io/basic-auth`, `kubernetes.io/dockerconfigjson` (pull secrets), `kubernetes.io/tls`, `kubernetes.io/ssh-auth`, `kubernetes.io/service-account-token`.

`oc set env deploy/api --from=configmap/app-cfg`, `oc set volume deploy/api --add --name=cfg --type=configmap --configmap-name=app-cfg --mount-path=/etc/app`.

**Redéploiement lors d'un changement de config** : `oc rollout restart deploy/api` ; avec Kustomize `configMapGenerator` (hash dans le nom) ; avec Helm `checksum/config`. Operator **Reloader** (Stakater) pour l'automatiser.

### 1.2 Sécuriser les secrets
- **Chiffrement etcd** (`apiserver/cluster` → `spec.encryption.type: aescbc` ou `aesgcm`) : 🔑, à activer sur tout cluster de production.
- Ne jamais committer de Secret en clair → **Sealed Secrets**, **SOPS**, **External Secrets Operator** (Vault, AWS SM, Azure KV), **Secrets Store CSI Driver** (montage éphémère).
- RBAC strict sur `secrets` (`get`/`list`/`watch` = lecture de toutes les valeurs).
- Rotation et durée de vie courte ; éviter les variables d'environnement (visibles par `oc debug`, `/proc`) au profit de fichiers.

### 1.3 Modèle de stockage
```
 Pod ──► PVC (demande) ──► PV (volume) ──► backend (disque, Ceph, NFS, EBS…)
                 └─ StorageClass (provisionnement dynamique via un pilote CSI)
```
| Mode d'accès | Sens | Support typique |
|---|---|---|
| `ReadWriteOnce` (RWO) | un nœud en lecture/écriture | blocs : EBS, LVMS, Ceph RBD |
| `ReadWriteOncePod` (RWOP) | un seul Pod | bloc CSI |
| `ReadWriteMany` (RWX) | plusieurs nœuds en écriture | CephFS, NFS, EFS, Azure Files |
| `ReadOnlyMany` (ROX) | plusieurs nœuds en lecture | idem |

`volumeMode` : `Filesystem` (défaut) ou `Block` (accès brut, VM, bases de données).
`volumeBindingMode: WaitForFirstConsumer` : le volume est créé où le Pod est placé (indispensable en multi-zone ou stockage local).
`reclaimPolicy` : `Delete` (défaut dynamique) ou `Retain` (production !). `allowVolumeExpansion: true` permet d'agrandir.

### 1.4 Pilotes CSI sur OpenShift
| Plateforme | StorageClass par défaut | Remarque |
|---|---|---|
| AWS | `gp3-csi` | RWO, zonale |
| Azure | `managed-csi` | RWO ; Azure Files pour RWX |
| GCP | `standard-csi` | RWO |
| vSphere | `thin-csi` | RWO ; vSAN File Services RWX |
| CRC / OKD local | `crc-csi-hostpath-provisioner` | RWO, nœud unique |
| Bare metal / SNO | **LVM Storage (LVMS)** | basé sur TopoLVM, RWO local |
| Toute plateforme | **OpenShift Data Foundation (ODF)** | Ceph : RBD (RWO), CephFS (RWX), Object (S3 via NooBaa/RGW) |
| NFS | Operator `nfs-subdir-external-provisioner` ou PV statiques | RWX simple |

Classe par défaut : annotation `storageclass.kubernetes.io/is-default-class: "true"` (`oc get sc`).

### 1.5 Snapshots et clones (CSI)
`VolumeSnapshotClass` + `VolumeSnapshot` (de PVC) → `PersistentVolumeClaim` avec `dataSource` (restauration ou clone). Les snapshots ne sont **pas** des sauvegardes (même backend). Pour la sauvegarde : **OADP** (OpenShift API for Data Protection, basé sur Velero) : `DataProtectionApplication`, `Backup`, `Restore`, `Schedule`, vers S3.

### 1.6 Registre interne et stockage
Le registre exige du stockage persistant en production : `configs.imageregistry.operator.openshift.io/cluster` → `spec.storage.pvc.claim` (RWX recommandé pour plusieurs réplicas) ou S3. Sur CRC : `emptyDir` (volatile).

### 1.7 Droits sur volumes : `fsGroup` et SELinux
La SCC injecte un `fsGroup` du projet : les volumes sont `chgrp` pour être accessibles à l'UID arbitraire. SELinux (`MCS labels` par projet) isole les conteneurs ; si un chemin hôte monté est inaccessible, c'est souvent SELinux (pas les permissions Unix). Éviter `hostPath` ; si indispensable : SCC dédiée et `seLinuxOptions`.

### 1.8 Stockage éphémère
`emptyDir` (disque du nœud, `medium: Memory` pour tmpfs), *ephemeral volumes* (`volumes[].ephemeral.volumeClaimTemplate`), limites `ephemeral-storage`. Les logs et couches d'images remplissent `/var` : surveiller `DiskPressure`.

### 1.9 Bases de données : le bon réflexe
Préférer un **Operator** (CloudNativePG, Crunchy, Percona, MongoDB, Strimzi…) à un StatefulSet « maison » : sauvegarde, bascule, mises à jour majeures. Sur OpenShift, privilégier les images **non-root** (sclorg `postgresql-15-c9s`, ou images UBI Red Hat).

## 2. 🎬 Démo (40 min)

```bash
oc new-project lab-stockage
oc apply -f manifests/01-config.yaml && oc get cm,secret
oc set env deploy/app --list ; oc rsh deploy/app cat /etc/app/settings.conf
oc get sc ; oc get pv
oc apply -f manifests/02-pvc-app.yaml ; oc get pvc -w                 # Pending si WaitForFirstConsumer, Bound après le Pod
oc rsh deploy/app sh -c 'echo persistant > /data/test.txt'
oc delete pod -l app=pvc-app ; oc rsh deploy/pvc-app cat /data/test.txt
oc patch pvc data -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'     # expansion
oc apply -f manifests/03-snapshot.yaml                                 # snapshot + restauration
```

## 3. 🧪 Labos

> Projet : `lab-stockage`

### Lab 6.1 ⭐ — ConfigMap en variables et en fichier
Appliquez `manifests/01-config.yaml`. Modifiez la valeur du ConfigMap : que voit l'application via env ? via fichier ?

<details><summary>Corrigé</summary>

```bash
oc patch cm app-cfg -p '{"data":{"LOG_LEVEL":"debug"}}'
oc rsh deploy/app env | grep LOG_LEVEL          # ancienne valeur (env figé)
sleep 70 ; oc rsh deploy/app cat /etc/app/settings.conf   # nouvelle valeur (volume, hors subPath)
oc rollout restart deploy/app
```
</details>

### Lab 6.2 ⭐ — Secret
Créez un Secret `db-credentials`, injectez-le en variables dans un Pod. Décodez-le avec `oc get secret ... -o jsonpath | base64 -d`. Qui peut le lire ?

<details><summary>Corrigé</summary>

```bash
oc create secret generic db-credentials --from-literal=username=app --from-literal=password='S3cr3t!'
oc set env deploy/app --from=secret/db-credentials --prefix=DB_
oc get secret db-credentials -o jsonpath='{.data.password}' | base64 -d
oc policy who-can get secrets -n lab-stockage
```
base64 n'est pas du chiffrement : le contrôle d'accès RBAC et le chiffrement etcd sont les vraies protections.
</details>

### Lab 6.3 ⭐⭐ — PVC et persistance
Appliquez `02-pvc-app.yaml`. Écrivez un fichier, supprimez le Pod, relisez. Observez le PV créé, la StorageClass et le mode d'accès.

<details><summary>Corrigé</summary>

```bash
oc get pvc data -o wide ; oc get pv | grep lab-stockage
oc describe pvc data | grep -E 'StorageClass|Volume|Access'
```
</details>

### Lab 6.4 ⭐⭐ — Extension d'un volume
Agrandissez `data` de 1 à 2 Gi à chaud. Vérifiez `df -h` dans le Pod. Que se passe-t-il si la StorageClass n'autorise pas l'expansion ?

<details><summary>Corrigé</summary>

```bash
oc patch pvc data -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'
oc get pvc data -w ; oc rsh deploy/pvc-app df -h /data
```
Sans `allowVolumeExpansion: true`, la requête est refusée (`forbidden: only dynamically provisioned pvc can be resized`).
</details>

### Lab 6.5 ⭐⭐⭐ — Snapshot et restauration 🔑 (CSI avec snapshots)
Créez un `VolumeSnapshot`, supprimez des données, restaurez dans un nouveau PVC via `dataSource`.

<details><summary>Corrigé</summary>
Voir `manifests/03-snapshot.yaml`. `oc get volumesnapshotclass` pour connaître la classe. Sur CRC (hostpath) les snapshots peuvent ne pas être supportés : lire la démonstration ou utiliser ODF/cloud.
</details>

### Lab 6.6 ⭐⭐⭐ — PostgreSQL non-root avec PVC
Déployez `quay.io/sclorg/postgresql-15-c9s` avec Secret + PVC. Créez une table, supprimez le Pod, vérifiez la persistance.

<details><summary>Corrigé</summary>
`manifests/04-postgres.yaml`. Variables attendues par l'image : `POSTGRESQL_USER`, `POSTGRESQL_PASSWORD`, `POSTGRESQL_DATABASE`. Volume : `/var/lib/pgsql/data`.

```bash
oc rsh deploy/postgres psql -U app -d vote -c 'create table t(i int); insert into t values (1);'
oc delete pod -l app=postgres ; oc rsh deploy/postgres psql -U app -d vote -c 'select * from t;'
```
</details>

### Lab 6.7 ⭐⭐⭐ — Projet de volumes partagés (RWX)
Trois Pods écrivent dans un volume RWX. Quelle StorageClass utiliser ? Que se passe-t-il avec un PVC RWO sur 2 nœuds ?

<details><summary>Corrigé</summary>
`ocs-storagecluster-cephfs` (ODF), `efs`, `azurefile-csi`… RWO sur 2 nœuds : le second Pod reste `ContainerCreating` (`Multi-Attach error`). Sur un nœud unique, plusieurs Pods peuvent partager un RWO.
</details>

### Lab 6.8 ⭐⭐⭐⭐ — Chiffrement etcd et sauvegarde OADP 🔑
Activez le chiffrement `aesgcm` d'etcd et vérifiez la migration ; installez OADP, sauvegardez le projet `lab-stockage` vers un bucket S3 (MinIO du cluster), supprimez-le, restaurez.

<details><summary>Corrigé</summary>

```bash
oc patch apiserver cluster --type=merge -p '{"spec":{"encryption":{"type":"aesgcm"}}}'
oc get openshiftapiserver -o=jsonpath='{range .items[0].status.conditions[?(@.type=="Encrypted")]}{.reason}{"\n"}{.message}{"\n"}'
# OADP : voir manifests/05-oadp.yaml
```
Le chiffrement prend plusieurs minutes ; **sauvegardez etcd avant** (module 11).
</details>

## 4. Quiz
1. Une modification de ConfigMap est-elle visible dans les variables d'environnement d'un Pod en cours ? → non, redémarrage nécessaire.
2. Que fait `WaitForFirstConsumer` ? → retarde la création du volume jusqu'au placement du Pod.
3. RWO vs RWX ? → un nœud vs plusieurs.
4. Un snapshot CSI est-il une sauvegarde ? → non (même backend), utiliser OADP/Velero.
5. Comment protéger réellement un Secret ? → RBAC, chiffrement etcd, gestionnaire externe, pas de Git en clair.

Nettoyage : `oc delete project lab-stockage`

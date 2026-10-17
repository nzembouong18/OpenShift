# Module 07 — Sécurité : authentification, RBAC, SCC, conformité

⏱ 4 h · 🟡🔴

## Objectifs
- Configurer l'authentification (OAuth, HTPasswd, LDAP/OIDC) et les groupes
- Maîtriser RBAC, ServiceAccounts et **SecurityContextConstraints**
- Appliquer Pod Security Admission, durcir workloads et réseau
- Découvrir conformité (Compliance Operator), ACS/StackRox, chiffrement, supply chain

## 1. Cours

### 1.1 Vue d'ensemble : défense en profondeur
```
Identité (OAuth/OIDC) → Autorisation (RBAC) → Admission (SCC/PSA/webhooks/ValidatingAdmissionPolicy)
→ Exécution (SELinux, seccomp, caps, non-root) → Réseau (NetworkPolicy, mTLS) → Données (chiffrement)
→ Supply chain (signature, SBOM, scan) → Audit et conformité
```

### 1.2 Authentification
Le **serveur OAuth** intégré émet des jetons après vérification par un **Identity Provider** (`oauth.config.openshift.io/cluster`).
| IdP | Usage |
|---|---|
| `HTPasswd` | labos, comptes de secours |
| `LDAP` / Active Directory | entreprise |
| `OpenID Connect` | Keycloak, Entra ID, Okta, Google |
| `GitHub`, `GitLab`, `Google` | équipes de dev |
| `RequestHeader`, `Keystone`, `BasicAuth` | cas particuliers |
- Objets : `User`, `Identity`, `Group` ; synchronisation de groupes LDAP : `oc adm groups sync`.
- Utilisateur `kubeadmin` : **à supprimer** après configuration d'un IdP et d'un `cluster-admin` nominatif (`oc delete secret kubeadmin -n kube-system`).
- Durée des jetons : `oauthclients`, `OAuth.spec.tokenConfig.accessTokenMaxAgeSeconds`.
- Depuis 4.15+ : **authentification externe directe (OIDC)** possible sans le serveur OAuth intégré (selon version/plateforme).

### 1.3 RBAC
`Role`/`ClusterRole` (verbes × ressources) + `RoleBinding`/`ClusterRoleBinding` (sujets). Règle **additive**, jamais de deny.
| Rôle | Portée | Droits |
|---|---|---|
| `cluster-admin` | cluster | tout |
| `admin` / `edit` / `view` | projet | cf. module 02 |
| `cluster-reader` | cluster | lecture seule globale |
| `self-provisioner` | cluster | créer des projets |
Outils : `oc auth can-i`, `oc policy who-can`, `oc adm policy who-can`, `oc adm policy scc-subject-review`, `oc get rolebinding -o wide`. Agrégation de rôles : labels `rbac.authorization.k8s.io/aggregate-to-*`.
Bonnes pratiques : groupes plutôt qu'utilisateurs, `RoleBinding` plutôt que `ClusterRoleBinding`, revue périodique, aucun `*`.

### 1.4 ServiceAccounts
Identité des Pods. Chaque projet reçoit `default`, `builder`, `deployer`. Jetons : projetés, **à durée limitée** (plus de secrets longue durée automatiques depuis 4.11). Un SA reçoit le `view`/`edit` seulement si vous l'accordez. Pour un accès externe longue durée : `oc create token <sa> --duration=...` ou Secret de type `service-account-token` explicite.
```bash
oc create sa pipeline-sa
oc policy add-role-to-user edit -z pipeline-sa
oc create token pipeline-sa --duration=1h
```
Pull secrets : `oc secrets link default regcred --for=pull`.

### 1.5 SecurityContextConstraints (SCC)
Les SCC contrôlent **ce qu'un Pod a le droit de faire** (UID, capacités, volumes, SELinux, host*). Elles sont plus riches que les PSP supprimées de Kubernetes.
| SCC | Pour qui | Risque |
|---|---|---|
| `restricted-v2` | **défaut** de tous les utilisateurs authentifiés | faible |
| `nonroot-v2` | image avec `USER` numérique non-root | faible |
| `anyuid` | image exigeant un UID fixe (root inclus) | moyen |
| `hostmount-anyuid`, `hostaccess`, `hostnetwork-v2` | accès hôte | élevé |
| `privileged` | composants plateforme (CNI, CSI…) | **critique** |

Mécanique d'admission : SCC compatibles (via `use` sur la SCC pour l'utilisateur ou le SA) triées par **priorité** puis restriction ; la première qui valide est appliquée et annotée sur le Pod (`openshift.io/scc`). Le UID est tiré de la plage du projet.
```bash
oc get scc
oc adm policy add-scc-to-user anyuid -z monapp -n lab-secu     # 🔑 : le SA monapp seulement
oc adm policy scc-review -z monapp -f pod.yaml                 # quelle SCC pour ce Pod ?
oc describe scc restricted-v2
```
**Ne modifiez jamais les SCC par défaut** ; créez-en de nouvelles, accordez-les à des **SA précis**, jamais à `system:authenticated`.

### 1.6 Pod Security Admission (PSA) et SCC
PSA (`pod-security.kubernetes.io/enforce|audit|warn` = `privileged|baseline|restricted`) coexiste avec les SCC. Depuis 4.12 : le **synchroniseur** dérive les labels PSA des SCC accessibles au projet (`security.openshift.io/scc.podSecurityLabelSync`). Les namespaces `openshift-*` restent `privileged`. Pour vos projets : visez `restricted` (warn/audit au minimum).
```bash
oc label ns lab-secu pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted --overwrite
```

### 1.7 Durcir un workload (checklist)
- `runAsNonRoot: true`, pas d'`runAsUser` fixe (laisser la plage du projet)
- `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile: RuntimeDefault`
- `readOnlyRootFilesystem: true` (+ `emptyDir` pour `/tmp`)
- requests/limits, probes, ServiceAccount dédié, `automountServiceAccountToken: false` si inutile
- images par **digest**, registres autorisés (`image.config.openshift.io/cluster` → `allowedRegistriesForImport`, `registrySources`), `ImageContentSourcePolicy`/`ImageDigestMirrorSet`
- NetworkPolicy default-deny, egress restreint

### 1.8 Admission avancée
`ValidatingAdmissionPolicy` (CEL, sans webhook), webhooks (Kyverno, OPA Gatekeeper via Operator) pour imposer : labels obligatoires, interdiction de `latest`, registres autorisés, limites.
```yaml
# Extrait CEL : interdire :latest
expression: "object.spec.template.spec.containers.all(c, !c.image.endsWith(':latest'))"
```

### 1.9 Chiffrement, certificats, audit
- **etcd** : `aescbc`/`aesgcm` (module 06). **Disques** : LUKS via `MachineConfig` ou chiffrement cloud/CSI.
- **Certificats** : API (`apiserver.spec.servingCerts.namedCertificates`), Ingress (`defaultCertificate`), rotation automatique des certificats internes ; **cert-manager** pour les vôtres.
- **Profils TLS** : `tlsSecurityProfile` (Old/Intermediate/Modern/Custom) pour API, Ingress, kubelet.
- **Audit** : profils `Default`, `WriteRequestBodies`, `AllRequestBodies` (`apiserver.spec.audit.profile`) ; collecte : `oc adm node-logs --role=master --path=kube-apiserver/audit.log`.
- **Fichier/exec dans les conteneurs** : Falco, ACS runtime, audit des `oc rsh`.

### 1.10 Conformité et scan
| Outil | Rôle |
|---|---|
| **Compliance Operator** | scans OpenSCAP (CIS, PCI-DSS, NIST, ANSSI-BP-028…) : `ScanSettingBinding`, `ComplianceCheckResult`, remédiations |
| **File Integrity Operator** | surveille l'intégrité des fichiers des nœuds (AIDE) |
| **Red Hat Advanced Cluster Security (StackRox)** | vulnérabilités d'images, politiques de déploiement/runtime, graphe réseau, conformité |
| **Quay + Clair** | registre avec scan, signature |
| **Security Profiles Operator** | profils seccomp/SELinux générés |
| **Network Observability** | flux réseau (eBPF) |
| **Cosign / Sigstore, ACS, `ClusterImagePolicy`** | vérification de signature à l'admission (selon version) |

### 1.11 Isolation multi-tenant
Un projet par équipe/environnement, quotas, NetworkPolicy, SCC minimales, nœuds dédiés (`openshift.io/node-selector` + taints), `ClusterResourceQuota`, AdminNetworkPolicy, `ResourceQuota` stockage, politiques d'images. Pour l'isolation forte : clusters séparés, **Hosted Control Planes** (module 12), ou machines virtuelles Kata (sandboxed containers).

## 2. 🎬 Démo (50 min)

```bash
oc new-project lab-secu
# 1. Authentification : HTPasswd
htpasswd -c -B -b users.htpasswd alice 'Passw0rd!' ; htpasswd -B -b users.htpasswd bob 'Passw0rd!'
oc create secret generic htpass-secret --from-file=htpasswd=users.htpasswd -n openshift-config      # 🔑
oc apply -f manifests/01-oauth-htpasswd.yaml ; oc get pods -n openshift-authentication -w
oc login -u alice -p 'Passw0rd!'
# 2. RBAC
oc adm policy add-role-to-user view bob -n lab-secu        # en admin
oc auth can-i delete pod -n lab-secu --as=bob
# 3. SCC : une image qui exige root
oc apply -f manifests/02-pod-root.yaml ; oc get pod root -o yaml | grep -i scc ; oc describe pod root | tail
oc create sa needs-root ; oc adm policy add-scc-to-user anyuid -z needs-root     # 🔑
oc adm policy scc-subject-review -z needs-root -f manifests/02-pod-root.yaml
# 4. PSA
oc label ns lab-secu pod-security.kubernetes.io/enforce=restricted --overwrite
# 5. Durcissement
oc apply -f manifests/03-hardened-deployment.yaml
```

## 3. 🧪 Labos

> Projet : `lab-secu` (🔑 = administrateur)

### Lab 7.1 ⭐⭐ — IdP HTPasswd 🔑
Ajoutez deux utilisateurs `alice` (admin du projet) et `bob` (lecture seule). Connectez-vous, vérifiez ce que chacun peut faire.

<details><summary>Corrigé</summary>

```bash
oc apply -f manifests/01-oauth-htpasswd.yaml
oc adm policy add-role-to-user admin alice -n lab-secu
oc adm policy add-role-to-user view bob -n lab-secu
oc login -u bob -p 'Passw0rd!' && oc auth can-i create pod -n lab-secu
```
Attendre le redéploiement des Pods `oauth-openshift` (1-2 min). Ne remplacez pas la ressource OAuth sans conserver les IdP existants.
</details>

### Lab 7.2 ⭐⭐ — Groupes et rôles
Créez un groupe `devs` avec alice et bob ; donnez-lui `edit` sur `lab-secu`. Retirez ensuite bob du groupe.

<details><summary>Corrigé</summary>

```bash
oc adm groups new devs alice bob
oc adm policy add-role-to-group edit devs -n lab-secu
oc adm groups remove-users devs bob
```
</details>

### Lab 7.3 ⭐⭐ — Rôle sur mesure
Créez un `Role` `pod-reader` (get/list/watch pods + logs) et liez-le à un ServiceAccount `auditor`. Testez avec `oc auth can-i --as=system:serviceaccount:lab-secu:auditor`.

<details><summary>Corrigé</summary>
Voir `manifests/04-rbac.yaml`.

```bash
oc auth can-i list pods --as=system:serviceaccount:lab-secu:auditor -n lab-secu    # yes
oc auth can-i delete pods --as=system:serviceaccount:lab-secu:auditor -n lab-secu  # no
```
</details>

### Lab 7.4 ⭐⭐ — Image root, SCC `anyuid`
Déployez `docker.io/library/nginx:1.27` : échec. Comprenez pourquoi. Corrigez d'abord par **une image non-root**, puis (en connaissance de cause) par `anyuid` sur un SA dédié.

<details><summary>Corrigé</summary>

```bash
oc describe pod root | tail -5
oc create sa nginx-root
oc adm policy add-scc-to-user anyuid -z nginx-root
oc set serviceaccount deploy/nginx-root nginx-root
oc get pod -o yaml | grep 'openshift.io/scc'       # anyuid
```
Le périmètre est le SA, pas le projet. À documenter comme dette technique.
</details>

### Lab 7.5 ⭐⭐⭐ — SCC personnalisée 🔑
Créez une SCC `tmp-writable` basée sur `restricted-v2` autorisant seulement le volume `emptyDir` et `readOnlyRootFilesystem: true`. Accordez-la à un SA.

<details><summary>Corrigé</summary>
Voir `manifests/05-scc-custom.yaml`. Appliquer, puis `oc adm policy add-scc-to-user tmp-writable -z <sa>`. Vérifier avec `scc-review`.
</details>

### Lab 7.6 ⭐⭐ — Pod Security Admission
Activez `enforce=restricted` sur le projet. Déployez un Pod `privileged` ou sans `seccompProfile` et lisez l'erreur. Corrigez le manifeste.

<details><summary>Corrigé</summary>
Le message liste les champs fautifs (`allowPrivilegeEscalation`, `capabilities`, `runAsNonRoot`, `seccompProfile`). Le manifeste `03-hardened-deployment.yaml` passe.
</details>

### Lab 7.7 ⭐⭐⭐ — Admission déclarative (CEL)
Écrivez une `ValidatingAdmissionPolicy` interdisant `:latest` et les conteneurs sans `resources.limits.memory` dans les projets étiquetés `env=prod`.

<details><summary>Corrigé</summary>
Voir `manifests/06-vap.yaml` ; test : `oc -n prod-ns run x --image=nginx:latest` → refusé.
</details>

### Lab 7.8 ⭐⭐⭐ — Compliance Operator 🔑
Installez l'Operator, lancez un scan `ocp4-cis` + `rhcos4-moderate`, listez les `ComplianceCheckResult` en échec et appliquez une remédiation automatique.

<details><summary>Corrigé</summary>
Voir `manifests/07-compliance.yaml`.

```bash
oc get compliancesuite -n openshift-compliance -w
oc get compliancecheckresult -n openshift-compliance | grep FAIL | head
oc get complianceremediation -n openshift-compliance
oc patch complianceremediation <nom> -n openshift-compliance --type=merge -p '{"spec":{"apply":true}}'
```
Les remédiations de nœuds génèrent des `MachineConfig` et donc un redémarrage progressif.
</details>

### Lab 7.9 ⭐⭐⭐⭐ — Audit et enquête 🔑
Activez `WriteRequestBodies`, supprimez un secret avec l'utilisateur `bob`, retrouvez qui/quand/quoi dans les logs d'audit.

<details><summary>Corrigé</summary>

```bash
oc patch apiserver cluster --type=merge -p '{"spec":{"audit":{"profile":"WriteRequestBodies"}}}'
oc adm node-logs --role=master --path=kube-apiserver/audit.log | grep '"verb":"delete"' | grep '"resource":"secrets"' | jq -c '{user:.user.username,obj:.objectRef.name,t:.requestReceivedTimestamp}'
```
</details>

### Lab 7.10 ⭐⭐⭐⭐ — Supprimer `kubeadmin` et durcir l'accès 🔑
Après avoir créé un cluster-admin nominatif via un IdP, supprimez le secret `kubeadmin`, retirez `self-provisioner` aux authentifiés, activez le chiffrement etcd, fixez un profil TLS `Intermediate`.

<details><summary>Corrigé</summary>

```bash
oc adm policy add-cluster-role-to-user cluster-admin alice
oc delete secret kubeadmin -n kube-system
oc patch ingresscontroller default -n openshift-ingress-operator --type=merge -p '{"spec":{"tlsSecurityProfile":{"type":"Intermediate","intermediate":{}}}}'
```
Irréversible sur CRC sans recréation : ne le faites pas avant d'avoir **testé** la connexion nominative.
</details>

## 4. Quiz
1. Quelle SCC s'applique par défaut ? → `restricted-v2`.
2. Pourquoi `anyuid` sur un SA plutôt que sur le projet ? → limiter la portée de l'exception (moindre privilège).
3. RBAC supporte-t-il le deny ? → non, uniquement additif.
4. Quel outil exécute des scans CIS/PCI ? → Compliance Operator.
5. Comment lire les logs d'audit ? → `oc adm node-logs --role=master --path=kube-apiserver/audit.log`.

Nettoyage : `oc delete project lab-secu` ; retirer l'IdP de test (`oc edit oauth cluster`) si créé.

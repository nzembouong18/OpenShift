# Guide du formateur

## 1. Planning type — 6 jours (7 h/jour)

| Jour | Matin (9h-12h30) | Après-midi (13h30-17h) |
|---|---|---|
| **J1** | Accueil, tour de table, **00 Setup** (1 h), **01 Fondamentaux** (cours + démo) | 01 labos 1.1-1.4, **02 Projets & applications** (cours, démo, labos 2.1-2.5) |
| **J2** | **03 Builds & S2I** (cours, démo, labos 3.1-3.6) | 03 fin (3.7-3.8), **04 Workloads** (cours, démo, labos 4.1-4.6) |
| **J3** | 04 fin (4.7-4.8), **05 Réseau** (cours, démo, labos 5.1-5.4) | 05 fin (NetworkPolicy, egress), **06 Config & stockage** (6.1-6.6) |
| **J4** | **07 Sécurité** (IdP, RBAC, SCC, PSA : 7.1-7.6) | 07 fin (7.7-7.8), **08 Operators** (8.1-8.4, 8.6) |
| **J5** | **09 Pipelines & GitOps** (9.1-9.8) | **10 Observabilité** (10.1-10.6) |
| **J6** | **11 Administration** (cours + démos MCO/etcd/upgrade) | **13 Projet final** (version courte 3 h) + soutenances ; **12 Avancé** en démonstration |

Variantes :
- **Développeur (3 jours, esprit EX288)** : 00, 01, 02, 03, 04, 05 (5.1-5.6), 06 (6.1-6.4), 09 (Tekton + Argo CD de base), projet final version courte.
- **Administrateur (4 jours, esprit EX280)** : 01, 02, 05, 06, 07, 08, 10, 11 + projet (volets sécurité/exploitation).
- **Expert (2 jours add-on)** : 11 (complet sur cluster dédié), 12 (labos 12.1-12.8), revue d'architecture.
- **Distanciel** : 12 demi-journées de 3 h 30 ; démos en live-coding, labos en salles de travail (binômes).

## 2. Répartition conseillée
Cours 25 % · Démo 20 % · Labos 50 % · Quiz/rétro 5 %. Ne jamais dépasser 20 min de cours sans manipulation.

## 3. Choix de l'infrastructure — décision à prendre en J-30
| Option | Pour | Contre |
|---|---|---|
| **Cluster OCP partagé par le formateur** (1 projet par stagiaire, quotas) | tous les labos sauf 🔑 par stagiaire ; ressources mutualisées | risque de voisinage, droits admin à partager prudemment |
| **CRC par poste** | autonomie, 🔑 possible | 16 Go RAM/poste, téléchargement ≈ 4 Go, pull secret par personne |
| **Developer Sandbox** | zéro installation | pas de 🔑, 14 jours d'inactivité, quotas |
| **Un cluster par binôme (cloud IPI/ROSA/ARO)** | tout est possible | coût (≈ 6-10 €/h/cluster), à détruire après |
| **OKD / SNO** | open source, 🔑 | communautaire, versions différentes d'OCP |

Recette « classe de 12 » : un cluster OCP 3 CP + 4 workers (16 vCPU/64 Go au total pour les workers), un compte `htpasswd` par stagiaire (`user01..user12`), `ClusterResourceQuota` par utilisateur, template de projet (module 02), `self-provisioner` conservé (labos), un cluster 🔑 séparé pour les modules 11-12 (SNO ou HCP).

Création des comptes :
```bash
for i in $(seq -w 1 12); do htpasswd -B -b users.htpasswd user$i "$(openssl rand -base64 9)"; done
```
Distribuer les mots de passe séparément (jamais dans le dépôt).

## 4. Préparation (J-7 → J-1)
- [ ] Vérifier `oc login` + `make check` sur chaque poste (ou compte Sandbox actif)
- [ ] Vérifier la disponibilité des **images** : `registry.access.redhat.com/ubi9/*`, `quay.io/sclorg/*`, `docker.io/openshift/hello-openshift`, `nginxinc/nginx-unprivileged`. Si le réseau est contraint : miroir (`oc image mirror`) + `ImageDigestMirrorSet`
- [ ] **Operators** (module 08/09/10/12) : pré-installer Pipelines, GitOps, Web Terminal ; pré-vérifier les canaux (`make operators-info`)
- [ ] Vérifier l'accès GitHub (S2I clone `sclorg/*-ex`, ce dépôt pour les BuildConfigs/Argo CD) ; forker ce dépôt sur l'organisation de la classe si pare-feu
- [ ] Préparer le dépôt GitOps et le webhook (module 09)
- [ ] Tester toutes les démos sur la version OCP retenue (§7)
- [ ] Prévoir un cluster de secours, imprimer l'[aide-mémoire](cheatsheet.md)
- [ ] Désactiver la mise en veille des Sandbox (utilisation avant le cours)

## 5. Conseils d'animation
- **Faire prédire avant d'exécuter** : « que fait l'Operator si je supprime ce Pod ? », « quelle SCC va s'appliquer ? ».
- **Casser volontairement** (modules 04, 05, 07, 10) : le diagnostic est la compétence n°1.
- Montrer systématiquement la **console** *et* la CLI : les deux publics (dev/ops) ne se sentent pas à égalité sinon.
- Insister sur `oc describe` → **Events**, `oc get events --sort-by=.lastTimestamp`.
- Imposer le YAML écrit à la main une fois par objet, puis autoriser `oc create ... --dry-run=client -o yaml`.
- Pair-programming : pilote/copilote, alterner toutes les 30 min.
- Fil rouge : `vote-app` (module 13) ; relier chaque module à une étape de sa production-isation.
- Niveaux hétérogènes : les labos ⭐⭐⭐⭐ sont des défis, jamais obligatoires.

## 6. Pièges fréquents (et réponses)
| Piège | Remède |
|---|---|
| `ImagePullBackOff` sur Docker Hub (rate limit) | utiliser UBI/Quay ; secret de pull ; miroir interne |
| Image Docker Hub qui plante (root) | c'est un **objectif pédagogique** (module 07) ; fournir l'alternative non-root |
| CRC trop lent / manque de mémoire | `crc config set memory 20480`, fermer les autres applications, désactiver `monitoring` n'est **pas** possible → viser 16 Go minimum |
| CRC « cassé » après plusieurs jours éteint | attendre/approuver les CSR (`oc get csr`), `crc stop && crc start` |
| Sandbox : projet sans droits de création | utiliser le projet existant `<user>-dev`, adapter les namespaces dans les YAML (`sed`) |
| Les manifests contiennent `namespace: lab-xxx` | `oc apply -f ... -n <projet>` ne l'écrase pas : retirer le champ ou `sed -i "s/lab-xxx/$(oc project -q)/"` |
| Build S2I trop long (pull des builders) | pré-importer `oc import-image` / lancer un build à blanc la veille |
| Webhooks inaccessibles (cluster privé) | simuler avec `curl` (labos 3.6, 9.5) |
| Operators absents (catalogues désactivés) | miroir de catalogue ou démonstration formateur |
| Route injoignable (DNS `*.apps`) | ajouter les entrées dans `/etc/hosts` ou utiliser `curl --resolve` |
| NetworkPolicy coupe la Route | autoriser `network.openshift.io/policy-group: ingress` |
| Redémarrage MCO pendant les labos 🔑 | planifier : un cluster par groupe, jamais pendant une démo critique |

## 7. Versions et dérives
La formation vise OCP **4.16 → 4.19**. Points à revérifier avant chaque session : (1) noms/canaux des Operators (Logging 6, Service Mesh 3, OLM v1, Builds v2) ; (2) API dépréciées (`DeploymentConfig`, `ClusterTask`, `v1beta1` Tekton Triggers) ; (3) disponibilité des images (Bitnami, Docker Hub) ; (4) limites du Sandbox ; (5) options d'authentification (OAuth intégré vs OIDC externe).

## 8. Évaluation
Voir [evaluation.md](evaluation.md). Barème projet final dans `13-projet-final/README.md`.

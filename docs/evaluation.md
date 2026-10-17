# Évaluation et certifications

## 1. Modalités

| Moment | Outil | Barème |
|---|---|---|
| Fin de chaque module | Quiz (5 questions) + labos validés | formatif |
| Fin J3 | **QCM intermédiaire** (§2) | 20 pts |
| Fin J6 | **Projet final** (module 13) + soutenance | 100 pts |
| Optionnel | **Examen pratique chronométré** (§4) | 100 pts |

Attestation de réussite : ≥ 70 % au projet **et** ≥ 70 % au QCM.

## 2. QCM (20 questions, 1 point chacune) — réponses en §3

1. Quel Operator pilote les mises à jour de la plateforme ? a) MCO b) CVO c) OLM d) Ingress
2. Que fait le MCO ? a) gère les certificats b) gère l'OS des nœuds via MachineConfig c) installe des Operators d) fait les builds
3. Quelle SCC est appliquée par défaut ? a) anyuid b) privileged c) restricted-v2 d) hostaccess
4. Un ImageStream… a) stocke obligatoirement les couches b) référence des images par tags/digests c) remplace le registre d) est un volume
5. Quelle stratégie de build ne nécessite pas de Dockerfile ? a) Docker b) Source (S2I) c) Custom d) aucune
6. Pour répartir 10 % du trafic vers une v2 on utilise… a) Ingress b) alternateBackends sur la Route c) HPA d) NetworkPolicy
7. Edge vs passthrough : en passthrough, le TLS est terminé… a) au Router b) dans le Pod c) au LB cloud d) nulle part
8. DeploymentConfig est… a) recommandé b) déprécié c) supprimé du produit d) réservé aux admins
9. Une NetworkPolicy default-deny casse les Routes. Il faut autoriser… a) le namespace du router (policy-group ingress) b) 0.0.0.0/0 c) hostNetwork d) rien
10. Le monitoring des applications nécessite… a) enableUserWorkload: true b) un Grafana externe c) un sidecar d) un Operator payant
11. ServiceMonitor sert à… a) créer des alertes b) déclarer des cibles de scrape c) créer des dashboards d) stocker des logs
12. `oc adm drain` échoue à cause de… a) un PDB strict b) un Service c) un Secret d) une Route
13. Sauvegarde etcd : a) `oc adm backup` b) `cluster-backup.sh` sur un nœud control plane c) snapshot de PVC d) impossible
14. Un Subscription en `Manual` demande… a) rien b) l'approbation de l'InstallPlan c) un redémarrage d) une SCC
15. Hosted Control Planes : a) le CP tourne en Pods b) le CP est supprimé c) plus de workers d) sans etcd
16. Le rôle `admin` dans un projet permet de… a) tout y faire, dont gérer les droits b) lire seulement c) administrer le cluster d) créer des projets
17. Quelle commande met à jour le cluster ? a) `oc upgrade` b) `oc adm upgrade --to=` c) `oc update cluster` d) `oc rollout`
18. GitOps (Argo CD) : le déploiement est… a) poussé par la CI b) tiré et réconcilié depuis Git c) manuel d) via Jenkins uniquement
19. Un Secret Kubernetes est par défaut… a) chiffré dans etcd b) encodé en base64 (chiffrement etcd optionnel) c) hashé d) inaccessible
20. Le registre interne est joignable en interne sur… a) quay.io b) image-registry.openshift-image-registry.svc:5000 c) localhost:5000 d) registry.redhat.io

## 3. Corrigé
1b · 2b · 3c · 4b · 5b · 6b · 7b · 8b · 9a · 10a · 11b · 12a · 13b · 14b · 15a · 16a · 17b · 18b · 19b · 20b

## 4. Examen pratique (3 h, 15 tâches, 100 pts) — exemples
Réalisez, dans un projet vierge, sans consulter les corrigés (documentation officielle autorisée) :
1. Créer un projet avec quota (2 CPU/4 Gi) et LimitRange ; ajouter `alice` en `edit`, `bob` en `view`. *(6)*
2. Déployer une application depuis un dépôt Git par S2I, l'exposer en HTTPS avec redirection. *(8)*
3. Corriger un Deployment qui échoue à cause de la SCC (image root) **sans** modifier la SCC. *(8)*
4. Configurer ConfigMap et Secret ; les injecter (env + fichier) ; provoquer un rollout. *(6)*
5. Créer un PVC, y écrire des données, prouver la persistance après suppression du Pod. *(6)*
6. Mettre en place un autoscaler (HPA) et le valider sous charge. *(6)*
7. Isoler le projet avec NetworkPolicy (default-deny + Router + flux applicatif). *(8)*
8. Répartir le trafic 80/20 entre deux versions. *(5)*
9. Créer un Role/RoleBinding pour un ServiceAccount de lecture des Pods. *(5)*
10. Diagnostiquer 3 applications cassées (image, config, mémoire) et les réparer. *(9)*
11. Écrire un Pipeline Tekton simple (clone + build) et l'exécuter. *(8)*
12. Déclarer une Application Argo CD avec sync automatique + selfHeal. *(6)*
13. Exposer des métriques via ServiceMonitor et créer une alerte. *(6)*
14. 🔑 Créer un MachineConfig (sysctl/chrony) pour un pool et valider l'application. *(5)*
15. 🔑 Sauvegarder etcd et lister les mises à jour disponibles (sans les lancer). *(4)*

Barème : 1 point de moins par étape manquante, validation par script de contrôle du formateur.

## 5. Parcours de certification (indicatif)
| Certification Red Hat | Modules couverts | Compléments |
|---|---|---|
| **EX280 — OpenShift Administration** | 01, 02, 05, 06, 07, 08, 10, 11 | pratique chronométrée, templates, quotas, OAuth, MCO |
| **EX288 — OpenShift Application Development** | 02, 03, 04, 05, 06, 09 | Helm, Tekton, probes, ressources |
| **EX380 — Automation and Integration** | 08, 09, 11, 12 | GitOps, ACM, Ansible, API |
| **Cloud-native : CKA / CKAD** | modules K8s de la formation Kubernetes | OpenShift passe sur Kubernetes standard |
Les contenus d'examens évoluent : consulter les objectifs officiels Red Hat avant inscription.

## 6. Auto-évaluation par niveau
| Niveau | Capacités vérifiables |
|---|---|
| 🟢 Débutant | se connecter, créer projet, déployer depuis image/source, exposer, lire logs/events |
| 🟡 Intermédiaire | builds, ImageStreams, probes/HPA, Routes TLS, NetworkPolicy, PVC, RBAC |
| 🔴 Avancé | SCC, Operators, pipelines, GitOps, monitoring/alertes, diagnostic rapide |
| ⚫ Expert | MCO, upgrades, etcd/DR, multi-cluster, architecture HA/DR/sécurité, optimisation |

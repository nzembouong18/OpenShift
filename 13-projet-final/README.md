# Module 13 — Projet final : « vote-app » en production sur OpenShift

⏱ 5 h (travail en binôme) · 🔴 Avancé

## Contexte
Porter une application 3-tiers, **déjà fournie et fonctionnelle**, au niveau d'exigence d'une production OpenShift en mobilisant tous les acquis.

```
 Utilisateur ──► Route (TLS edge) ──► vote-frontend (nginx) ──/api──► vote-api (Flask) ──► postgres (StatefulSet + PVC)
                                              ▲                              │
                           Tekton ──build──► ImageStream     Prometheus ◄─ /metrics ─┘
                           Argo CD ──sync──► Git (overlays dev | staging | prod)
```

Le code est dans [`app/`](app/) (API Flask, tests, `Containerfile`), les manifests Kustomize dans [`manifests/`](manifests/) (`base/` + `overlays/{dev,staging,prod}`).

## Cahier des charges

| # | Exigence | Module |
|---|---|---|
| 1 | Projets `vote-dev`, `vote-staging`, `vote-prod` avec **quotas**, **LimitRange**, labels standards `app.kubernetes.io/*` | 02 |
| 2 | Image `vote-api` **construite dans le cluster** (BuildConfig Docker ou Shipwright) depuis `13-projet-final/app`, publiée dans un ImageStream ; déployée **par digest** en staging/prod | 03 |
| 3 | `vote-api` et `vote-frontend` en Deployments (≥ 2 réplicas en prod), `postgres` en StatefulSet avec PVC ; stratégie RollingUpdate `maxUnavailable: 0` | 04 |
| 4 | Route **TLS** (edge + redirect), puis variante **re-encrypt** avec certificat Service CA vers le frontend | 05 |
| 5 | **NetworkPolicy** : default-deny + flux strictement nécessaires (router → web → api → db, monitoring → api) | 05 |
| 6 | Identifiants PostgreSQL en **Secret** (jamais en clair dans Git : Sealed Secrets, SOPS ou External Secrets) ; config en **ConfigMap** | 06 |
| 7 | **Requests/limits**, probes (startup/readiness/liveness), **HPA** (2→6, 60 % CPU), **PDB**, topologySpread | 04 |
| 8 | **SecurityContext** durci, SA dédié sans token monté, **aucune SCC supplémentaire** ; namespace PSA `restricted` (warn/audit au minimum) | 07 |
| 9 | Accès : `alice` (admin du projet), `bob` (view), un groupe `qa` (edit en staging) | 07 |
| 10 | **Pipeline Tekton** : clone → tests (`pytest`) → build → déploiement dev ; déclenché par webhook | 09 |
| 11 | **Argo CD** : un `ApplicationSet` dev/staging/prod ; sync auto en dev/staging, manuelle en prod ; promotion par PR | 09 |
| 12 | **ServiceMonitor** + 2 alertes (indisponibilité, taux d'erreurs) ; un dashboard ; test de déclenchement | 10 |
| 13 | **Logging** : logs JSON retrouvés dans la console (Loki) *ou* via `oc logs` avec corrélation d'un identifiant de requête | 10 |
| 14 | **Chaos & reprise** : suppression de Pods en charge (0 erreur visible), drain d'un nœud (PDB respecté), restauration de la base depuis sauvegarde (`pg_dump` ou OADP) | 06, 11 |
| 15 | **Bonus** : scale-to-zero du frontend (Knative) · canary 90/10 par Route · VAP interdisant `:latest` · scan Compliance/ACS | 05, 07, 12 |
| 16 | Document **RUNBOOK.md** (voir le gabarit [RUNBOOK.md](RUNBOOK.md)) | tous |

## Démarrage

```bash
# 1. Projets et droits (adapter pour le Sandbox : un seul projet, suffixes -dev uniquement)
for e in dev staging prod; do oc new-project vote-$e; done
# 2. Construire l'image dans lab-cicd (ou dans vote-dev) :
oc new-project lab-cicd
oc new-build --name=vote-api --strategy=docker --binary
oc patch bc/vote-api -p '{"spec":{"strategy":{"dockerStrategy":{"dockerfilePath":"Containerfile"}}}}'
oc start-build vote-api --from-dir=13-projet-final/app --follow
# 3. Autoriser l'extraction d'image depuis les autres projets
for e in dev staging prod; do oc policy add-role-to-group system:image-puller system:serviceaccounts:vote-$e -n lab-cicd; done
# 4. Déployer la base fonctionnelle (Kustomize intégré à oc)
oc apply -k 13-projet-final/manifests/overlays/dev
oc -n vote-dev get pods -w
curl -k https://$(oc -n vote-dev get route vote -o jsonpath='{.spec.host}')/api/results
```
Résultat attendu : `{"a":0,"b":0}` puis les compteurs augmentent via l'interface.

## Jalons proposés

| Temps | Jalon | Livrable |
|---|---|---|
| 0 h 30 | Application déployée en dev | votes visibles |
| 1 h 15 | Quotas, accès, PSA, NetworkPolicy validés | `oc auth can-i`, tests de blocage |
| 2 h 15 | Pipeline Tekton + webhook | PipelineRun vert |
| 3 h 00 | Argo CD ApplicationSet + promotion staging | Applications `Synced/Healthy` |
| 3 h 45 | Monitoring, alertes, test | alerte déclenchée puis résolue |
| 4 h 15 | Chaos + sauvegarde/restauration | rapport des tests |
| 4 h 30 | Soutenance 10 min + RUNBOOK | démo + questions |

## Recette (tests de validation)

```bash
# Fonctionnel
oc -n vote-prod get pods                                          # tous Ready, SCC restricted-v2 : oc get pod -o yaml | grep openshift.io/scc
curl -sk https://$(oc -n vote-prod get route vote -o jsonpath='{.spec.host}')/api/results
# Résilience : suppression en charge, 0 erreur HTTP côté client
while true; do curl -sk -o /dev/null -w "%{http_code}\n" https://$HOST/api/results; sleep 0.2; done | sort | uniq -c &
oc -n vote-prod delete pod -l app=vote-api --wait=false
# Sécurité : un Pod étranger ne joint pas la base
oc -n vote-prod run intrus --rm -it --image=registry.access.redhat.com/ubi9/ubi-minimal -- bash -c 'timeout 3 bash -c "</dev/tcp/postgres/5432" && echo OUVERT || echo BLOQUE'
# Scalabilité : charge et HPA
oc -n vote-prod get hpa -w
# Alerte
oc -n vote-prod scale statefulset postgres --replicas=0   # readyz 503 → ErrorRate
# Maintenance : drain d'un worker
oc adm drain <worker> --ignore-daemonsets --delete-emptydir-data
```

## Grille d'évaluation (100 pts)

| Critère | Points |
|---|---|
| Fonctionnement bout en bout (dev→prod) | 15 |
| Sécurité (SCC par défaut, PSA, NetPol, secrets, RBAC) | 20 |
| Livraison (Tekton + Argo CD, promotion, digest) | 20 |
| Fiabilité (probes, HPA, PDB, chaos, sauvegarde) | 15 |
| Observabilité (métriques, alertes, logs) | 10 |
| RUNBOOK (clarté, exactitude, reproductibilité) | 10 |
| Soutenance (démo, justification des choix) | 10 |
| Bonus | +10 |

## Pièges fréquents
- `ImagePullBackOff` entre projets : `system:image-puller` manquant.
- Route 503 après NetworkPolicy : oubli de l'autorisation du Router.
- `CrashLoopBackOff` de PostgreSQL après changement du Secret : le mot de passe est figé dans le PVC initialisé → supprimer le PVC (lab) ou `ALTER USER`.
- HPA + `replicas` dans Git : Argo CD s'en plaint → `ignoreDifferences` sur `/spec/replicas`.
- `readyz` 503 : la base n'est pas prête, **normal** au démarrage (la readiness probe retire le Pod du Service le temps nécessaire).

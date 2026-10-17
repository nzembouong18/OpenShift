# RUNBOOK — vote-app (gabarit à compléter)

> Objectif : qu'une personne d'astreinte qui ne connaît pas l'application puisse déployer, diagnostiquer et restaurer en suivant ce document. Remplacez chaque `TODO`.

## 1. Vue d'ensemble
| Élément | Valeur |
|---|---|
| Propriétaire / équipe | TODO |
| Environnements | `vote-dev`, `vote-staging`, `vote-prod` |
| URL prod | TODO (`oc -n vote-prod get route vote`) |
| Dépôts | code : TODO · config GitOps : TODO |
| Dashboards | TODO (console → Observe → Dashboards) |
| SLO | TODO (ex. 99,5 % de requêtes `/api/*` < 500 ms et sans 5xx sur 30 jours) |
| Astreinte / escalade | TODO |

## 2. Déployer / promouvoir
1. Merge sur `main` du dépôt applicatif → PipelineRun Tekton (`tkn pipelinerun logs -f -L -n lab-cicd`).
2. Le pipeline met à jour le tag/digest dans l'overlay `dev` (commit automatique) → Argo CD synchronise.
3. Promotion : PR « dev → staging » puis « staging → prod » (revue obligatoire). Sync prod **manuelle** : `argocd app sync vote-prod`.
4. Vérifier : `oc -n vote-prod rollout status deploy/vote-api` ; `oc -n vote-prod get pods`.

## 3. Rollback
- GitOps (préféré) : `git revert <commit>` sur l'overlay → sync.
- Urgence : `argocd app rollback vote-prod <id>` ou `oc -n vote-prod rollout undo deploy/vote-api`.
- Après un rollback manuel, **réconcilier Git** (sinon la dérive sera annulée par Argo CD).

## 4. Diagnostic — 3 pannes probables

### 4.1 Route en 503 « Application is not available »
1. `oc -n vote-prod get endpoints vote-frontend vote-api` → vides ?
2. `oc -n vote-prod get pods` → `NotReady` ? `oc describe pod` → probes.
3. `oc get networkpolicy` → le Router est-il autorisé ?
4. Cause fréquente : base indisponible → `readyz` KO → plus d'endpoints api.

### 4.2 Erreurs 5xx / `/api/results` lent
1. Alerte `VoteApiHighErrorRate` ; Observe → Metrics : `sum(rate(http_requests_total{service="vote-api"}[5m])) by (status)`.
2. `oc -n vote-prod logs -l app=vote-api --tail=100`.
3. PostgreSQL : `oc -n vote-prod exec postgres-0 -- psql -U app -d vote -c "select count(*) from pg_stat_activity"`.
4. Saturation : `oc adm top pods -n vote-prod`, état du HPA.

### 4.3 PostgreSQL ne démarre pas / disque plein
1. `oc -n vote-prod describe pod postgres-0` ; `oc logs postgres-0`.
2. PVC : `oc get pvc` ; `oc exec postgres-0 -- df -h /var/lib/pgsql/data`.
3. Extension du volume : `oc patch pvc data-postgres-0 -p '{"spec":{"resources":{"requests":{"storage":"5Gi"}}}}'`.

## 5. Sauvegarde et restauration PostgreSQL
**Sauvegarde logique** (CronJob quotidien, stockage hors cluster) :
```bash
oc -n vote-prod exec postgres-0 -- pg_dump -U app -Fc vote > vote-$(date +%F).dump
```
**Restauration** :
```bash
oc -n vote-prod scale deploy/vote-api --replicas=0
oc -n vote-prod exec -i postgres-0 -- pg_restore -U app -d vote --clean --if-exists < vote-YYYY-MM-DD.dump
oc -n vote-prod scale deploy/vote-api --replicas=3
```
**Sauvegarde de l'ensemble du projet** : OADP (`Backup` du namespace `vote-prod`). Test de restauration : TODO (date, résultat). RPO/RTO cibles : TODO.

## 6. Maintenance
- Drain d'un nœud : PDB `minAvailable: 1` sur api et frontend → `oc adm drain <node> --ignore-daemonsets --delete-emptydir-data`.
- Mise à jour d'image de base : rebuild automatique (trigger ImageStream) → pipeline → PR de promotion.
- Rotation des secrets : TODO.

## 7. Contacts et liens
TODO

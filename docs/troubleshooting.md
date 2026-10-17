# Troubleshooting OpenShift

## Méthode en 5 questions
1. **Quoi ?** (`oc get`, `oc status`) → objet et état.
2. **Pourquoi ?** (`oc describe`, `oc get events`) → section Events.
3. **Que dit l'application ?** (`oc logs`, `-p`).
4. **Qui a le droit ?** (`oc auth can-i`, SCC, quotas).
5. **Qu'est-ce qui a changé ?** (`oc rollout history`, Git, `oc get events`, Argo CD diff).

## Pods
| Symptôme | Causes | Commandes / correctif |
|---|---|---|
| `ImagePullBackOff` / `ErrImagePull` | tag erroné, registre privé sans secret, quota Docker Hub, ImageStream non lisible | `oc describe pod`, `oc secrets link default <pull-secret> --for=pull`, `oc policy add-role-to-user system:image-puller` |
| `CrashLoopBackOff` | application qui plante, probe, config manquante | `oc logs -p`, `oc debug deploy/x` |
| `CreateContainerConfigError` | ConfigMap/Secret absent, clé erronée | `oc describe pod` |
| `Pending` | ressources, quota, PVC non lié, taint, nodeSelector, SCC | `oc describe pod`, `oc describe quota`, `oc get pvc` |
| `OOMKilled` | limite mémoire trop basse / fuite | `oc describe pod` (Last State), augmenter, profiler |
| `Error: container has runAsNonRoot and image will run as root` | image exigeant root | image non-root ou SCC dédiée à un SA |
| `forbidden: unable to validate against any security context constraint` | UID/volume/capacité interdit | `oc describe pod`/ReplicaSet events, `oc adm policy scc-subject-review` |
| `permission denied` à l'écriture | répertoire non inscriptible pour GID 0 | `chgrp -R 0 dir && chmod -R g=u dir` dans l'image, ou `emptyDir` |
| Pod `Terminating` bloqué | finalizer, nœud perdu | `oc delete pod --force --grace-period=0` (dernier recours) |

## Builds
| Symptôme | Piste |
|---|---|
| Build `Pending` | quota, ressources du Pod de build, SCC du SA `builder` |
| `fatal: unable to access` (git) | proxy/CA, dépôt privé → `sourceSecret` |
| Échec `assemble` | logs du build, variables (`NPM_MIRROR`, `PIP_INDEX_URL`), version du builder |
| Push refusé | droits sur l'ImageStream cible ; nom de l'ImageStreamTag |
| Image toujours ancienne | déclencheur manquant, tag `latest` mis en cache → `oc set triggers` / déployer par digest |

## Réseau
| Symptôme | Piste |
|---|---|
| Route « Application is not available » | aucun endpoint Ready : `oc get ep`, probes, labels/selector |
| Route timeout | NetworkPolicy, mauvais `targetPort`, application sur 127.0.0.1 |
| Cert warning | edge avec certificat par défaut → fournir certificat, ou `curl -k` en lab |
| Service injoignable depuis un autre projet | NetworkPolicy ; DNS `svc.ns.svc.cluster.local` |
| DNS lent | `ndots:5`, FQDN avec point final, `dns.operator` forward |
| Connexion externe bloquée | `EgressFirewall`, proxy cluster |

## Stockage
| Symptôme | Piste |
|---|---|
| PVC `Pending` | pas de StorageClass par défaut, quota, `WaitForFirstConsumer` (normal tant qu'aucun Pod) |
| `Multi-Attach error` | RWO sur 2 nœuds → `Recreate`, ou RWX |
| `permission denied` sur volume | fsGroup/SELinux ; ne pas monter un `hostPath` |
| PVC plein | `allowVolumeExpansion`, `oc patch pvc` |

## Authentification / RBAC
| Symptôme | Piste |
|---|---|
| `error: You must be logged in` | jeton expiré → `oc login` |
| `forbidden` | `oc auth can-i`, `oc policy who-can`, RoleBinding du bon projet |
| IdP inopérant | `oc get pods -n openshift-authentication`, `oc logs`, secret `htpass-secret` |

## Operators / OLM
Voir module 08 §1.7. Commandes : `oc get sub,ip,csv -A`, `oc get catalogsource -n openshift-marketplace`, `oc logs -n openshift-operator-lifecycle-manager deploy/olm-operator`.

## Cluster
| Symptôme | Piste |
|---|---|
| `ClusterOperator` Degraded | `oc describe co/<nom>` → conditions + `relatedObjects` ; logs du namespace de l'Operator |
| Nœud NotReady | `oc describe node`, `oc adm node-logs <n> -u kubelet`, CSR en attente, disque plein |
| MCP bloqué (`UPDATING` depuis longtemps) | nœud qui ne se draine pas (PDB), `oc describe node` annotations MCO |
| Upgrade bloquée | `oc get co`, `oc adm upgrade`, Operator OLM incompatible, `ClusterVersion` conditions |
| etcd lent | disques, `etcdHighFsyncDurations`, défragmentation |
| CRC ne démarre pas | `crc cleanup && crc setup`, mémoire, virtualisation, DNS `*.crc.testing` |
| API `x509: certificate has expired` (CRC) | rallumer, attendre rotation, `oc get csr` + approuver |

## Collecte pour le support
`oc adm must-gather`, `oc adm inspect`, `sosreport` (via `oc debug node`), version exacte : `oc get clusterversion`.

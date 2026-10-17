# Module 05 — Réseau : Services, Routes, Ingress, NetworkPolicy

⏱ 4 h · 🟡

## Objectifs
- Exposer des applications avec **Services** et **Routes** (HTTP, TLS edge/passthrough/re-encrypt)
- Comprendre le **Router (HAProxy)** et l'`IngressController`
- Isoler le trafic (NetworkPolicy, AdminNetworkPolicy), maîtriser l'egress
- Connaître OVN-Kubernetes, Multus, DNS

## 1. Cours

### 1.1 Chemin d'une requête
```
Client ─► DNS (*.apps.<cluster>) ─► LB/VIP ─► Router (HAProxy, Pods openshift-ingress)
        ─► Endpoints du Service (Pods Ready) ─► Pod (port conteneur)
```
- Wildcard DNS `*.apps.<domaine>` → VIP/LB des nœuds qui portent le router.
- Le Router lit les **Routes**, génère `haproxy.config` et route par en-tête `Host` (HTTP) ou SNI (TLS).
- Il envoie le trafic **directement aux Pods** (Endpoints), sans passer par le ClusterIP.

### 1.2 Services
`ClusterIP` (défaut), `NodePort`, `LoadBalancer` (cloud ou MetalLB), `ExternalName`, **headless** (`clusterIP: None`). DNS : `<svc>.<ns>.svc.cluster.local`. Une Route cible un **Service** (pas un Pod).

### 1.3 Routes
```yaml
apiVersion: route.openshift.io/v1
kind: Route
spec:
  host: app.apps.example.com      # optionnel, sinon <nom>-<projet>.<domaine>
  to: {kind: Service, name: web, weight: 100}
  port: {targetPort: http}
  tls: {termination: edge, insecureEdgeTerminationPolicy: Redirect}
```
| Terminaison | TLS jusqu'au Router ? | TLS Router→Pod ? | Usage |
|---|---|---|---|
| *(aucune)* | ❌ | ❌ | HTTP simple |
| **edge** | ✅ (certificat du Router ou le vôtre) | ❌ | cas courant |
| **passthrough** | ✅ de bout en bout | ✅ (le Pod déchiffre) | mTLS applicatif, SNI |
| **re-encrypt** | ✅ | ✅ (nouveau TLS vers le Pod) | conformité |

`insecureEdgeTerminationPolicy` : `Redirect` (HTTP→HTTPS), `Allow`, `None`.

Fonctions avancées (annotations `haproxy.router.openshift.io/*`) :
| Annotation | Effet |
|---|---|
| `timeout` | délai de réponse (ex. `60s`) |
| `balance` | `roundrobin`, `leastconn`, `source` |
| `rate-limit-connections*` | limitation de débit |
| `ip_whitelist` | liste blanche CIDR |
| `disable_cookies` / `router.openshift.io/cookie_name` | affinité de session |
| `hsts_header` | HSTS |

**Répartition de trafic (A/B, canary)** : `spec.alternateBackends` + poids (`weight` 0-256).
```bash
oc set route-backends vote-route vote-v1=90 vote-v2=10
```

### 1.4 Ingress Kubernetes et Gateway API
- Un objet `Ingress` K8s est **converti en Route** par l'Ingress Controller Operator (annotations `route.openshift.io/termination`).
- **Gateway API** : supportée par OpenShift (4.19+ en GA via Ingress Operator / Service Mesh 3). À privilégier pour les nouveaux besoins multi-protocoles.
- Réserver `Route` pour la richesse OpenShift (poids, re-encrypt, passthrough simple).

### 1.5 IngressController (🔑)
Le router par défaut est géré par `IngressController/default` (`openshift-ingress-operator`). Vous pouvez créer des **shards** (plusieurs routers par `routeSelector`/`namespaceSelector`, ex. `internal` vs `public`), changer le domaine, activer les logs d'accès, ajuster `replicas`, `nodePlacement`, `endpointPublishingStrategy`, certificat par défaut (`defaultCertificate`), TLS minimal (`tlsSecurityProfile`).
```bash
oc get ingresscontroller default -n openshift-ingress-operator -o yaml
oc patch ingresscontroller/default -n openshift-ingress-operator --type=merge -p '{"spec":{"replicas":3}}'
```

### 1.6 Certificats
- Certificat **par route** : `tls.certificate`, `key`, `caCertificate` (secret exposé dans la Route ; préférer l'automatisation).
- **cert-manager Operator** : Issuer ACME/Vault/CA, émission automatique, annotation `cert-manager.io/issuer-kind` + Ingress, ou `Certificate` + route-controller (`openshift-routes`).
- **Service CA** : annotation `service.beta.openshift.io/serving-cert-secret-name=<secret>` sur un Service → certificat signé par la CA interne du cluster (pour re-encrypt/mTLS internes). Le CA se récupère en ConfigMap annotée `service.beta.openshift.io/inject-cabundle=true`.

### 1.7 Réseau de Pods : OVN-Kubernetes
| Aspect | OVN-Kubernetes (défaut ≥ 4.12) |
|---|---|
| Overlay | Geneve, sous-réseau Pods `10.128.0.0/14`, Services `172.30.0.0/16` (par défaut) |
| NetworkPolicy | ✅ (implémentée en ACL OVN) |
| EgressIP / EgressFirewall / EgressService | ✅ |
| AdminNetworkPolicy / BaselineAdminNetworkPolicy | ✅ (politique d'administrateur, prioritaire sur les projets) |
| Multicast, IPsec, hybrid overlay (Windows) | ✅ |
| User Defined Networks (UDN) | réseaux secondaires/primaires par namespace (4.17+) |

OpenShift SDN est **retiré** (migration obligatoire pour les anciens clusters).

### 1.8 Isoler : NetworkPolicy
Par défaut tout est ouvert dans le cluster. Schéma recommandé :
1. `default-deny` (Ingress) dans chaque projet ;
2. autoriser le **Router** : `namespaceSelector` sur le label `network.openshift.io/policy-group: ingress` (équivalent : `policy-group.network.openshift.io/ingress: ""`) ;
3. autoriser le **monitoring** : label `network.openshift.io/policy-group: monitoring` ;
4. autoriser les flux applicatifs précis (labels de Pods) ;
5. maîtriser l'egress (`EgressNetworkPolicy`/`EgressFirewall`).

### 1.9 Egress
| Besoin | Solution |
|---|---|
| IP source stable vers l'extérieur | `EgressIP` (🔑) + label de nœud/namespace |
| Filtrer les destinations | `EgressFirewall` (CRD `k8s.ovn.org/v1`, objet unique nommé `default` par projet) |
| Passer par un proxy | variables `HTTP_PROXY` + proxy cluster (`proxy/cluster`) |

### 1.10 DNS
CoreDNS (`openshift-dns`). Pod → `<svc>`, `<svc>.<ns>`, `<svc>.<ns>.svc`. `dnspolicy`, `ndots:5` (peut ralentir les résolutions externes : utiliser des FQDN avec un point final). Opérateur DNS : zones forwarding personnalisées (`dns.operator/default` → `servers`).

### 1.11 Réseaux secondaires : Multus
`NetworkAttachmentDefinition` + annotation `k8s.v1.cni.cncf.io/networks`. CNI : macvlan, ipvlan, bridge, SR-IOV (Operator dédié), host-device. Usage : télécom, trafic isolé, bases de données, VM.

### 1.12 LoadBalancer on-prem : MetalLB
Operator MetalLB : `IPAddressPool` + `L2Advertisement` ou `BGPPeer`/`BGPAdvertisement` → Services `type: LoadBalancer` fonctionnels hors cloud.

## 2. 🎬 Démo (50 min)

```bash
oc new-project lab-reseau
oc apply -f manifests/01-app-service-route.yaml
oc get svc,route,endpoints
curl -I http://$(oc get route web -o jsonpath='{.spec.host}')          # 302 vers https
curl -kI https://$(oc get route web -o jsonpath='{.spec.host}')
# A/B routing
oc apply -f manifests/02-route-ab.yaml ; for i in $(seq 20); do curl -s http://$(oc get route ab -o jsonpath='{.spec.host}') | grep -o 'v[12]'; done | sort | uniq -c
# Passthrough vs edge vs re-encrypt : montrer les 3 variantes (manifests/03-routes-tls.yaml)
# NetworkPolicy
oc apply -f manifests/04-networkpolicies.yaml
oc run tester --rm -it --image=registry.access.redhat.com/ubi9/ubi-minimal -- curl -m3 web:8080     # bloqué
# Router en coulisses
oc -n openshift-ingress rsh deploy/router-default grep -A8 'backend be_http:lab-reseau:web' /var/lib/haproxy/conf/haproxy.config
```

## 3. 🧪 Labos

> Projet : `lab-reseau`

### Lab 5.1 ⭐ — Service et Route
Déployez `web` (manifest 01), vérifiez Endpoints, testez la Route en HTTP et HTTPS. Que fait `insecureEdgeTerminationPolicy: Redirect` ?

<details><summary>Corrigé</summary>

```bash
oc apply -f manifests/01-app-service-route.yaml
curl -sI http://$(oc get route web -o jsonpath='{.spec.host}') | head -3   # 302 Location: https://...
```
</details>

### Lab 5.2 ⭐ — Service sans Endpoint
Modifiez le `selector` du Service pour une faute de frappe. Diagnostic : `oc get endpoints`, route `503 Application is not available`.

<details><summary>Corrigé</summary>

```bash
oc patch svc web -p '{"spec":{"selector":{"app":"wbe"}}}'
oc get endpoints web          # <none>
curl -k https://$(oc get route web -o jsonpath='{.spec.host}')    # page "Application is not available"
oc patch svc web -p '{"spec":{"selector":{"app":"web"}}}'
```
</details>

### Lab 5.3 ⭐⭐ — Canary 90/10
Déployez `app-v1` / `app-v2` (manifest 02). Routez 90/10 puis 50/50, puis 0/100. Mesurez la répartition avec une boucle `curl`.

<details><summary>Corrigé</summary>

```bash
oc set route-backends ab app-v1=90 app-v2=10
oc set route-backends ab app-v1=50 app-v2=50
oc set route-backends ab app-v1=0  app-v2=100
```
Les réponses sont `v1` ou `v2` selon un `ConfigMap`/echo ; l'affinité de cookie peut fausser le test : utiliser `curl` sans cookie jar.
</details>

### Lab 5.4 ⭐⭐ — TLS edge avec certificat personnalisé
Générez un certificat auto-signé pour `secure.apps...`, créez une route edge via `oc create route edge --cert --key`.

<details><summary>Corrigé</summary>

```bash
HOST=secure.$(oc get ingresses.config/cluster -o jsonpath='{.spec.domain}')
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -keyout tls.key -out tls.crt -subj "/CN=$HOST" -addext "subjectAltName=DNS:$HOST"
oc create route edge secure --service=web --hostname=$HOST --cert=tls.crt --key=tls.key --insecure-policy=Redirect
curl --cacert tls.crt https://$HOST --resolve $HOST:443:<ip-router>
```
</details>

### Lab 5.5 ⭐⭐⭐ — Re-encrypt avec Service CA
Annotez un Service pour obtenir un certificat serveur automatique, faites écouter nginx en HTTPS, publiez une route `reencrypt` avec `destinationCACertificate`.

<details><summary>Corrigé</summary>
Voir `manifests/03-routes-tls.yaml` : annotation `service.beta.openshift.io/serving-cert-secret-name: web-tls`, montage du secret dans le Pod, route `termination: reencrypt` ; le CA de destination est celui de `openshift-service-ca.crt` (`oc get cm openshift-service-ca.crt -o jsonpath='{.data.service-ca\.crt}'`).
</details>

### Lab 5.6 ⭐⭐ — NetworkPolicy
Appliquez `manifests/04-networkpolicies.yaml` : default-deny + autorisation Router + `client → web`. Vérifiez qu'un Pod étranger est bloqué et que la Route fonctionne toujours.

<details><summary>Corrigé</summary>

```bash
oc label ns lab-reseau name=lab-reseau --overwrite
oc run intrus --rm -it --restart=Never --image=registry.access.redhat.com/ubi9/ubi-minimal -- curl -m3 web:8080   # timeout
oc run client --rm -it --restart=Never --labels=role=client --image=registry.access.redhat.com/ubi9/ubi-minimal -- curl -m3 web:8080   # OK
```
Si la Route tombe en 503/timeout, la policy qui autorise le Router est absente ou mal étiquetée : `network.openshift.io/policy-group: ingress`.
</details>

### Lab 5.7 ⭐⭐⭐ — Egress Firewall 🔑
Interdisez tout egress vers Internet sauf `registry.access.redhat.com` depuis le projet.

<details><summary>Corrigé</summary>
Voir `manifests/05-egress.yaml` (`EgressFirewall` nommé `default`). Test : `oc run t --rm -it --image=ubi-minimal -- curl -m3 https://example.com` (échec) vs `https://registry.access.redhat.com`.
</details>

### Lab 5.8 ⭐⭐⭐ — Router : shard interne 🔑
Créez un `IngressController` `internal` (domaine `internal.apps...`) sélectionnant les routes avec le label `type=internal`, puis une route associée.

<details><summary>Corrigé</summary>
Voir `manifests/06-ingresscontroller-shard.yaml`. Le DNS wildcard du nouveau domaine doit exister (sur cloud IPI, l'Operator crée l'enregistrement ; sinon l'ajouter vous-même).
</details>

### Lab 5.9 ⭐⭐⭐⭐ — Observer le chemin réseau
À l'aide de `oc debug node`, `ovs-vsctl`, `ovn-nbctl` (pods `ovnkube-node`) et `tcpdump`, tracez la traversée d'un paquet client → Route → Pod. Documentez chaque saut.

<details><summary>Corrigé</summary>

```bash
oc -n openshift-ovn-kubernetes get pods -o wide
oc -n openshift-ovn-kubernetes exec -it ovnkube-node-xxxxx -c ovnkube-controller -- ovn-nbctl --no-leader-only show | head
oc debug node/<n> -- chroot /host tcpdump -nn -i any port 8080 -c 20
```
Sauts : client → VIP/LB → hostNetwork Router → (OVN Geneve) → veth du Pod. `oc adm must-gather -- /usr/bin/gather_network_logs` collecte la même information.
</details>

## 4. Quiz
1. Quelle ressource OpenShift expose un Service en HTTP(S) ? → `Route`.
2. Edge vs passthrough ? → TLS terminé au Router vs jusqu'au Pod.
3. Comment répartir 10 % du trafic vers v2 ? → `alternateBackends` / `oc set route-backends`.
4. Quelle étiquette autorise le Router dans une NetworkPolicy ? → `network.openshift.io/policy-group: ingress` (porté par le namespace `openshift-ingress`).
5. Quel CNI par défaut ? → OVN-Kubernetes.

Nettoyage : `oc delete project lab-reseau`

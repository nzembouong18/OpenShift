# Aide-mémoire `oc`

## Session et navigation
```bash
oc login -u <user> https://api.<cluster>:6443          oc login --token=<tok> --server=...
oc whoami ; oc whoami -t ; oc whoami --show-console ; oc whoami --show-server
oc projects ; oc project <p> ; oc new-project <p> ; oc delete project <p>
oc config get-contexts ; oc config use-context <c>
```
## Lire
```bash
oc get pods|svc|route|deploy|bc|build|is|istag|pvc|cm|secret -n <p> -o wide|yaml|json
oc get all ; oc status ; oc get events --sort-by=.lastTimestamp
oc describe <type>/<nom> ; oc explain <type>.spec --recursive
oc get <type> -o jsonpath='{.items[*].metadata.name}'
oc get <type> -o custom-columns=NAME:.metadata.name,IMG:.spec.containers[0].image
oc api-resources ; oc api-versions
oc logs [-f] [-p] [-c <ctr>] [--since=10m] pod/<p> | deploy/<d> | bc/<b>
```
## Créer / modifier
```bash
oc apply -f x.yaml ; oc apply -k overlays/dev ; oc create -f x.yaml ; oc delete -f x.yaml
oc create deployment web --image=... --replicas=2 --dry-run=client -o yaml
oc new-app --image=... | <git-url> | -f template.yaml -p K=V ; oc new-app python:3.12-ubi9~<git-url>
oc expose svc/web ; oc create route edge|passthrough|reencrypt <nom> --service=...
oc set image deploy/web web=img:tag ; oc set env deploy/web K=V ; oc set resources deploy/web --requests=cpu=50m,memory=64Mi
oc set probe deploy/web --readiness --get-url=http://:8080/ ; oc set volume deploy/web --add ...
oc scale deploy/web --replicas=3 ; oc autoscale deploy/web --min=2 --max=6 --cpu-percent=60
oc label|annotate <type>/<nom> k=v ; oc patch <type>/<nom> -p '{...}' ; oc edit <type>/<nom>
```
## Builds et images
```bash
oc new-build --name=app --binary --strategy=docker ; oc start-build app --from-dir=. --follow
oc start-build bc/app ; oc cancel-build build/app-1 ; oc logs -f bc/app
oc import-image is:tag --from=<registry>/<img> --confirm [--scheduled]
oc tag src:tag dst:tag ; oc get is,istag ; oc set triggers deploy/web --from-image=web:latest -c web
oc policy add-role-to-user system:image-puller -z default -n <src>
```
## Déploiement
```bash
oc rollout status|history|undo|restart|pause|resume deploy/web
oc rollout latest dc/legacy       # DeploymentConfig (legacy)
oc set route-backends <route> v1=90 v2=10
```
## Debug
```bash
oc rsh pod/x ; oc exec pod/x -- cmd ; oc port-forward pod/x 8080:8080 ; oc cp pod:/path ./path
oc debug deploy/web ; oc debug node/<n> -- chroot /host bash ; oc debug pod/x --as-root
oc run tmp --rm -it --image=registry.access.redhat.com/ubi9/ubi-minimal -- bash
oc adm top pods|nodes ; oc adm node-logs <node> -u kubelet|crio
oc adm must-gather --dest-dir=./mg ; oc adm inspect ns/<p>
```
## RBAC / sécurité
```bash
oc auth can-i <verbe> <ressource> [--as=<user>] -n <p> ; oc policy who-can <verbe> <ressource>
oc adm policy add-role-to-user|group <role> <sujet> -n <p> ; oc adm policy add-cluster-role-to-user ...
oc create sa <sa> ; oc create token <sa> ; oc secrets link <sa> <secret> --for=pull
oc adm policy add-scc-to-user <scc> -z <sa> ; oc adm policy scc-review|scc-subject-review ...
oc get scc ; oc describe scc restricted-v2
```
## Administration (🔑)
```bash
oc get clusterversion,co,nodes,mcp,csr ; oc adm upgrade [--to=...] ; oc adm upgrade channel stable-4.N
oc adm cordon|uncordon|drain <node> --ignore-daemonsets --delete-emptydir-data
oc get machineset,machine -n openshift-machine-api ; oc scale machineset <ms> --replicas=N -n openshift-machine-api
oc get operatorhub,catalogsource,sub,ip,csv -A ; oc get packagemanifest -n openshift-marketplace
oc adm certificate approve <csr> ; oc adm prune builds|deployments|images --confirm
oc debug node/<cp> -- chroot /host /usr/local/bin/cluster-backup.sh /home/core/assets/backup
```
## Pièges de syntaxe
- `oc get all` ne montre pas Route/ConfigMap/Secret/PVC… `oc get all,cm,secret,pvc,route`
- `-n` après la sous-commande ; `--all-namespaces`/`-A` pour tous les projets
- `oc delete project` est asynchrone (`Terminating`)
- Ctrl-C sur `oc logs -f` ne tue pas le build

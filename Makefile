PULL_SECRET ?= $(HOME)/pull-secret.txt
CRC_CPUS    ?= 6
CRC_MEMORY  ?= 16384
CRC_DISK    ?= 60

.PHONY: crc-setup crc-start crc-stop crc-delete login check clean-labs lint operators-info

crc-setup: ## Prépare OpenShift Local (une seule fois)
	crc config set cpus $(CRC_CPUS)
	crc config set memory $(CRC_MEMORY)
	crc config set disk-size $(CRC_DISK)
	crc config set consent-telemetry no
	crc setup

crc-start: crc-setup ## Démarre OpenShift Local (nécessite le pull secret Red Hat)
	crc start -p $(PULL_SECRET)
	@echo "Identifiants : crc console --credentials"

crc-stop: ## Arrête OpenShift Local
	crc stop

crc-delete: ## Supprime la VM OpenShift Local
	crc delete -f

login: ## Se connecte en kubeadmin (CRC)
	eval $$(crc oc-env) && oc login -u kubeadmin -p "$$(crc console --credentials -o json | python3 -c 'import sys,json; print(json.load(sys.stdin)["clusterConfig"]["adminCredentials"]["password"])')" https://api.crc.testing:6443

check: ## Vérifie l'environnement
	./00-setup/scripts/check-env.sh

operators-info: ## Liste les canaux par défaut des Operators utilisés (module 08-12)
	@for p in openshift-pipelines-operator-rh openshift-gitops-operator serverless-operator servicemeshoperator3 kubevirt-hyperconverged cluster-logging loki-operator; do \
	  printf '%-40s' $$p; oc get packagemanifest $$p -n openshift-marketplace -o jsonpath='{.status.defaultChannel}' 2>/dev/null || printf 'indisponible'; echo; done

clean-labs: ## Supprime tous les projets de labs
	oc get project -o name | grep 'project.project.openshift.io/lab-' | xargs -r oc delete

lint: ## Valide la syntaxe YAML de tous les manifests et du code Python du fil rouge
	python3 -c "import sys,glob,yaml; fs=glob.glob('**/manifests/**/*.yaml',recursive=True); [list(yaml.safe_load_all(open(f))) for f in fs]; print('YAML OK (%d fichiers)' % len(fs))"
	python3 -m py_compile 13-projet-final/app/app.py && echo "Python OK"
	for e in dev staging prod; do kubectl kustomize 13-projet-final/manifests/overlays/$$e >/dev/null && echo "Kustomize $$e OK"; done

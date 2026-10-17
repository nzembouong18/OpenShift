# Glossaire

| Terme | Définition |
|---|---|
| **OCP / OKD** | OpenShift Container Platform (produit) / sa base communautaire |
| **CRC (OpenShift Local)** | OpenShift mono-nœud dans une VM, pour poste de dev |
| **Project** | namespace enrichi (annotations, RBAC, quotas) |
| **Route** | exposition HTTP(S)/TLS via le Router HAProxy |
| **Router / IngressController** | HAProxy qui sert les Routes |
| **S2I (Source-to-Image)** | construction d'image applicative à partir de code et d'une image builder |
| **BuildConfig / Build** | définition / exécution d'un build |
| **ImageStream (IS/ISTag)** | pointeur logique vers des images ; déclenche builds/déploiements |
| **DeploymentConfig** | ancien contrôleur de déploiement, déprécié |
| **SCC** | SecurityContextConstraints : politique d'admission des Pods |
| **PSA** | Pod Security Admission (privileged/baseline/restricted) |
| **OAuth server** | serveur d'authentification intégré |
| **IdP** | Identity Provider (HTPasswd, LDAP, OIDC…) |
| **CVO** | Cluster Version Operator : met à jour la plateforme |
| **Cluster Operator** | Operator de composant de plateforme (`oc get co`) |
| **MCO / MachineConfig / MCP** | gestion de l'OS des nœuds (Ignition + rpm-ostree) |
| **RHCOS** | Red Hat Enterprise Linux CoreOS, OS immuable des nœuds |
| **Ignition** | outil de configuration au premier démarrage |
| **Machine API / MachineSet** | provisioning déclaratif des nœuds |
| **OLM** | Operator Lifecycle Manager |
| **CatalogSource / Subscription / InstallPlan / CSV** | objets OLM (catalogue, abonnement, plan, version installée) |
| **OperatorHub** | catalogue d'Operators de la console |
| **UWM** | User Workload Monitoring |
| **ServiceMonitor / PrometheusRule** | cibles de scrape / règles et alertes |
| **LokiStack / ClusterLogForwarder** | stockage de logs / pipeline de collecte (Logging 6) |
| **OVN-Kubernetes** | CNI par défaut |
| **EgressIP / EgressFirewall** | IP source fixe / filtrage sortant |
| **Multus** | réseaux secondaires |
| **ODF / LVMS** | stockage Ceph / stockage LVM local |
| **OADP** | sauvegarde/restauration (Velero) |
| **Tekton / Pipelines as Code** | CI cloud-native / pipelines versionnés avec le code |
| **Argo CD / OpenShift GitOps** | livraison continue GitOps |
| **ACM** | Advanced Cluster Management (gestion de flotte) |
| **ACS (StackRox)** | Advanced Cluster Security |
| **HCP (HyperShift)** | Hosted Control Planes |
| **SNO** | Single Node OpenShift |
| **KubeVirt / OpenShift Virtualization** | machines virtuelles dans OpenShift |
| **KEDA** | autoscaling événementiel (Custom Metrics Autoscaler) |
| **Knative** | serverless (Serving/Eventing) |
| **must-gather** | outil de collecte de diagnostics |

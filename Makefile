#!/usr/bin/make

include .env

.SILENT: post-help

all: cluster flannel metallb helm metrics traefik dashboard prometheus post-help

docker-install:
	sudo apt-get update
	sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu `lsb_release -cs` stable"
	sudo apt-get update
	sudo apt-get install docker-ce docker-ce-cli containerd.io
	sudo usermod -aG docker `id -un`

kubectl-install:
	sudo apt-get update && sudo apt-get install -y apt-transport-https gnupg2 curl
	curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
	echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
	sudo apt-get update
	sudo apt-get install -y kubectl

	echo 'source <(kubectl completion bash)' >>~/.bashrc
	source <(kubectl completion bash)

kind-install:
	curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64
	chmod +x /tmp/kind
	sudo mv /tmp/kind /usr/local/bin

	echo 'source <(kind completion bash)' >>~/.bashrc
	source <(kind completion bash)

cluster:
	@tput setaf 6; echo "\nmake $@\n"; tput sgr0

	kind create cluster --name ${CLUSTER_NAME} --config=kind-config.yaml --wait=${KIND_WAIT}
	kubectl cluster-info --context kind-${CLUSTER_NAME}

	kubectl wait --for=condition=Ready --timeout=${KIND_WAIT} -A pod --all || echo 'TIMEOUT' >&2

flannel:
	@tput setaf 6; echo "\nmake $@\n"; tput sgr0

	# https://medium.com/swlh/customise-your-kind-clusters-networking-layer-1249e7916100
	#curl -sfL https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml > /tmp/kube-flannel.yml
	#kubectl apply -f /tmp/kube-flannel.yml

	#kubectl scale deployment --replicas 1 coredns --namespace kube-system

metallb:
	@tput setaf 6; echo "\nmake $@\n"; tput sgr0

	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/manifests/namespace.yaml
	kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/manifests/metallb.yaml
	kubectl create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"

	cat metallb-config.yaml | METALLB_POOL=${METALLB_POOL} envsubst | kubectl apply -f -

	kubectl wait --for=condition=Ready --timeout=${METALLB_WAIT} -n metallb-system pod --all || echo 'TIMEOUT' >&2

helm:
	@tput setaf 6; echo "\nmake $@\n"; tput sgr0

	curl -sfL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

	helm repo add stable https://charts.helm.sh/stable
	helm repo update

metrics:
ifeq (${DO_METRICS}, true)
	@tput setaf 6; echo "\nmake $@\n"; tput sgr0

	helm install metrics-server stable/metrics-server --version ${METRICS_VERSION} --set 'args={--kubelet-insecure-tls, --kubelet-preferred-address-types=InternalIP}' --namespace kube-system

	kubectl wait --for=condition=Available --timeout=${METRICS_WAIT} -n kube-system  deployment.apps/metrics-server || echo 'TIMEOUT' >&2

endif

traefik:
	@tput setaf 6; echo "\nmake $@\n"; tput sgr0

	cat traefik-config.yaml | OAM_DOMAIN=${OAM_DOMAIN} OAM_IP=${OAM_IP} envsubst | helm install traefik stable/traefik --version 1.81.0 --namespace kube-system -f -

	kubectl wait --for=condition=Available --timeout=${TRAEFIK_WAIT} -n kube-system  deployment.apps/traefik || echo 'TIMEOUT' >&2

dashboard:
	@tput setaf 6; echo "\nmake $@\n"; tput sgr0

	kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/${DASHBOARD_VERSION}/aio/deploy/alternative.yaml

	cat dashboard-config.yaml | OAM_DOMAIN=${OAM_DOMAIN} envsubst | kubectl apply -f -

	kubectl wait --for=condition=Available -n kubernetes-dashboard deployment/kubernetes-dashboard || echo 'TIMEOUT' >&2

prometheus:
ifeq (${DO_PROMETHEUS}, true)
	@tput setaf 6; echo "\nmake $@\n"; tput sgr0

	kubectl create namespace ${PROMETHEUS_NAMESPACE} --dry-run -o yaml | kubectl apply -f -

	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update

	cat prometheus-values.yaml | OAM_DOMAIN=${OAM_DOMAIN} envsubst | helm install ${PROMETHEUS_HELM_RELEASE_NAME} prometheus-community/kube-prometheus-stack -n ${PROMETHEUS_NAMESPACE} --version ${PROMETHEUS_CHART_VERSION} -f -

	kubectl wait --for=condition=Ready --timeout=${PROMETHEUS_WAIT} -n ${PROMETHEUS_NAMESPACE} pod --all || echo 'TIMEOUT' >&2
endif

prometheus-cleanup:
ifeq (${DO_PROMETHEUS}, true)
	helm uninstall ${PROMETHEUS_HELM_RELEASE_NAME} -n ${PROMETHEUS_NAMESPACE}

	kubectl delete crd alertmanagerconfigs.monitoring.coreos.com
	kubectl delete crd alertmanagers.monitoring.coreos.com
	kubectl delete crd podmonitors.monitoring.coreos.com
	kubectl delete crd probes.monitoring.coreos.com
	kubectl delete crd prometheuses.monitoring.coreos.com
	kubectl delete crd prometheusrules.monitoring.coreos.com
	kubectl delete crd servicemonitors.monitoring.coreos.com
	kubectl delete crd thanosrulers.monitoring.coreos.com

endif

post-help:
	@tput setaf 6; echo "\nmake $@\n"; tput sgr0

	echo "Add below line to /etc/host:\n${OAM_IP} ${OAM_DOMAIN}"

	echo "\nTraefik URL:\nhttp://${OAM_DOMAIN}/dashboard/"

	echo "\nDashboard URL:\nhttps://${OAM_DOMAIN}/kubernetes/"

	echo "\nDashboard login token:"
	kubectl -n kubernetes-dashboard describe secret admin-user-token | grep ^token

	echo "\nPrometheus URL:\nhttps://${OAM_DOMAIN}/prometheus/"

	echo "\nAlertmanager URL:\nhttps://${OAM_DOMAIN}/alertmanager/"

	echo "\nGrafana URL:\nhttps://${OAM_DOMAIN}/grafana/"

destroy:
	kind delete cluster --name ${CLUSTER_NAME}

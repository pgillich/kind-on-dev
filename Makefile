#!/usr/bin/make

SHELL := bash

UNAME := $(shell uname)

ifeq ($(UNAME), Linux)
vagrant = docker run -it --rm -e LIBVIRT_DEFAULT_URI -v /var/run/libvirt/:/var/run/libvirt/ \
	-v ~/.vagrant.d:/.vagrant.d -v $$(pwd):$$(pwd) -w $$(pwd) --network host pgillich/vagrant-libvirt:latest \
	vagrant
else
vagrant = PATH=$$(cygpath "$$WINDIR/System32/OpenSSH"):$$PATH vagrant
endif

helm-repo-stable = (helm repo add stable https://charts.helm.sh/stable && helm repo update stable)

include .env

.PHONY: all
all: cluster metrics istio kiali dashboard telemetry info-post

.PHONY: install-docker
install-docker:
	sudo apt-get update
	sudo apt-get install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
	curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
	sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu `lsb_release -cs` stable"
	sudo apt-get update
	sudo apt-get install docker-ce docker-ce-cli containerd.io
	sudo usermod -aG docker `id -un`

	sudo cp docker-daemon.json /etc/docker/daemon.json
	sudo systemctl daemon-reload
	sudo systemctl restart docker

	@tput setaf 3; echo -e "\nLogout and login to reload group rights!\n"; tput sgr0

.PHONY: install-kubectl
install-kubectl:
	sudo apt-get update && sudo apt-get install -y apt-transport-https gnupg2 curl
	curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
	echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list
	sudo apt-get update
	sudo apt-get install -y kubectl

	mkdir -p ~/.kube

	echo >>~/.bashrc
	echo 'source <(kubectl completion bash)' >>~/.bashrc

	@tput setaf 3; echo -e "\nStart a new shell to load kubectl completion!\n"; tput sgr0

.PHONY: install-k3s
install-k3s: destroy-k3s

.PHONY: install-k3d
install-k3d: 
	curl -Lo /tmp/k3d https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-amd64
	chmod +x /tmp/k3d
	sudo mv /tmp/k3d /usr/local/bin

.PHONY: install-kind
install-kind:
	curl -Lo /tmp/kind https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64
	chmod +x /tmp/kind
	sudo mv /tmp/kind /usr/local/bin

	echo >>~/.bashrc
	echo 'source <(kind completion bash)' >>~/.bashrc

	@tput setaf 3; echo -e "\nStart a new shell to load kind completion!\n"; tput sgr0

.PHONY: install-micro
install-micro:
	sudo snap install microk8s --classic --channel=${MICRO_VERSION}
	sudo usermod -a -G microk8s $${USER}

	@tput setaf 3; echo -e "\nLogout and login to reload group rights!\n"; tput sgr0

.PHONY: install-kvm
install-kvm:
	sudo apt-get install qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
	sudo apt-get install virt-manager
	sudo adduser `id -un` kvm
	sudo adduser `id -un` libvirt || sudo adduser `id -un` libvirtd

	@tput setaf 3; echo -e "\nRestart the system to start daemons and reload group rihts!\n"; tput sgr0

.PHONY: generate-vagrant
generate-vagrant:
	git clone https://github.com/pgillich/kubeadm-vagrant.git || cd kubeadm-vagrant; git pull

	mkdir -p ~/.vagrant.d/boxes
	mkdir -p ~/.vagrant.d/data
	mkdir -p ~/.vagrant.d/tmp

.PHONY: install-vagrant
install-vagrant:
ifeq (${DO_VAGRANT_ALIAS}, true)
	echo >>~/.bashrc
	echo alias vagrant="'"'${vagrant}'"'" >>~/.bashrc

	@tput setaf 3; echo -e "\nStart a new shell to reload vagrant alias!\n"; tput sgr0
endif

.PHONY: install-helm
install-helm:
ifeq ($(UNAME), Linux)
	curl -sfL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
else
	curl -sfL https://get.helm.sh/helm-${HELM_VERSION}-windows-amd64.zip -o /tmp/helm.zip
	unzip -o /tmp/helm.zip -d /tmp
	cp /tmp/windows-amd64/helm.exe /bin
endif

	$(call helm-repo-stable)

.PHONY: helm-repo-stable
helm-repo-stable:
	$(call helm-repo-stable)

.PHONY: cluster
cluster: cluster-${K8S_DISTRIBUTION}

.PHONY: cluster-k3s
cluster-k3s:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=${K3S_VERSION} INSTALL_K3S_SYMLINK=skip sh -s - \
		--write-kubeconfig-mode 644 --https-listen-port ${K3S_SERVER_PORT}
	cp /etc/rancher/k3s/k3s.yaml ~/.kube/${K8S_DISTRIBUTION}.yaml
	cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

	while [ $$(KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl get -A pod -o name | wc -l) -eq 0 ]; do sleep 1; done
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait --for=condition=Ready --timeout=${K3S_WAIT} -A pod --all \
		|| echo 'TIMEOUT' >&2

.PHONY: cluster-k3d
cluster-k3d:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	k3d cluster create --config ${K3D_CONFIG} --wait --timeout ${K3D_WAIT}
	cp ~/.kube/config ~/.kube/${K8S_DISTRIBUTION}.yaml

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait --for=condition=Ready --timeout=${K3D_WAIT} -A pod --all \
		|| echo 'TIMEOUT' >&2

.PHONY: cluster-micro
cluster-micro:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml microk8s status --wait-ready
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml sudo microk8s disable ha-cluster

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml microk8s status --wait-ready
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml microk8s inspect

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml microk8s enable dns storage

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml microk8s config >~/.kube/${K8S_DISTRIBUTION}.yaml
	cp ~/.kube/${K8S_DISTRIBUTION}.yaml ~/.kube/config

	while [ $$(KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl get -A pod -o name | wc -l) -eq 0 ]; do sleep 1; done
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait --for=condition=Ready --timeout=${MICRO_WAIT} -A pod --all \
		|| echo 'TIMEOUT' >&2

.PHONY: cluster-kind
cluster-kind:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	kind create cluster --name ${CLUSTER_NAME} --config=${KIND_CONFIG} --wait=${KIND_WAIT}
	kubectl cluster-info --context kind-${CLUSTER_NAME}
	cp ~/.kube/config ~/.kube/${K8S_DISTRIBUTION}.yaml

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait --for=condition=Ready --timeout=${KIND_WAIT} -A pod --all \
		|| echo 'TIMEOUT' >&2

.PHONY: drop-caches
drop-caches:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	sudo sh -c 'sync; echo 3 > /proc/sys/vm/drop_caches'

.PHONY: cluster-vagrant
cluster-vagrant:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	echo "SETUP_APPS = false" >kubeadm-vagrant/Ubuntu/.env

	cd kubeadm-vagrant/Ubuntu; $(vagrant) up --no-parallel

	cd kubeadm-vagrant/Ubuntu; $(vagrant) ssh master -- 'cat .kube/config' \
		| grep -v '^Starting with' >~/.kube/${K8S_DISTRIBUTION}.yaml
	cp ~/.kube/${K8S_DISTRIBUTION}.yaml ~/.kube/config

.PHONY: cni
cni: cni-${K8S_DISTRIBUTION}

.PHONY: cni-k3s
cni-k3s:
ifeq (${DO_CNI}, true)
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	@tput setaf 3; echo -e "SKIPPED (already done by k3s)\n"; tput sgr0
endif

.PHONY: cni-micro
cni-micro:
ifeq (${DO_CNI}, true)
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	@tput setaf 3; echo -e "SKIPPED (already done by disabling HA)\n"; tput sgr0
endif

.PHONY: cni-kind
cni-kind:
ifeq (${DO_CNI}, true)
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	@tput setaf 3; echo -e "SKIPPED (buggy)\n"; tput sgr0

	# https://medium.com/swlh/customise-your-kind-clusters-networking-layer-1249e7916100
	#curl -sfL https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml > /tmp/kube-flannel.yml
	#KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl apply -f /tmp/kube-flannel.yml

	#KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl scale deployment --replicas 1 coredns --namespace kube-system
endif

.PHONY: cni-vagrant
cni-vagrant:
ifeq (${DO_CNI}, true)
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	@tput setaf 3; echo -e "SKIPPED (already done by vagrant)\n"; tput sgr0
endif

.PHONY: metallb
metallb: metallb-${K8S_DISTRIBUTION}

.PHONY: metallb-k3s
metallb-k3s:
ifeq (${DO_METALLB}, true)
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	@tput setaf 3; echo -e "SKIPPED (on K3s)\n"; tput sgr0
endif

.PHONY: metallb-micro
metallb-micro:
ifeq (${DO_METALLB}, true)
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	microk8s enable metallb:${METALLB_POOL}

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait --for=condition=Ready \
	--timeout=${METALLB_WAIT} -n metallb-system pod --all \
	|| echo 'TIMEOUT' >&2
endif

.PHONY: metallb-kind
metallb-kind: metallb-official

.PHONY: metallb-vagrant
metallb-vagrant: metallb-official

.PHONY: metallb-official
metallb-official:
ifeq (${DO_METALLB}, true)
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl apply \
		-f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/manifests/namespace.yaml
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl apply \
		-f https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/manifests/metallb.yaml
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl create secret generic \
		-n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"

	cat metallb-config.yaml | METALLB_POOL=${METALLB_POOL} envsubst \
		| KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl apply -f -

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait --for=condition=Ready \
		--timeout=${METALLB_WAIT} -n metallb-system pod --all \
		|| echo 'TIMEOUT' >&2
endif

.PHONY: istio
istio:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

ifeq ($(K8S_DISTRIBUTION), k3d)
	helm repo add istio https://istio-release.storage.googleapis.com/charts && helm repo update istio
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl create namespace istio-system || echo "Namespace already created"
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm upgrade --install istio-base istio/base --version ${ISTIO_VERSION} -n istio-system --wait
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm upgrade --install istiod istio/istiod --version ${ISTIO_VERSION} -n istio-system --wait
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm upgrade --install istio-ingressgateway --version ${ISTIO_VERSION} istio/gateway -n istio-system --wait

	cat istio-ingress.yaml | EXTERNAL_DOMAIN=${EXTERNAL_DOMAIN} envsubst \
		| KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl apply -f -
else
	mkdir -p ${ISTIO_DIR}; cd ${ISTIO_DIR} \
		&& curl -sL https://istio.io/downloadIstio | ISTIO_VERSION=${ISTIO_VERSION} TARGET_ARCH=x86_64 sh -

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml \
		${ISTIO_DIR}/istio-${ISTIO_VERSION}/bin/istioctl install --set profile=demo -f istio-config.yaml -y
endif

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait \
		--for=condition=Ready --timeout=${ISTIO_WAIT} -n istio-system pod --all \
		|| echo 'TIMEOUT' >&2

.PHONY: delete-istio
delete-istio:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl delete namespace istio-system

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl get crd -oname | grep --color=never 'istio.io' | KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml xargs kubectl delete

.PHONY: kiali
kiali:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	helm repo add kiali https://kiali.org/helm-charts && helm repo update kiali

	cat kiali-values.yaml | KIALI_GRAFANA_URL=${KIALI_GRAFANA_URL} KIALI_PROMETHEUS_URL=${KIALI_PROMETHEUS_URL} EXTERNAL_DOMAIN=${EXTERNAL_DOMAIN} envsubst \
		| KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm upgrade --install --version ${KIALI_VERSION} --create-namespace kiali-server kiali/kiali-server \
		-n istio-system --version ${KIALI_VERSION} -f -

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait \
		--for=condition=Available --timeout=${ISTIO_WAIT} -n istio-system deployment.apps/kiali \
		|| echo 'TIMEOUT' >&2

.PHONY: telemetry
telemetry: telemetry-common telemetry-loki telemetry-tempo telemetry-mimir telemetry-alloy telemetry-grafana

.PHONY: telemetry-common
telemetry-common:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	helm repo add grafana https://grafana.github.io/helm-charts && helm repo update grafana

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl apply -f telemetry-namespace.yaml || echo "Namespace already created"

	cat telemetry-ingress.yaml | EXTERNAL_DOMAIN=${EXTERNAL_DOMAIN} envsubst \
		| KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl apply -n telemetry -f -

.PHONY: telemetry-loki
telemetry-loki:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm upgrade --install loki grafana/loki --version ${LOKI_VERSION} -n telemetry -f loki-values.yaml
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait --for=condition=Ready --timeout=${LOKI_WAIT} -n telemetry pod --all \
		|| echo 'TIMEOUT' >&2

.PHONY: telemetry-mimir
telemetry-mimir:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm upgrade --install mimir grafana/mimir-distributed --version ${MIMIR_VERSION} -n telemetry -f mimir-values.yaml
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait --for=condition=Ready --timeout=${MIMIR_WAIT} -n telemetry pod --all \
		|| echo 'TIMEOUT' >&2

.PHONY: delete-telemetry-mimir
delete-telemetry-mimir:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm delete mimir -n telemetry

.PHONY: telemetry-alloy
telemetry-alloy:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	cat alloy-config.yaml | ALLOY_CONFIG="$$(echo '|'; cat alloy-config.alloy | sed 's/^/    /g')" envsubst \
		| KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl apply -n telemetry -f -
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm upgrade --install alloy grafana/alloy --version ${ALLOY_VERSION} -n telemetry -f alloy-values.yaml
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait --for=condition=Ready --timeout=${ALLOY_WAIT} -n telemetry pod --all \
		|| echo 'TIMEOUT' >&2

.PHONY: delete-telemetry-alloy
delete-telemetry-alloy:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm delete alloy -n telemetry

.PHONY: telemetry-grafana
telemetry-grafana:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm upgrade --install grafana grafana/grafana --version ${GRAFANA_VERSION} -n telemetry -f mimir-values.yaml
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait --for=condition=Ready --timeout=${GRAFANA_WAIT} -n telemetry pod --all \
		|| echo 'TIMEOUT' >&2

.PHONY: telemetry-tempo
telemetry-tempo:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	helm repo add grafana https://grafana.github.io/helm-charts && helm repo update grafana
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm upgrade --install tempo grafana/tempo -n telemetry -f tempo-values.yaml

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait --for=condition=Ready --timeout=${K3S_WAIT} -n telemetry pod --all \
		|| echo 'TIMEOUT' >&2

.PHONY: nfs
nfs:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	cat nfs-values.yaml | KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm upgrade --install --create-namespace nfs-provisioner stable/nfs-server-provisioner -f -

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait \
		-l app=nfs-server-provisioner --for=condition=ready --timeout=${NFS_WAIT} pod \
		|| echo 'TIMEOUT' >&2

.PHONY: metrics
metrics: metrics-${K8S_DISTRIBUTION}

.PHONY: metrics-k3s
metrics-k3s:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	@tput setaf 3; echo -e "SKIPPED (already done by K3s)\n"; tput sgr0

.PHONY: metrics-k3d
metrics-k3d:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	@tput setaf 3; echo -e "SKIPPED (already done by K3d)\n"; tput sgr0

.PHONY: metrics-micro
metrics-micro:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	microk8s enable metrics-server

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait \
		--for=condition=Available --timeout=${METRICS_WAIT} -n kube-system deployment.apps/metrics-server \
		|| echo 'TIMEOUT' >&2

.PHONY: metrics-kind
metrics-kind: metrics-official

.PHONY: metrics-vagrant
metrics-vagrant: metrics-official

.PHONY: metrics-official
metrics-official:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ && helm repo update metrics-server

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm upgrade --install --create-namespace metrics-server metrics-server/metrics-server --version ${METRICS_VERSION} \
		--set 'args={--kubelet-insecure-tls, --kubelet-preferred-address-types=InternalIP}' --namespace kube-system

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait \
		--for=condition=Available --timeout=${METRICS_WAIT} -n kube-system  deployment.apps/metrics-server \
		|| echo 'TIMEOUT' >&2

.PHONY: dashboard
dashboard:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

ifeq ($(K8S_DISTRIBUTION), k3d)
	helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ && helm repo update kubernetes-dashboard
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard --create-namespace --namespace kubernetes-dashboard
	
	cat dashboard-config_${K8S_DISTRIBUTION}.yaml | EXTERNAL_DOMAIN=${EXTERNAL_DOMAIN} envsubst \
		| KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl apply -f -

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl create \
		-n kubernetes-dashboard token admin-user

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait \
		--for=condition=Available --timeout=${DASHBOARD_WAIT} -n kubernetes-dashboard deployment/kubernetes-dashboard-web \
		|| echo 'TIMEOUT' >&2
else
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl create \
		-f https://raw.githubusercontent.com/kubernetes/dashboard/${DASHBOARD_VERSION}/aio/deploy/recommended.yaml

	cat dashboard-config.yaml | EXTERNAL_DOMAIN=${EXTERNAL_DOMAIN} envsubst \
		| KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl apply -f -

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl create \
		-n kubernetes-dashboard token admin-user

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait \
		--for=condition=Available --timeout=${DASHBOARD_WAIT} -n kubernetes-dashboard deployment/kubernetes-dashboard \
		|| echo 'TIMEOUT' >&2
endif

.PHONY: delete-dashboard
delete-dashboard:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl delete ns kubernetes-dashboard

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl delete clusterrolebinding kubernetes-dashboard

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl delete clusterrole kubernetes-dashboard

.SILENT: info-post
.PHONY: info-post
info-post:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	echo -e "Using custom kubectl config file:\nKUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl ...\nKUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm ..."

ifeq (${OAM_IP},)
	echo -e "\nAdd below line to /etc/hosts:\n$$(kubectl -n istio-system get service istio-ingressgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')" \
	  "  istio.${EXTERNAL_DOMAIN} dashboard.${EXTERNAL_DOMAIN} grafana.${EXTERNAL_DOMAIN} mimir.${EXTERNAL_DOMAIN} tempo.${EXTERNAL_DOMAIN} tempo-collector.${EXTERNAL_DOMAIN} alloy.${EXTERNAL_DOMAIN}"
else
	echo -e "\nAdd below line to /etc/hosts:\n${OAM_IP} dashboard.${EXTERNAL_DOMAIN} grafana.${EXTERNAL_DOMAIN} prometheus.${EXTERNAL_DOMAIN}"
endif

	echo -e "\nDashboard URL:\nhttps://dashboard.${EXTERNAL_DOMAIN}"

	echo -e "\nDashboard login token:"
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl -n kubernetes-dashboard describe secret admin-user-token \
		| grep ^token || echo "DASHBOARD IS NOT READY!"

	echo -e "\nKiali URL:\nhttp://istio.${EXTERNAL_DOMAIN}/kiali/"

	echo -e "\nMimir URLs:"
	echo -e "  Alertmanager:           http://mimir.${EXTERNAL_DOMAIN}/alertmanager/"
	echo -e "  Tenant stats:           http://mimir.${EXTERNAL_DOMAIN}/distributor/all_user_stats"
	echo -e "  HA tracker status:      http://mimir.${EXTERNAL_DOMAIN}/distributor/ha_tracker"
	echo -e "  Alertmanager status:    http://mimir.${EXTERNAL_DOMAIN}/multitenant_alertmanager/status"
	echo -e "  Alertmanager configs:   http://mimir.${EXTERNAL_DOMAIN}/multitenant_alertmanager/configs"
	echo -e "  List rule groups:       http://mimir.${EXTERNAL_DOMAIN}/prometheus/config/v1/rules"
	echo -e "  List Prometheus rules:  http://mimir.${EXTERNAL_DOMAIN}/prometheus/api/v1/rules"
	echo -e "  List Prometheus alerts: http://mimir.${EXTERNAL_DOMAIN}/prometheus/api/v1/alerts"
	echo -e "  Ruler ring status:      http://mimir.${EXTERNAL_DOMAIN}/ruler/ring"

	echo -e "\nAlloy URL:\nhttp://alloy.${EXTERNAL_DOMAIN}/"
	echo -e   "  metrics: http://alloy.${EXTERNAL_DOMAIN}/metrics"

	echo -e "\nLoki URLs:"
	echo -e "  Config:              http://loki.${EXTERNAL_DOMAIN}/config"
	echo -e "  Memberlist status:   http://loki.${EXTERNAL_DOMAIN}/memberlist"
	echo -e "  Ring status:         http://loki.${EXTERNAL_DOMAIN}/ring"
	echo -e "  Distributor ring:    http://loki.${EXTERNAL_DOMAIN}/distributor/ring"
	echo -e "  Compactor ring:      http://loki.${EXTERNAL_DOMAIN}/compactor/ring"
	echo -e "  IndexGateway ring:   http://loki.${EXTERNAL_DOMAIN}/indexgateway/ring"
	echo -e "  QueryScheduler ring: http://loki.${EXTERNAL_DOMAIN}/scheduler/ring"
	echo -e "  Prom rules:          curl -H 'X-Scope-OrgID: <TENANT_ID>' http://loki.${EXTERNAL_DOMAIN}/prometheus/api/v1/rules"
	echo -e "  Prom alerts:         curl -H 'X-Scope-OrgID: <TENANT_ID>' http://loki.${EXTERNAL_DOMAIN}/prometheus/api/v1/alerts"
	echo -e "  Prom labels:         curl -H 'X-Scope-OrgID: <TENANT_ID>' http://loki.${EXTERNAL_DOMAIN}/loki/api/v1/labels"
	echo -e "  Prom series:         curl -H 'X-Scope-OrgID: <TENANT_ID>' http://loki.${EXTERNAL_DOMAIN}/loki/api/v1/series"

	echo -e "\nGrafana URL:\nhttp://grafana.${EXTERNAL_DOMAIN}/"
	echo -n "  admin /" $$(KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl get secret --namespace telemetry grafana -o jsonpath="{.data.admin-password}" | base64 --decode)
	echo

	echo -e "\nTempo status:\nhttp://tempo.${EXTERNAL_DOMAIN}/status"
	echo -e "\nTempo Collector URL:\nhttp://tempo-collector.${EXTERNAL_DOMAIN}/v1/traces"

	if [ $$(cat /proc/sys/fs/inotify/max_user_watches) -lt 524288 ]; then echo -e "\nWARNING! max_user_watches should be increased, see README.md"; fi
	if [ $$(cat /proc/sys/fs/inotify/max_user_instances) -lt 8196 ]; then echo -e "\nWARNING! max_user_instances should be increased, see README.md"; fi

.PHONY: destroy
destroy: destroy-${K8S_DISTRIBUTION}

.PHONY: destroy-k3s
destroy-k3s:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	/usr/local/bin/k3s-uninstall.sh || echo "ALREADY UNINSTALLED"
	sudo rm -rf /var/lib/rancher/k3s/ /etc/rancher/k3s

.PHONY: destroy-k3d
destroy-k3d:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	k3d cluster delete ${CLUSTER_NAME}

.PHONY: destroy-kind
destroy-kind:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	kind delete cluster --name ${CLUSTER_NAME}

.PHONY: destroy-micro
destroy-micro:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml microk8s reset --destroy-storage

.PHONY: destroy-vagrant
destroy-vagrant:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	cd kubeadm-vagrant/Ubuntu; $(vagrant) destroy

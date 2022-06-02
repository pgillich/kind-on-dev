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

helm-repo-stable = (helm repo add stable https://charts.helm.sh/stable && helm repo update)

include .env

.PHONY: all
all: cluster cni metallb metrics traefik dashboard prometheus info-post

.PHONY: no-net
no-net: cluster metallb metrics dashboard prometheus info-post

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
	echo curl -sfL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 # | bash
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

.PHONY: nfs
nfs:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	cat nfs-values.yaml | KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm install nfs-provisioner stable/nfs-server-provisioner -f -

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait \
		-l app=nfs-server-provisioner --for=condition=ready --timeout=${NFS_WAIT} pod \
		|| echo 'TIMEOUT' >&2

.PHONY: metrics
metrics: metrics-${K8S_DISTRIBUTION}

.PHONY: metrics-k3s
metrics-k3s:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	@tput setaf 3; echo -e "SKIPPED (already done by K3s)\n"; tput sgr0

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

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm install metrics-server stable/metrics-server --version ${METRICS_VERSION} \
		--set 'args={--kubelet-insecure-tls, --kubelet-preferred-address-types=InternalIP}' --namespace kube-system

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait \
		--for=condition=Available --timeout=${METRICS_WAIT} -n kube-system  deployment.apps/metrics-server \
		|| echo 'TIMEOUT' >&2

.PHONY: traefik
traefik:
ifeq (${DO_TRAEFIK}, true)
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

ifeq (${K8S_DISTRIBUTION}, k3s)
	sudo sed -i -e '/    rbac:/i\' -e "    dashboard:\n      enabled: true\n      domain:  ${OAM_DOMAIN}" \
		/var/lib/rancher/k3s/server/manifests/traefik.yaml
else
	cat traefik-config.yaml | OAM_DOMAIN=${OAM_DOMAIN} OAM_IP=${OAM_IP} TRAEFIK_SERVICETYPE=${TRAEFIK_SERVICETYPE} envsubst \
		| KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm install traefik stable/traefik --version ${TRAEFIK_VERSION} --namespace kube-system -f -
#	cat traefik-config.yaml | OAM_DOMAIN=${OAM_DOMAIN} OAM_IP=${OAM_IP} TRAEFIK_LOADBALANCERIP=${TRAEFIK_LOADBALANCERIP} TRAEFIK_EXTERNALIP=${TRAEFIK_EXTERNALIP} envsubst \
#		| KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm template traefik stable/traefik --version ${TRAEFIK_VERSION} --namespace kube-system -f -

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait \
		--for=condition=Available --timeout=${TRAEFIK_WAIT} -n kube-system deployment.apps/traefik || echo 'TIMEOUT' >&2
endif
endif

.PHONY: dashboard
dashboard:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl create \
		-f https://raw.githubusercontent.com/kubernetes/dashboard/${DASHBOARD_VERSION}/aio/deploy/alternative.yaml

	cat dashboard-config.yaml | OAM_DOMAIN=${OAM_DOMAIN} INGRESS_CLASS=${INGRESS_CLASS} envsubst \
		| KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl apply -f -

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait \
		--for=condition=Available --timeout=${DASHBOARD_WAIT} -n kubernetes-dashboard deployment/kubernetes-dashboard \
		|| echo 'TIMEOUT' >&2

.PHONY: prometheus
prometheus:
ifeq (${DO_PROMETHEUS}, true)
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl create namespace ${PROMETHEUS_NAMESPACE} \
		--dry-run -o yaml | KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl apply -f -

	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update

	cat prometheus-values.yaml | OAM_DOMAIN=${OAM_DOMAIN} INGRESS_CLASS=${INGRESS_CLASS} envsubst \
		| KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm install ${PROMETHEUS_HELM_RELEASE_NAME} prometheus-community/kube-prometheus-stack \
		-n ${PROMETHEUS_NAMESPACE} --version ${PROMETHEUS_CHART_VERSION} -f -

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl wait \
		--for=condition=Ready --timeout=${PROMETHEUS_WAIT} -n ${PROMETHEUS_NAMESPACE} pod --all \
		|| echo 'TIMEOUT' >&2
endif

.PHONY: delete-prometheus
delete-prometheus:
ifeq (${DO_PROMETHEUS}, true)
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm uninstall ${PROMETHEUS_HELM_RELEASE_NAME} -n ${PROMETHEUS_NAMESPACE}

	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl delete crd alertmanagerconfigs.monitoring.coreos.com
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl delete crd alertmanagers.monitoring.coreos.com
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl delete crd podmonitors.monitoring.coreos.com
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl delete crd probes.monitoring.coreos.com
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl delete crd prometheuses.monitoring.coreos.com
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl delete crd prometheusrules.monitoring.coreos.com
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl delete crd servicemonitors.monitoring.coreos.com
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl delete crd thanosrulers.monitoring.coreos.com
endif

.SILENT: info-post
.PHONY: info-post
info-post:
	@tput setaf 6; echo -e "\nmake $@\n"; tput sgr0

	echo -e "Using custom kubectl config file:\nKUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl ...\nKUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml helm ..."

ifeq (${OAM_IP},)
	echo -e "\nAdd below line to /etc/hosts:\n127.0.0.1 ${OAM_DOMAIN}"
	echo -e "\nAdd below line to C:\windows\system32\drivers\etc\hosts:\n`ip a show dev eth0 scope global | grep -oP 'inet \K[0-9.]+'` ${OAM_DOMAIN}"
else
	echo -e "\nAdd below line to /etc/hosts:\n${OAM_IP} ${OAM_DOMAIN}"
endif

	echo -e "\nTraefik URL:\nhttp://${OAM_DOMAIN}/dashboard/"

	echo -e "\nDashboard URL:\nhttps://${OAM_DOMAIN}/kubernetes/"

	echo -e "\nDashboard login token:"
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml kubectl -n kubernetes-dashboard describe secret admin-user-token \
		| grep ^token || echo "DASHBOARD IS NOT READY!"

	echo -e "\nPrometheus URL:\nhttps://${OAM_DOMAIN}/prometheus/"

	echo -e "\nAlertmanager URL:\nhttps://${OAM_DOMAIN}/alertmanager/"

	echo -e "\nGrafana URL:\nhttps://${OAM_DOMAIN}/grafana/"
	echo -n "  admin / "; grep -Po 'adminPassword:[\s]*\K.*' prometheus-values.yaml

	if [ $$(cat /proc/sys/fs/inotify/max_user_watches) -lt 524288 ]; then echo -e "\nWARNING! max_user_watches should be increased, see README.md"; fi
	if [ $$(cat /proc/sys/fs/inotify/max_user_instances) -lt 8196 ]; then echo -e "\nWARNING! max_user_instances should be increased, see README.md"; fi

.PHONY: destroy
destroy: destroy-${K8S_DISTRIBUTION}

.PHONY: destroy-k3s
destroy-k3s:
	/usr/local/bin/k3s-uninstall.sh || echo "ALREADY UNINSTALLED"
	sudo rm -rf /var/lib/rancher/k3s/ /etc/rancher/k3s

.PHONY: destroy-kind
destroy-kind:
	kind delete cluster --name ${CLUSTER_NAME}

.PHONY: destroy-micro
destroy-micro:
	KUBECONFIG=~/.kube/${K8S_DISTRIBUTION}.yaml microk8s reset --destroy-storage

.PHONY: destroy-vagrant
destroy-vagrant:
	cd kubeadm-vagrant/Ubuntu; $(vagrant) destroy

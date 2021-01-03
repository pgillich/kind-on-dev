# kind-on-dev

This repo helps to setup a KinD (and Vagrant+kubeadm) cluster from scratch.

The solution is make-based, see more details in `Makefile` and `.env`.

On Windows, only Vagrant+kubeadm variant is supported with limitaitons.

> Warning: This deployment is not secure and must be hardened before using it in production.

## Preparation

On Ununtu, run below commands, if something is missing or needed:

* `make kubectl-install` (if not installed yet)
* `make docker-install` (only for KinD)
* `make kind-install` (only for KinD)
* `make kvm-install` (only for Vagrant + libvirt/KVM)
* `make vagrant-install` (only for Vagrant, needed)
* `DO_VAGRANT_ALIAS=true make vagrant-install` (only for Vagrant, if not installed yet and `vagrant` would be used in CLI)

> Note: the Vagrant+kubeadm variant uses own vagrant in Docker, which contains all needed plugins. See more details at [kubeadm-vagrant/Ubuntu/README.md](kubeadm-vagrant/Ubuntu/README.md).

On Windows, do below steps:

1. Install official Vagrant and needed plugins (mutate and hostmanager), if not installed yet.
1. Install kubeclt, if not installed yet.
1. Install a Cygwin distribution, which has `make` or it can be installed (for example: MobaXterm)
1. run `make vagrant-install`

## Configuration

Review `.env`.

Review `*.yaml` files.

Review `kubeadm-vagrant/Ubuntu/Vagrantfile`, if Vagrant is used. Hint: RAM allocation for VMs is very low!

Help for Prometheus configuration:

* <https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack>
* <https://github.com/prometheus-operator/kube-prometheus>
* <https://github.com/grafana/helm-charts/blob/main/charts/grafana/values.yaml>
* <https://docs.flagger.app/tutorials/prometheus-operator>
* <https://docs.fission.io/docs/observability/prometheus/>
* <https://medium.com/swlh/free-ssl-certs-with-lets-encrypt-for-grafana-prometheus-operator-helm-charts-b3b629e84ba1>
* <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/getting-started.html>

Passwords:

* Grafana: admin / prometheus-values.yaml:grafana.adminPassword

## Setup cluster

> Warning: `~/.kube/config` will be overwritten!

Install:

```sh
make all
```

Install without Prometheus:

```sh
make all DO_PROMETHEUS=false
```

Post-install steps: please follow instructions of `make post-help`. Note: `post-help` target is called at the end of `make all`.

## Destroy cluster

> Warning: if the selected K8s distribution is K3s, it will be uninstalled!

```sh
make destroy
```

## Known issues

### Flannel

Flannel on Vagrant+kubeadm is deployed automatically.

Flannel cannot be deployed on KinD, because a binary is missing on the nodes. See more details:

* <https://medium.com/swlh/customise-your-kind-clusters-networking-layer-1249e7916100>
* <https://github.com/kubernetes-sigs/kind/issues/1340>
* <https://github.com/coreos/flannel/issues/890>
* <https://medium.com/@liuyutong2921/network-failed-to-find-plugin-bridge-in-path-opt-cni-bin-70e7156ceb0b>
* <https://cloud.garr.it/support/kb/kubernetes/flannel/>
* <https://programmer.group/a-thorough-understanding-of-kubernetes-cni.html>
* <https://stackoverflow.com/questions/51169728/failed-create-pod-sandbox-rpc-error-code-unknown-desc-networkplugin-cni-fa/56246246>

## References

* <https://www.danielstechblog.io/local-kubernetes-setup-with-kind/>
* <https://medium.com/swlh/customise-your-kind-clusters-networking-layer-1249e7916100>

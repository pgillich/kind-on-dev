# kind-on-dev

This repo helps to setup a KinD cluster from scratch.

The solution is make-based, see more details in `Makefile`.

## Preparation

Run below commands, if something is missing:

* `make docker`
* `make kubectl`
* `make kind`

## Configuration

Review `.env`.

Review `*.yaml` files.

Help for Prometheus configuration:

* <https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack>
* <https://github.com/prometheus-operator/kube-prometheus>
* <https://docs.flagger.app/tutorials/prometheus-operator>
* <https://docs.fission.io/docs/observability/prometheus/>
* <https://medium.com/swlh/free-ssl-certs-with-lets-encrypt-for-grafana-prometheus-operator-helm-charts-b3b629e84ba1>
* <https://docs.nvidia.com/datacenter/cloud-native/gpu-operator/getting-started.html>

Passwords:

* Grafana: admin / prometheus-values.yaml:grafana.adminPassword

## Setup cluster

Install:

```sh
make all
```

Install with Prometheus:

```sh
make all DO_PROMETHEUS=true
```

Post-install steps: please follow instructions of `make post-help`. Note: `post-help` target is called at the end of `make all`.

## Destroy cluster

```sh
make destroy
```

## Known issues

### Flannel

Flannel cannot be deployed, because a binary is missing on the nodes. See more details:

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

# kind-on-dev

This repo helps to setup a KinD cluster from scratch.

The solution is make-based, see more details in `Makefile`.

## Preparation

Run below commands, if something is missing:

* `make docker`
* `make kubectl`
* `make kind`

## Configuration

Edit `.env`.

## Setup cluster

Install:

```sh
make cluster
```

Post-install steps: please follow instructions of `make post-help`. Note: `post-help` is called at the end of `make all`.

## Destroy cluster

```sh
make destroy
```

## Known issues

### Flannel

Flannel cannot be deployed, because a binary is missing on the nodes. See more details:

* <https://github.com/kubernetes-sigs/kind/issues/1340>
* <https://github.com/coreos/flannel/issues/890>
* <https://medium.com/@liuyutong2921/network-failed-to-find-plugin-bridge-in-path-opt-cni-bin-70e7156ceb0b>
* <https://cloud.garr.it/support/kb/kubernetes/flannel/>
* <https://programmer.group/a-thorough-understanding-of-kubernetes-cni.html>
* <https://stackoverflow.com/questions/51169728/failed-create-pod-sandbox-rpc-error-code-unknown-desc-networkplugin-cni-fa/56246246>

## References:

* <https://www.danielstechblog.io/local-kubernetes-setup-with-kind/>
* <https://medium.com/swlh/customise-your-kind-clusters-networking-layer-1249e7916100>



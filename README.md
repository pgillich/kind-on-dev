# kind-on-dev

This repo helps to setup a K3d (and K3s, KinD, MicroK8S, Vagrant+kubeadm) cluster from scratch.
Usage is published at [Environment for comparing several on-premise Kubernetes distributions (K3s, KinD, kubeadm)](https://pgillich.medium.com/environment-for-comparing-several-on-premise-kubernetes-distributions-k3s-kind-kubeadm-a53675a80a00).

> This development branch supports Kubernetes 1.24.
> Traefik is replaced to Istio Gateway and VirtualService.
> Work in progress, WSL2 with K3d is in focus
> Created for my article <https://pgillich.medium.com/istio-tracing-with-jaeger-756ed9872e73>

The solution is make-based, see more details in `Makefile` and `.env`.

On Windows, only below combinations are supported with limitaitons:
* Vagrant+kubeadm
* WSL2 with KinD

> Warning: This deployment is not secure and must be hardened before using it in production.

## Initial configurations

### Grafana Alloy

Info:

* <https://grafana.com/docs/alloy/latest/set-up/install/linux/>
* <https://grafana.com/docs/alloy/latest/set-up/migrate/from-prometheus/>
* <https://grafana.com/docs/alloy/latest/set-up/migrate/from-otelcol/>
* <https://grafana.com/docs/alloy/latest/set-up/migrate/from-operator/>

Getting Prometheus config from: <https://github.com/istio/istio/blob/master/samples/addons/prometheus.yaml>

Converting Prometheus config to Grafana Alloy:

```sh
alloy convert --source-format prometheus -b prometheus.yaml
```

Additional initial config from: <https://github.com/grafana/alloy/blob/main/operations/helm/charts/alloy/config/example.alloy>

Converting initial OTEL collector config [otlp-collector.yaml](otlp-collector.yaml) to Grafana Alloy:

```sh
alloy convert --source-format otelcol -b otlp-collector.yaml
```

Converting sample Promtail config from <https://grafana.com/docs/loki/latest/send-data/promtail/installation/#install-as-kubernetes-daemonset-recommended>:

```sh
alloy convert -f promtail ./promtail.yaml
```


## Preparation

Install below packages, if it's missing:

* `make`
* `git`

On Ununtu, run below commands, if something is missing or needed:

* `make install-kubectl` (if not installed yet)
* `make install-micro` (if MicroK8S not installed yet)
* `make install-docker` (only for KinD, K3d)
* `make install-kind` (only for KinD)
* `make install-k3d` (only for K3d)
* `make install-kvm` (only for Vagrant + libvirt/KVM)
* `make generate-vagrant` (only for Vagrant, needed)
* `DO_VAGRANT_ALIAS=true make install-vagrant` (only for Vagrant, if not installed yet and `vagrant` would be used in CLI)
* `make install-helm` (if not installed yet)

> Note: `/etc/docker/daemon.json:insecure-registries` may be set for MicroK8S, if Docker is installed, see: <https://microk8s.io/docs/registry-built-in>.

> Note: the Vagrant+kubeadm variant uses own vagrant in Docker, which contains all needed plugins.
> See more details at [kubeadm-vagrant/Ubuntu/README.md](kubeadm-vagrant/Ubuntu/README.md).

> Note: There are several limitations and workarounds with Vagrant,
> See more details at [kubeadm-vagrant/Ubuntu/README.md](kubeadm-vagrant/Ubuntu/README.md).

A few Linux filesystem limits should be increased, for example:

```sh
cat /proc/sys/fs/inotify/max_user_watches; echo fs.inotify.max_user_watches=524288 | sudo tee /etc/sysctl.d/50_max_user_watches.conf && sudo sysctl --system; cat /proc/sys/fs/inotify/max_user_watches

cat /proc/sys/fs/inotify/max_user_instances; echo fs.inotify.max_user_instances=8196 | sudo tee /etc/sysctl.d/50_max_user_instances.conf && sudo sysctl --system; cat /proc/sys/fs/inotify/max_user_instances
```

Linux swap should be disabled, for example:

```sh
sudo swapoff -a
```

Add below line to `/etc/hosts`:

```text
127.0.2.1       k3d-01.company.com
```

On Windows with Vagrant+kubeadm, do below steps:

1. Install official Vagrant and needed plugins (mutate and hostmanager), if not installed yet.
1. Install kubectl, if not installed yet.
1. Install a Cygwin distribution, which has `make` and `git` or it can be installed (for example on MobaXterm: `apt-get install make git`)
1. run `make generate-vagrant`

## Configuration

Review `.env`.

Review `*.yaml` files.

Review `kubeadm-vagrant/Ubuntu/Vagrantfile`, if Vagrant is used. Hint: RAM allocation for VMs is very low!

Review `kind-config_wsl2.yaml`, if WSL2 with KinD is used.

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

Example for install without Prometheus:

```sh
make all DO_PROMETHEUS=false
```

Example for installing a non-default distro (the default can be set in `.env`):

```sh
make all K8S_DISTRIBUTION=k3s
```

Example for installing WSL2 with KinD:

```sh
make all DO_CNI=false DO_METALLB=false
```

Post-install steps: please follow instructions of `make info-post`. Note: `info-post` target is called at the end of `make all`.

> Parellel with deployments on KinD or K3d (or after) the `make drop-caches` should be run sometime.

## Istio

Determining Node IP: <https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/>
* https://kubernetes.io/docs/concepts/services-networking/service/#type-nodeport
* https://istio.io/latest/docs/setup/getting-started/
* https://istio.io/latest/docs/setup/install/helm/
* https://istio.io/latest/docs/setup/additional-setup/customize-installation/
* https://stackoverflow.com/questions/67538712/set-ingress-gateway-nodeport-with-isito-operator
* https://istio.io/latest/docs/tasks/observability/gateways/
* https://istio.io/v1.12/docs/examples/microservices-istio/istio-ingress-gateway/
* https://istio.io/v1.1/docs/tasks/telemetry/gateways/

* https://stackoverflow.com/questions/67187642/how-to-use-virtualservice-to-expose-dashboards-like-grafana-prometheus-and-kiali

127.0.0.1:8001/api/v1/namespaces/istio-system/services/kiali:http/proxy/kiali/

dashboards:
  istio-extension-dashboard: 13277
  istio-mesh-dashboard: 7639
  istio-performance-dashboard: 11829
  istio-service-dashboard: 7636
  istio-workload-dashboard: 7630
  pilot-dashboard: 7645

## Post-install config

### Name resolution

Add below line to `/etc/hosts`:

```text
?.?.?.?       dashboard.kind-01.company.com grafana.kind-01.company.com prometheus.kind-01.company.com
```

Where the `?.?.?.?` is printed out by `info-post` target.

### Grafana Datasources

#### Logs

*Name: `Logs (loki)`*

URL: `http://loki.telemetry.svc:3100/`

HTTP header: `X-Scope-OrgID`: `self-monitoring`

*Name: `Logs (alloy)`*

URL: `http://loki.telemetry.svc:3100/`

HTTP header: `X-Scope-OrgID`: `alloy`

#### Metrics

*Name: `Metrics (alloy)`*

URL: `http://mimir-nginx.telemetry.svc:80/prometheus`

HTTP header: `X-Scope-OrgID`: `alloy`

## Optional components

### Monitoring

Metrics server and Prometheus deployment can de disabled by `DO_...` flags in `.env` file.

### Storage

Before using NFS in K3s, `nfs-common` package must be installed, for example:

```sh
sudo apt install nfs-common
```

Nfs storage can be deployed by `make nfs`. It can be configured in `nfs-values.yaml`.

> Warning! It's experimental.

Example for using NFS:

```sh
kubectl apply -f pvc-example.yaml

kubectl get pod -l app=busybox-with-pv -o wide --show-labels

for pod in $(kubectl get pod -l app=busybox-with-pv -o name); do echo -e "\n$pod /mnt"; kubectl exec -ti $pod -- find /mnt -type f -exec cat '{}' ';' ; done
```

Note: the default storage is <https://github.com/rancher/local-path-provisioner>,
which is used by the deployed NFS server.

## Destroy cluster

> Warning: if the selected K8s distribution is K3s, it will be uninstalled!

```sh
make destroy
```

## Known issues

### WSL2

Only WSL2 with KinD and K3d combination is supported.

Before starting the install, `max_user_watches` and `max_user_instances` must be set properly (`sysctl --system`).

After restart, the WSL2 IP address will be changed. The WSL2 IP address for `C:\windows\system32\drivers\etc\hosts` can be determined by one of below commands:

* `wsl.exe hostname -I`
* `wsl.exe -- ip -4 a show dev eth0 scope global`

It may be a solution: <https://github.com/microsoft/WSL/issues/4210#issuecomment-648570493>

### Mimir install Jobs

The install Job health checks are wrong and the job exits properly before the health check called, see:

```sh
kubectl get pod -n telemetry -w

mimir-minio-post-job-j4b9m                     0/3     PodInitializing   0          4s
mimir-minio-post-job-j4b9m                     2/3     Running           0          4s
mimir-minio-post-job-j4b9m                     2/3     Running           0          10s
mimir-minio-post-job-j4b9m                     3/3     Running           0          10s
mimir-minio-post-job-j4b9m                     1/3     NotReady          0          15s

mimir-make-minio-buckets-5.0.14-ffq7d          0/2     PodInitializing   0          4s
mimir-make-minio-buckets-5.0.14-ffq7d          1/2     Running           0          8s
mimir-make-minio-buckets-5.0.14-ffq7d          1/2     Running           0          13s
mimir-make-minio-buckets-5.0.14-ffq7d          2/2     Running           0          13s
mimir-make-minio-buckets-5.0.14-ffq7d          1/2     NotReady          0          15s
```

Workaround: if only the Job Pods aren't Ready, run below command in a new shell:

```sh
kubectl get pod -n telemetry
kubectl delete job -n telemetry mimir-make-minio-buckets-5.0.14  mimir-minio-post-job
```

### Mimir Helm upgrade

After Helm upgrade (executing the `make telemetry-mimir`) the `distributor` losts the zones and Mimir won't work.

Workaround: reinstall by below command:

```sh
make delete-telemetry-mimir telemetry-mimir
```

### Flannel

Flannel is the CNI for MicroK8S, if HA is disabled (if HA is enabled, Calico is the CNI). So, this solution disables HA in MicroK8S automatically.

Flannel on Vagrant+kubeadm is deployed automatically.

Flannel cannot be deployed on KinD, because a binary is missing on the nodes. See more details:

* <https://medium.com/swlh/customise-your-kind-clusters-networking-layer-1249e7916100>
* <https://github.com/kubernetes-sigs/kind/issues/1340>
* <https://github.com/coreos/flannel/issues/890>
* <https://medium.com/@liuyutong2921/network-failed-to-find-plugin-bridge-in-path-opt-cni-bin-70e7156ceb0b>
* <https://cloud.garr.it/support/kb/kubernetes/flannel/>
* <https://programmer.group/a-thorough-understanding-of-kubernetes-cni.html>
* <https://stackoverflow.com/questions/51169728/failed-create-pod-sandbox-rpc-error-code-unknown-desc-networkplugin-cni-fa/56246246>


### Flannel on MicroK8s

The `microk8s inspect` returns errors:

```text
 FAIL:  Service snap.microk8s.daemon-flanneld is not running
For more details look at: sudo journalctl -u snap.microk8s.daemon-flanneld
 FAIL:  Service snap.microk8s.daemon-etcd is not running
For more details look at: sudo journalctl -u snap.microk8s.daemon-etcd
  Copy service arguments to the final report tarball
```

Because of why, the daemon was unable to start:

```text
$ systemctl status snap.microk8s.daemon-flanneld.service
● snap.microk8s.daemon-flanneld.service - Service for snap application microk8s.daemon-flanneld
     Loaded: loaded (/etc/systemd/system/snap.microk8s.daemon-flanneld.service; enabled; vendor preset: enabled)
     Active: inactive (dead) since Sat 2021-01-16 18:59:25 CET; 7min ago
    Process: 20890 ExecStart=/usr/bin/snap run microk8s.daemon-flanneld (code=exited, status=0/SUCCESS)
   Main PID: 20890 (code=exited, status=0/SUCCESS)

jan 16 18:59:25 ubuntu-20 systemd[1]: Started Service for snap application microk8s.daemon-flanneld.
jan 16 18:59:25 ubuntu-20 systemd[1]: snap.microk8s.daemon-flanneld.service: Succeeded.
```

Workaround: Uninstall MicroK8s (with --purge), install it again, restart the computer.

## References

* <https://www.danielstechblog.io/local-kubernetes-setup-with-kind/>
* <https://medium.com/swlh/customise-your-kind-clusters-networking-layer-1249e7916100>

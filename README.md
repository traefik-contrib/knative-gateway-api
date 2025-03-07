# Traefik + Knative w/ `net-gateway-api` via `LoadBalancer` services

This repository showcases a working setup of [Traefik][tf] and [Knative Serving][kn-serving] which uses
[`net-gateway-api`][net-gateway-api]'s support of `LoadBalancer` services to properly configure [`HTTPRoute`][httproute]s.

[tf]: https://doc.traefik.io/traefik
[kn-serving]: https://knative.dev/docs/serving/
[httproute]: https://gateway-api.sigs.k8s.io/api-types/httproute/
[net-gateway-api]: https://github.com/knative-extensions/net-gateway-api

## Motivation

One of the main reasons Knative does not already work smoothly with Traefik is that it currently uses
`ExternalName`s with it's default Kubernetes `Service` (the service that forwards for the *Knative* `Service`).

Given that `net-gateway-api` exists, Traefik *would* normally be able to does not support `ExternalName`s for

While Knative intends to [migrate from `ExternalName`][kn-migrate-issue], that work is not quite done yet.

What we *can* use to bridge this gap is [upstream code](https://github.com/knative/serving/blob/636392e930c1d6b5b5619bde54bf38e3990acf88/pkg/reconciler/route/resources/service.go#L115) that prioritizes IP addresses on services
of type `LoadBalancer`.

If `net-gateway-api` recognizes one, it will *supercede* the automatically created `ExternalName` service.

`LoadBalancer`s are *not* always configured or needed in every cluster, but if one *is*, we can use this
functionality to get a working Knative + Traefik integration.

[kn-migrate-issue]: https://github.com/knative/serving/issues/11821

## Requirements

This repository is structured to enable setting up a [KinD][kind] cluster with the following pieces installed:

- [MetalLB][mllb]
- Traefik
- Knative

To actually accomplish this, you'll need a few tools installed:

| Tool                     | Description         | Download instructions                                    |
|--------------------------|---------------------|----------------------------------------------------------|
| [`just`][just]           | Task runner         | [See `casey/just`][just], or `cargo binstall just`       |
| [`docker`][docker]       | Container platform  | See [Docker install documentation][docker-install]       |
| [`kustomize`][kustomize] | K8s templating tool | See [Kustomize install documentation][kustomize-install] |
| [`kind`][kind]           | K8s in Docker       | See [Kind install instructions][kind-install]            |


[docker-install]: https://docs.docker.com/get-started/get-docker/
[docker]: https://docs.docker.com
[just]: https://github.com/casey/just
[kind-install]: https://kind.sigs.k8s.io/docs/user/quick-start/#installing-with-a-package-manager
[kustomize-install]: https://kubectl.docs.kubernetes.io/installation/kustomize/
[kustomize]: https://kustomize.io/
[mllb]: https://metallb.universe.tf/

## Quickstart

Assuming you have all the tools installed, getting everything deployed *should be* very easy.

### Start Kind

```console
just setup
```

You should see output like the following:

```
just setup
Creating cluster "exp-traefik" ...
 ✓ Ensuring node image (kindest/node:v1.32.2) 🖼
 ✓ Preparing nodes 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-exp-traefik"
You can now use your cluster with:

kubectl cluster-info --context kind-exp-traefik

Thanks for using kind! 😊


Enter the kind cluster with

kubie ctx kind-exp-traefik

```

Once that is finished you can follow the instructions and enter the `kubie` context (or use some other tool):

```
kubie ctx kind-exp-traefik
```

### Start Kind

**NOTE** Just use `kind` -- it wokrs much better than `k3s` + Docker compose.
It has a thing for loading images into nodes!

```console
just setup
```

Alternatively:

```console
kind create cluster --config kind-config.yaml
```

Following the output of `just setup` you can change context w/ `kubie` (or another tool):

```console
kubie ctx kind-exp-traefik
```

### Deploy the local infra

Deploy the local infra required to make everything work:

```console
just deploy
```

> [!WARNING]
> Unfortunately, you will likely have to run `just deploy` multiple (~3) times!
>
> Please wait around 5 seconds then try again
>
> Common failures include:
>   - CRDs not being created fast enough (upstream resource files do not split split out CRDs)
>   - Validation Webhooks failing (as they startup there can be a lag)
>
> This can be fixed by splitting out the resources and applying them manually in the right order
> but it's easier to just retry after a short wait for now.

Generally, you should not get the same error two times in a row, and at some point (within ~3 runs),
there will be no errors.

**This step will actually deploy the sample workload *as well*.**

After deployment you should see only *one* `HTTPRoute`:

```
NAME                HOSTNAMES               AGE
example.localhost   ["example.localhost"]   2m55s
```

### Find the Gateway IP

Once the workload is deployed, to be access it we need to know the IP of the
automatically created Traefik `Gateway`. You can find that by running:

```console
kubectl get gateway
```

You should see output like:

```
NAME      CLASS     ADDRESS        PROGRAMMED   AGE
traefik   traefik   172.19.255.1   True         92s
```

> [!NOTE]
> At present, `Gateway`s must be in the same namespace as the HTTPRoutes they service to work properly.
>
> This *may* be just a configuration miss, but in general this is not actually a problem with Traefik,
> completely identical Gateways (same port, same endpoint etc) are properly deduped and served appropriately
> as long as their hostnames differ, for `HTTPRoute` objects.
>
> Both gateways have the *same* external address, and traffic is routed appropriately to workloads, and each
> workload is triggered independently by KNative, with shared activator machinery.

### Trigger the Example workload

To trigger the example workload, we can hit the gatway with a custom `Host` header:

```console
curl -H 'Host: example.localhost' 172.19.255.1 -v
```

Deploy the `example` workload w/ Gateway integration:

```console
just deploy-example
```

## Successful Cluster state

Assuming everything was deployed to the `ingress` cluster (alongside `traefik` and the automatically created `Gateway`), things settle like this.

## All of `knative-serving`

```
➜ k get all -n knative-serving
NAME                                             READY   STATUS    RESTARTS   AGE
pod/activator-666895ddd-mbw8x                    1/1     Running   0          5m20s
pod/autoscaler-7f4754ffb4-bv4n2                  1/1     Running   0          5m24s
pod/controller-cc7d86698-rt4qm                   1/1     Running   0          5m24s
pod/net-gateway-api-controller-f89786cfd-fdgz5   1/1     Running   0          5m24s
pod/net-gateway-api-webhook-699b8b87b7-m5wgd     1/1     Running   0          5m24s
pod/webhook-f65b5d96-b8qfb                       1/1     Running   0          5m24s

NAME                                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                                   AGE
service/activator-service            ClusterIP   10.96.214.187   <none>        9090/TCP,8008/TCP,80/TCP,81/TCP,443/TCP   5m24s
service/autoscaler                   ClusterIP   10.96.3.212     <none>        9090/TCP,8008/TCP,8080/TCP                5m24s
service/autoscaler-bucket-00-of-01   ClusterIP   10.96.248.82    <none>        8080/TCP                                  5m13s
service/controller                   ClusterIP   10.96.171.193   <none>        9090/TCP,8008/TCP                         5m24s
service/net-gateway-api-webhook      ClusterIP   10.96.200.191   <none>        9090/TCP,8008/TCP,443/TCP                 5m24s
service/webhook                      ClusterIP   10.96.164.94    <none>        9090/TCP,8008/TCP,443/TCP                 5m24s

NAME                                         READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/activator                    1/1     1            1           5m24s
deployment.apps/autoscaler                   1/1     1            1           5m24s
deployment.apps/controller                   1/1     1            1           5m24s
deployment.apps/net-gateway-api-controller   1/1     1            1           5m24s
deployment.apps/net-gateway-api-webhook      1/1     1            1           5m24s
deployment.apps/webhook                      1/1     1            1           5m24s

NAME                                                   DESIRED   CURRENT   READY   AGE
replicaset.apps/activator-5656895fc6                   0         0         0       5m24s
replicaset.apps/activator-666895ddd                    1         1         1       5m20s
replicaset.apps/autoscaler-7f4754ffb4                  1         1         1       5m24s
replicaset.apps/controller-cc7d86698                   1         1         1       5m24s
replicaset.apps/net-gateway-api-controller-f89786cfd   1         1         1       5m24s
replicaset.apps/net-gateway-api-webhook-699b8b87b7     1         1         1       5m24s
replicaset.apps/webhook-f65b5d96                       1         1         1       5m24s

NAME                                            REFERENCE              TARGETS               MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/activator   Deployment/activator   cpu: <unknown>/100%   1         20        1          5m24s
horizontalpodautoscaler.autoscaling/webhook     Deployment/webhook     cpu: <unknown>/100%   1         5         1          5m24s
```

## All of `ingress`

```
➜ k get all -n ingress
NAME                                            READY   STATUS    RESTARTS   AGE
pod/example-00001-deployment-78964f56d4-92lds   2/2     Running   0          5m29s
pod/traefik-j96x8                               1/1     Running   0          6m7s
pod/traefik-wqr5g                               1/1     Running   0          6m7s

NAME                            TYPE           CLUSTER-IP     EXTERNAL-IP    PORT(S)                                              AGE
service/example                 LoadBalancer   10.96.22.71    172.19.255.2   80:32547/TCP                                         5m29s
service/example-00001           ClusterIP      10.96.42.7     <none>         80/TCP,443/TCP                                       5m29s
service/example-00001-private   ClusterIP      10.96.86.39    <none>         80/TCP,443/TCP,9090/TCP,9091/TCP,8022/TCP,8012/TCP   5m29s
service/traefik                 LoadBalancer   10.96.61.149   172.19.255.1   80:32754/TCP,443:30535/TCP                           6m7s

NAME                     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/traefik   2         2         2       2            2           <none>          6m7s

NAME                                       READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/example-00001-deployment   1/1     1            1           5m29s

NAME                                                  DESIRED   CURRENT   READY   AGE
replicaset.apps/example-00001-deployment-78964f56d4   1         1         1       5m29s

NAME                                        LATESTCREATED   LATESTREADY     READY   REASON
configuration.serving.knative.dev/example   example-00001   example-00001   True

NAME                                         CONFIG NAME   GENERATION   READY   REASON   ACTUAL REPLICAS   DESIRED REPLICAS
revision.serving.knative.dev/example-00001   example       1            True             1                 0

NAME                                URL                                        READY   REASON
route.serving.knative.dev/example   http://example.ingress.svc.cluster.local   False   NotOwned

NAME                                  URL                                        LATESTCREATED   LATESTREADY     READY   REASON
service.serving.knative.dev/example   http://example.ingress.svc.cluster.local   example-00001   example-00001   False   NotOwned

NAME                                                  URL                        READY   REASON
domainmapping.serving.knative.dev/example.localhost   http://example.localhost   True
```

## Troubleshooting

### Stuck `activator` deployment

Sometimes, the `activator` deployment in `knative-serving` gets stuck during startup.

**Quick Fix:** Edit the deployment and remove the liveness & readiness probes to solve this.

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

> [!CAUTION]
> At present, it seems the gateway *must* be in the same namespace as the HTTPRoute
> to work properly.
>
> If using this repo verbatim it shouldn't be an issue (everyting is
> deployed into `ingress`), but this is worth looking into later (it may be just a config mistake).

### Trigger the Example workload

To trigger the example workload, we can hit the gatway with a custom `Host` header:

```console
curl -H 'Host: example.localhost' 172.19.255.1 -v
```

Deploy the `example` workload w/ Gateway integration:

```console
just deploy-example
```

## Troubleshooting

### Stuck `activator` deployment

Sometimes, the `activator` deployment in `knative-serving` gets stuck during startup.

**Quick Fix:** Edit the deployment and remove the liveness & readiness probes to solve this.

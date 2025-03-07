just := env_var_or_default("JUST", "just")
just_dir := env_var_or_default("JUST_DIR", justfile_directory())

docker := env_var_or_default("DOCKER", "docker")
kustomize := env_var_or_default("KUSTOMIZE", "kustomize")
kubectl := env_var_or_default("KUBECTL", "kubectl")
kind := env_var_or_default("KIND", "kind")

code_path := env_var_or_default("CODE_PATH", just_dir / "traefik")

traefik_image_version := env_var_or_default("TRAEFIK_IMAGE_VERSION", "v3.3.3")

kind_ctx_name := env_var_or_default("KIND_CTX_NAME", "kind-exp-traefik")
kind_cluster_name := env_var_or_default("KIND_CLUSTER_NAME", "exp-traefik")

# At present, it lokos like the gateway has to be in the same namespace
# this may just be a configuration mistake.
workload_ns := env_var_or_default("WORKLOAD_NS", "ingress")

@_default:
    {{just}} --list

# Perform setup for local experiment
setup: setup-kind

# Setup the kind cluster
@setup-kind:
    {{kind}} create cluster --config kind-config.yaml
    echo -e "\n\nEnter the kind cluster with\n\nkubie ctx kind-{{kind_cluster_name}}"

# Teardown local experiment
teardown: teardown-kind

@teardown-kind:
    {{kind}} delete cluster --name {{kind_cluster_name}}

# Generate k8s resources
[group('build')]
@generate-k8s:
    {{kustomize}} -o generated.yaml build --enable-helm base

# Deploy all resources required for example knative workload
deploy: deploy-k8s deploy-knative deploy-example

# Deploy k8s resources
[group('deploy')]
@deploy-k8s: generate-k8s
    # Install MetalLB first, get CRDs and operator in place
    {{kubectl}} apply --server-side --force-conflicts -n metallb-system -f {{just_dir}}/metallb/metallb-native.yaml
    {{kubectl}} apply --server-side --force-conflicts -n metallb-system -f {{just_dir}}/metallb/kind-workers.l2advertisement.yaml
    {{kubectl}} apply --server-side --force-conflicts -n metallb-system -f {{just_dir}}/metallb/kind.ipaddresspool.yaml
    # Install Gateway channel experimental support
    {{kubectl}} apply --server-side -f {{just_dir}}/gateway-api/experimental-install.yaml
    # Install rest of kustomize-managed resources
    {{kubectl}} apply --server-side --force-conflicts -n ingress -f {{just_dir}}/generated.yaml

# Deploy Knative
[group('deploy')]
@deploy-knative:
    {{kubectl}} apply -f {{just_dir}}/knative/knative.crds.yaml
    # NOTE: knative serving required some changes (disabling validating webhooks, due to API server <-> node connection issues)
    {{kubectl}} apply -f {{just_dir}}/knative/knative.serving.yaml
    # NOTE: net-gateway-api validating webhook removed!
    {{kubectl}} apply -n knative-serving -f {{just_dir}}/knative/net-gateway-api.yaml
    {{kubectl}} apply -n knative-serving -f {{just_dir}}/knative/config-network.configmap.yaml
    {{kubectl}} apply -n knative-serving -f {{just_dir}}/knative/config-gateway.configmap.yaml
    # We need to remove the liveness/readiness probes on the activator, not sure why it stalls/doesn't come up
    # properly
    sleep 3
    echo -e "\n==> removing activator patch\n"
    {{kubectl}} patch deployment -n knative-serving activator --type=json -p='[{"op": "remove", "path": "/spec/template/spec/containers/0/livenessProbe"}, {"op": "remove", "path": "/spec/template/spec/containers/0/readinessProbe"}]'

# Deploy the example workload (knative)
[group('workload')]
@deploy-example:
    {{kubectl}} apply -n {{workload_ns}} -f {{just_dir}}/workload/add-prefix-gwapi.middleware.yaml
    {{kubectl}} apply -n {{workload_ns}} -f {{just_dir}}/workload/example.clusterdomainclaim.yaml
    {{kubectl}} apply -n {{workload_ns}} -f {{just_dir}}/workload/example.domainmapping.yaml
    # NOTE: The overriding service (w/ LoadBalancer) must be deployed BEFORE the Knative Service!
    {{kubectl}} apply -n {{workload_ns}} -f {{just_dir}}/workload/example.svc.yaml
    {{kubectl}} apply -n {{workload_ns}} -f {{just_dir}}/workload/example.knativesvc.yaml
    {{kubectl}} apply -n {{workload_ns}} -f {{just_dir}}/workload/example.httproute.yaml

[group('workload')]
@undeploy-example:
    {{kubectl}} delete -n {{workload_ns}} -f {{just_dir}}/workload/example.knativesvc.yaml || true
    {{kubectl}} delete -n {{workload_ns}} -f {{just_dir}}/workload/add-prefix-gwapi.middleware.yaml || true
    {{kubectl}} delete -n {{workload_ns}} -f {{just_dir}}/workload/example.domainmapping.yaml || true
    {{kubectl}} delete -n {{workload_ns}} -f {{just_dir}}/workload/example.clusterdomainclaim.yaml || true
    {{kubectl}} delete -n {{workload_ns}} -f {{just_dir}}/workload/example.svc.yaml || true
    {{kubectl}} delete -n {{workload_ns}} -f {{just_dir}}/workload/example.httproute.yaml || true

[group('workload')]
@deploy-example-custom-httproute:
    # NOTE: creating a custom HTTPRoute is *not* necessary, but can enable custom Traefik middlewares
    #
    # Since there are some injected middlewares that Knative creates, it may not be a great idea to
    # override those.
    #
    # With this custom HTTP route requests work fine, but Knative-provided middlewares are stripped,
    # only the ones specified by the user remain -- a patch is much better!
    {{kubectl}} apply -f {{just_dir}}/workload/example.httproute.yaml || true


[group('workload')]
@undeploy-example-custom-httproute:
    {{kubectl}} delete -f {{just_dir}}/workload/example.httproute.yaml || true

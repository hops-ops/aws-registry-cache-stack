# aws-registry-cache-stack

`RegistryCache` (`registrycaches.aws.hops.ops.com.ai`) manages on-demand OCI
registry proxy caches using CNCF Distribution, S3 storage, and optional EKS
PodIdentity.

## Why RegistryCache?

Crossplane packages and Kubernetes images may come from registries that AWS ECR
pull-through cache does not support, including `xpkg.crossplane.io` and
`xpkg.upbound.io`. Scheduled mirroring works, but it is not pull-through: new
image requirements wait for the next sync, tag selection is hard to keep clean,
and stale data accumulates.

This stack uses one Distribution proxy cache per upstream registry. Images are
fetched when first requested, cached in S3, and served through a stable in-cluster
registry service. When package rewrites need to be consumed by node image pulls,
the stack can also attach those internal services to an existing Istio Gateway
with Gateway API `HTTPRoute` resources.

With this stack:

- Distribution proxy caches provide pull-through behavior for any configured OCI
  registry.
- S3 stores cached blobs under per-upstream prefixes in one bucket.
- Crossplane `ImageConfig` resources can optionally rewrite package pulls to a
  cache endpoint.
- Gateway API routes can expose caches through a trusted, node-resolvable Istio
  Gateway endpoint.
- PodIdentity can grant the registry pods only the S3 permissions they need.
- S3 lifecycle configuration can clean up incomplete multipart uploads.

This stack no longer composes AWS ECR pull-through cache rules, ECR repository
creation templates, or a scheduled mirror CronJob. `public.ecr.aws` can still be
configured as a normal upstream when you want to cache public ECR images through
Distribution.

## Getting Started

Create a cache for Crossplane packages:

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: RegistryCache
metadata:
  name: platform-registry-cache
  namespace: default
spec:
  accountId: "123456789012"
  region: us-east-2
  clusterName: platform-cluster
  providerConfigRefs:
    kubernetes:
      name: platform-cluster
      kind: ProviderConfig
  distribution:
    enabled: true
    storage:
      bucketName: platform-registry-cache
      rootPrefix: crossplane-packages
    gateway:
      enabled: true
      hostname: rc.internal.example.com
      httpRouteAnnotations:
        external-dns.alpha.kubernetes.io/cloudflare-proxied: "false"
      gatewayRef:
        name: platform
        namespace: istio-ingress
        sectionNames:
          - https-apex
    upstreams:
      - name: xpkg-crossplane
        sourceRegistry: xpkg.crossplane.io
        rewrite:
          enabled: true
      - name: xpkg-upbound
        sourceRegistry: xpkg.upbound.io
        rewrite:
          enabled: true
```

For `xpkg.crossplane.io`, the stack renders a Kubernetes Service similar to:

```text
platform-registry-cache-dist-xpkg-crossplane.crossplane-system.svc.cluster.local:5000
```

## Standard Upstreams

The `standard.yaml` example configures common public registries:

```yaml
spec:
  distribution:
    enabled: true
    storage:
      bucketName: platform-registry-cache
      rootPrefix: distribution
    upstreams:
      - name: docker-hub
        sourceRegistry: registry-1.docker.io
        matchPrefix: docker.io
        remoteUrl: https://registry-1.docker.io
      - name: ghcr
        sourceRegistry: ghcr.io
      - name: quay
        sourceRegistry: quay.io
      - name: ecr-public
        sourceRegistry: public.ecr.aws
      - name: kubernetes
        sourceRegistry: registry.k8s.io
      - name: xpkg-crossplane
        sourceRegistry: xpkg.crossplane.io
      - name: xpkg-upbound
        sourceRegistry: xpkg.upbound.io
```

`sourceRegistry` is the upstream registry host. `remoteUrl` defaults to
`https://<sourceRegistry>`. `matchPrefix` defaults to `sourceRegistry`, but Docker
Hub usually needs `matchPrefix: docker.io` and
`remoteUrl: https://registry-1.docker.io`.

`xpkg.crossplane.io` is a registry alias backed by GHCR for public
`crossplane-contrib` packages. The stack keeps `matchPrefix:
xpkg.crossplane.io` for Crossplane package references, but defaults the
Distribution `remoteUrl` to `https://ghcr.io` so proxy-cache auth works with
CNCF Distribution.

## Storage

By default the stack creates one private S3 bucket named from account, region,
and XR name. Set `spec.distribution.storage.bucketName` to choose an explicit
bucket name, or set `createBucket: false` when the bucket is managed elsewhere.

Each upstream gets its own `rootdirectory` under the bucket:

```text
/<rootPrefix>/<upstream name>
```

The default S3 lifecycle policy only aborts incomplete multipart uploads after 7
days. It does not delete cached registry blobs. Tagged-image pruning is not part
of this proxy-cache implementation because Distribution owns the cache contents
and refresh behavior.

## AWS Access

By default, `spec.distribution.podIdentity.enabled` is `true`. The stack composes
a `PodIdentity` for the shared Distribution ServiceAccount and grants:

- `s3:GetBucketLocation`, `s3:ListBucket`, and multipart list access on the
  bucket.
- `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, multipart upload access on
  the configured upstream object prefixes.

Disable it when the target cluster injects credentials another way:

```yaml
spec:
  distribution:
    podIdentity:
      enabled: false
```

## Trusted Gateway Endpoint

Crossplane `ImageConfig` rewrites affect package runtime pods, and those images
are pulled by the node/container runtime. That means the rewrite target must be
DNS-resolvable from nodes and must serve TLS with a certificate trusted by the
nodes.

Use `spec.distribution.gateway` when the platform Istio Gateway already handles
DNS and TLS:

```yaml
spec:
  distribution:
    gateway:
      enabled: true
      hostname: rc.internal.example.com
      httpRouteAnnotations:
        external-dns.alpha.kubernetes.io/cloudflare-proxied: "false"
      gatewayRef:
        name: platform
        namespace: istio-ingress
        sectionNames:
          - https-apex
    upstreams:
      - name: xpkg-crossplane
        sourceRegistry: xpkg.crossplane.io
        rewrite:
          enabled: true
```

`httpRouteAnnotations` is applied to both the registry ping route and each
upstream route. When ExternalDNS is configured to proxy Cloudflare records by
default, set `external-dns.alpha.kubernetes.io/cloudflare-proxied: "false"` for
an internal load balancer. This keeps the DNS record resolvable by cluster nodes
without routing registry traffic through Cloudflare.

For each exposed upstream, the stack renders an `HTTPRoute` matching
`/v2/<normalized matchPrefix>`, rewrites that path back to `/v2`, and sends the
request to the internal Distribution Service. It also renders one `/v2` route per
hostname so Docker-compatible clients can complete the registry ping. With the
example above, the generated `ImageConfig` rewrite prefix is:

```text
rc.internal.example.com/xpkg-crossplane-io
```

The referenced Gateway listener must allow routes from the Distribution
namespace, for example `allowedRoutes.namespaces.from: All` on the platform
Gateway listener.

## ImageConfig

Each upstream can render a Crossplane `ImageConfig`:

```yaml
spec:
  distribution:
    upstreams:
      - name: xpkg-crossplane
        sourceRegistry: xpkg.crossplane.io
        rewrite:
          enabled: true
```

Rewriting is disabled by default. Enable it only when `distribution.gateway`
provides a trusted endpoint or when `rewrite.prefix` is set explicitly. The stack
does not default ImageConfig rewrites to the cluster-local
`*.svc.cluster.local` Service address because that endpoint is not usable by
node image pulls.

Leave rewriting disabled when the cache is used by a different consumer:

```yaml
spec:
  distribution:
    upstreams:
      - name: ghcr
        sourceRegistry: ghcr.io
        rewrite:
          enabled: false
```

Override the rendered `ImageConfig` name or rewrite prefix when exposing the
cache through another DNS name:

```yaml
spec:
  distribution:
    upstreams:
      - name: ghcr
        sourceRegistry: ghcr.io
        rewrite:
          imageConfigName: ghcr-cache
          prefix: registry-cache.internal.example.com/ghcr-io
```

## Composed Resources

- `Bucket`, `BucketPublicAccessBlock`, `BucketServerSideEncryptionConfiguration`,
  and optional `BucketLifecycleConfiguration` for S3 cache storage.
- Kubernetes `Object` resources for the ServiceAccount, ConfigMaps,
  Deployments, Services, optional Gateway API `HTTPRoute` resources, and optional
  `ImageConfig` resources.
- `PodIdentity` for S3 access when enabled.

## Status

`status.distribution` reports whether Distribution is enabled and ready, the
namespace, bucket name, and per-upstream service/rewrite details.

## Development

```bash
make render
make validate
make test
make e2e
```

For local control plane iteration:

```bash
hops config install --path xrs/stacks/aws/registry-cache --context colima
kubectl --context colima apply -f examples/registrycaches/standard.yaml
```

## References

- CNCF Distribution configuration: https://distribution.github.io/distribution/about/configuration/
- CNCF Distribution proxy mode: https://distribution.github.io/distribution/recipes/mirror/
- Crossplane ImageConfig: https://docs.crossplane.io/latest/packages/image-configs/
- Gateway API HTTPRoute: https://gateway-api.sigs.k8s.io/api-types/httproute/
- Istio Gateway API: https://istio.io/latest/docs/tasks/traffic-management/ingress/gateway-api/

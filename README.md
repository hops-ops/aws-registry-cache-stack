# aws-registry-cache-stack

`AWSRegistryCacheStack` combines two registry cache paths:

- `ECRRegistryCache` for AWS-supported ECR pull-through cache upstreams such as
  ECR Public, `registry.k8s.io`, Quay, Docker Hub, and GHCR.
- A scheduled Kubernetes mirror job for unsupported OCI registries such as
  `xpkg.crossplane.io` and `xpkg.upbound.io`.

AWS ECR pull-through cache does not support arbitrary upstream registries, so
Crossplane package registries are mirrored into private ECR repositories instead
of being configured as pull-through rules.

## Getting Started

Create pull-through cache rules for supported public upstreams:

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: AWSRegistryCacheStack
metadata:
  name: platform-registry-cache
  namespace: default
spec:
  accountId: "123456789012"
  region: us-east-2
  pullThrough:
    enabled: true
    rules:
      - name: ecr-public
        ecrRepositoryPrefix: ecr-public
        upstreamRegistryUrl: public.ecr.aws
        repositoryCreationTemplate:
          enabled: true
      - name: kubernetes
        ecrRepositoryPrefix: kubernetes
        upstreamRegistryUrl: registry.k8s.io
        repositoryCreationTemplate:
          enabled: true
```

The stack depends on `ghcr.io/hops-ops/aws-ecr-registry-cache` and composes an
`ECRRegistryCache` claim with the same name as the stack.

Consumers pull through the private ECR host:

```text
123456789012.dkr.ecr.us-east-2.amazonaws.com/kubernetes/nginx-slim:latest
```

## Mirroring Crossplane Packages

Enable the mirror job to copy unsupported repositories into ECR:

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: AWSRegistryCacheStack
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
  mirror:
    enabled: true
    namespace: crossplane-system
    repositories:
      - source: xpkg.crossplane.io/crossplane-contrib/provider-aws-ecr:v2.5.0
      - source: xpkg.crossplane.io/crossplane-contrib/function-auto-ready
```

Source refs are normalized to repositories before mirroring. For example:

```text
xpkg.crossplane.io/crossplane-contrib/provider-aws-ecr:v2.5.0
```

mirrors every tag from:

```text
xpkg.crossplane.io/crossplane-contrib/provider-aws-ecr
```

into:

```text
123456789012.dkr.ecr.us-east-2.amazonaws.com/xpkg-crossplane/crossplane-contrib/provider-aws-ecr
```

The job also discovers live Crossplane package resources by reading:

- `providers.pkg.crossplane.io`
- `functions.pkg.crossplane.io`
- `configurations.pkg.crossplane.io`

Explicit repositories and discovered repositories are deduplicated by normalized
source repository.

## Mirror Runtime

The default CronJob image is:

```text
ghcr.io/hops-ops/registry-cache-mirror:latest
```

That image is built from `images/mirror/Dockerfile` in this repo and includes
`sh`, `kubectl`, `jq`, `aws`, `regsync`, and `docker-credential-ecr-login`.
Override `spec.mirror.image` if you build a different utility image.

The wrapper creates missing ECR repositories, writes a repository-mode
`regsync.yml`, and runs:

```bash
regsync once --missing
```

Set `spec.mirror.regsync.missingOnly: false` to run `regsync once` instead.

## Tag Filters

All tags are mirrored by default. Add repository-specific filters when storage
cost or blast radius matters:

```yaml
spec:
  mirror:
    repositories:
      - source: xpkg.crossplane.io/crossplane-contrib/provider-aws-ecr
        tags:
          allow:
            - "^v2\\."
          deny:
            - ".*-rc\\..*"
```

The wrapper passes `allow`, `deny`, and `semverRange` filters into generated
`regsync` repository entries.

## AWS Access

By default, `spec.mirror.podIdentity.enabled` is `true`. The stack composes a
`PodIdentity` for the mirror ServiceAccount and scopes ECR write permissions to
the configured target prefixes, such as:

```text
arn:aws:ecr:us-east-2:123456789012:repository/xpkg-crossplane/*
arn:aws:ecr:us-east-2:123456789012:repository/xpkg-upbound/*
```

Disable PodIdentity when the target cluster already injects AWS credentials:

```yaml
spec:
  mirror:
    podIdentity:
      enabled: false
```

## Crossplane ImageConfig

This stack does not create Crossplane `ImageConfig` resources. Rewriting package
pulls is consumer-side behavior and should be enabled by the Crossplane stack
that owns package resolution.

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
kubectl --context colima apply -f examples/awsregistrycachestacks/standard.yaml
```

## References

- regsync usage: https://regclient.org/usage/regsync/
- ECR pull-through cache: https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html
- Crossplane ImageConfig: https://docs.crossplane.io/latest/packages/image-configs/

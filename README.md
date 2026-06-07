# aws-registry-cache-stack

`RegistryCache` (`registrycaches.aws.hops.ops.com.ai`) manages AWS ECR
pull-through cache rules and scheduled OCI repository mirroring into ECR.

## Why RegistryCache?

Without this stack, registry cache setup is split across ECR pull-through rules,
repository creation templates, scanning configuration, Kubernetes discovery
RBAC, mirror jobs, and optional EKS PodIdentity wiring.

With this stack:

- AWS-supported upstreams use native ECR pull-through cache rules.
- Unsupported registries such as `xpkg.crossplane.io` and `xpkg.upbound.io` are
  mirrored into private ECR repositories.
- Mirror repositories can be created declaratively through ECR
  `RepositoryCreationTemplate` resources with lifecycle policy attached.
- Crossplane package resources can be discovered from the cluster so declared
  providers, functions, and configurations are mirrored automatically.

## Getting Started

Create pull-through cache rules for supported public upstreams:

```yaml
apiVersion: aws.hops.ops.com.ai/v1alpha1
kind: RegistryCache
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

Consumers pull through the private ECR host:

```text
123456789012.dkr.ecr.us-east-2.amazonaws.com/kubernetes/nginx-slim:latest
```

## Growing

Enable the mirror job for unsupported OCI registries:

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

mirrors release tags from:

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

## Enterprise Scale

Use declarative repository creation templates for mirror-created repositories
when lifecycle policy, repository policy, or tag behavior should be controlled by
ECR instead of the mirror script:

```yaml
spec:
  mirror:
    enabled: true
    lifecyclePolicy:
      enabled: true
      untaggedExpireAfterDays: 1
```

When lifecycle policy is enabled, the stack renders ECR
`RepositoryCreationTemplate` resources with `appliedFor: ["CREATE_ON_PUSH"]`.
The mirror wrapper stops calling `aws ecr create-repository`; ECR creates new
repositories on first push and applies the template policy.

This affects future repositories created through the template. Existing ECR
repositories need their lifecycle policy applied separately or adopted under a
future explicit repository-management feature.

## Tag Filters

Mirror tag policy defaults to release-style tags that start with `v`:

```yaml
spec:
  mirror:
    tags:
      mode: filtered
      allow:
        - "^v.*"
```

Override the policy globally or per repository when a source needs different
tags:

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

## Mirror Runtime

The default CronJob image is:

```text
ghcr.io/hops-ops/registry-cache-mirror:latest
```

That image is built from `images/mirror/Dockerfile` in this repo and includes
`sh`, `kubectl`, `jq`, `aws`, `regsync`, and `docker-credential-ecr-login`.
Override `spec.mirror.image` if you build a different utility image.

The wrapper writes a repository-mode `regsync.yml` and runs:

```bash
regsync once --missing
```

Set `spec.mirror.regsync.missingOnly: false` to run `regsync once` instead.

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

## Import Existing

Set `spec.managementPolicies` to observe or update existing AWS resources before
allowing create/delete behavior. Existing mirror-created ECR repositories are not
claimed directly by this stack today; lifecycle policy on existing repositories
must be managed separately until explicit repository adoption is added.

## Status

`status.registry.host` exposes the target private ECR registry.
`status.pullThrough.rules[*].pullPrefix` exposes the private pull prefix for each
native cache rule. `status.mirror` reports whether the mirror path is enabled,
ready, which registry it targets, and how many mirror repository creation
templates are rendered.

## Composed Resources

- `PullThroughCacheRule` - one direct ECR pull-through cache rule per
  `spec.pullThrough.rules[]` entry.
- `RepositoryCreationTemplate` - optional ECR templates for pull-through
  repositories and mirror create-on-push repositories.
- `RegistryScanningConfiguration` - optional registry-wide ECR enhanced scanning
  configuration for pull-through prefixes.
- `Object` - Kubernetes namespace, ServiceAccount, RBAC, ConfigMap, and CronJob
  resources for the mirror runtime.
- `PodIdentity` - optional EKS PodIdentity for mirror ECR write access.

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
kubectl --context colima apply -f examples/registrycaches/standard.yaml
```

## References

- regsync usage: https://regclient.org/usage/regsync/
- ECR pull-through cache: https://docs.aws.amazon.com/AmazonECR/latest/userguide/pull-through-cache.html
- ECR repository creation templates: https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-creation-templates.html
- ECR lifecycle policies: https://docs.aws.amazon.com/AmazonECR/latest/userguide/LifecyclePolicies.html
- Crossplane ImageConfig: https://docs.crossplane.io/latest/packages/image-configs/

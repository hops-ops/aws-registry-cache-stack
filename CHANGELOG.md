# Changelog

## Unreleased

- BREAKING CHANGE: Distribution Service/Deployment names default to the
  upstream name (`ghcr`), not `{xr}-dist-{upstream}`. Override with
  `spec.distribution.upstreams[].service.name`.
- BREAKING CHANGE: when gateway exposure is off, ImageConfig rewrite defaults
  to `{service}.{namespace}.svc.cluster.local` and TLS is enabled (cert-manager
  self-signed Issuer + Certificate, Service port 443). Crossplane talks HTTPS;
  plain HTTP `:5000` is not used for package pulls.
- Add `spec.distribution.storage.type`: `s3` (default), `pvc`, or `emptyDir`.
  `pvc` is one RWO volume per upstream; S3 bucket and PodIdentity are skipped.
- Add `spec.distribution.tls` (leaf Certificates only). Default issuer is
  ClusterIssuer `internal-ca` from CertStack `spec.internalCA`. This stack
  does not create a CA.
- PVC + ReadWriteOnce rejects `replicas` greater than 1. Rewrite without
  gateway requires TLS or an explicit `rewrite.prefix`.

## v0.2.0

- BREAKING CHANGE: replace ECR pull-through cache rules and the scheduled mirror
  CronJob with S3-backed CNCF Distribution proxy caches.
- Add Distribution deployments, services, config maps, and optional Crossplane
  `ImageConfig` rewrites per upstream registry.
- Add S3 bucket, public-access-block, encryption, lifecycle, and PodIdentity
  resources for cache storage.

## v0.1.0

- Initial release of the AWS registry cache stack.
- Combines ECR pull-through cache rules with a scheduled Kubernetes mirror job
  for unsupported OCI registries.
- Adds Crossplane package discovery and optional PodIdentity for ECR writes.

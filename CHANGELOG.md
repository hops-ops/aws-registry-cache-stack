# Changelog

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

# Changelog

## v0.1.0

- Initial release of the AWS registry cache stack.
- Combines ECR pull-through cache rules with a scheduled Kubernetes mirror job
  for unsupported OCI registries.
- Adds Crossplane package discovery and optional PodIdentity for ECR writes.

### What's changed in v3.0.0

* chore(deps): migrate workflows-crossplane to hops-ops@v3.2.0 (by @patrickleet)

* chore(deps): update unbounded-tech/workflow-vnext-tag action to v1.22.3 (by @renovate[bot])

  Co-authored-by: renovate[bot] <29139614+renovate[bot]@users.noreply.github.com>

* chore(deps): update unbounded-tech/workflow-simple-release action to v2.1.3 (by @renovate[bot])

  Co-authored-by: renovate[bot] <29139614+renovate[bot]@users.noreply.github.com>
  Co-authored-by: Patrick Lee Scott <pat@patscott.io>

* fix: emit GA external-dns annotations on registry HTTPRoutes (by @patrickleet)

  BREAKING CHANGE: * fix!: emit GA external-dns annotations on registry HTTPRoutes

  BREAKING CHANGE: httpRouteAnnotations examples and tests move from
  external-dns.alpha.kubernetes.io/* to external-dns.kubernetes.io/*.
  Coordinate with aws-dns-stack / cloudflare-dns-stack GA majors.

  * docs: retarget ExternalDNS examples to GA annotation prefix

  * test: expect GA external-dns annotations on registry HTTPRoutes


See full diff: [v2.1.0...v3.0.0](https://github.com/hops-ops/aws-registry-cache-stack/compare/v2.1.0...v3.0.0)

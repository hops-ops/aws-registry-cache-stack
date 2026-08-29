_composition = "apis/registrycaches/composition.yaml"
_xrd = "apis/registrycaches/definition.yaml"

_items = [
    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "distribution-renders-s3-and-proxy-runtime"
        spec = {
            compositionPath = _composition
            xrdPath = _xrd
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "RegistryCache"
                metadata.name = "platform"
                metadata.namespace = "default"
                spec = {
                    accountId = "123456789012"
                    region = "us-east-2"
                    distribution = {
                        enabled = True
                        podIdentity = {
                            enabled = False
                        }
                        storage = {
                            lifecycle = {
                                abortIncompleteMultipartUploadDays = 2
                            }
                        }
                        upstreams = [
                            {
                                name = "xpkg-crossplane"
                                sourceRegistry = "xpkg.crossplane.io"
                            }
                        ]
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "s3.aws.m.upbound.io/v1beta1"
                    kind = "Bucket"
                    metadata.name = "platform-distribution-bucket"
                    metadata.annotations = {
                        "crossplane.io/external-name" = "hops-123456789012-us-east-2-platform-registry-cache"
                    }
                    spec = {
                        managementPolicies = ["*"]
                        forProvider = {
                            region = "us-east-2"
                            tags = {
                                "hops.ops.com.ai/managed" = "true"
                                "hops.ops.com.ai/registrycache" = "platform"
                            }
                        }
                        providerConfigRef = {
                            name = "default"
                            kind = "ProviderConfig"
                        }
                    }
                }
                {
                    apiVersion = "s3.aws.m.upbound.io/v1beta1"
                    kind = "BucketLifecycleConfiguration"
                    metadata.name = "platform-distribution-bucket-lifecycle"
                    metadata.annotations = {
                        "crossplane.io/external-name" = "hops-123456789012-us-east-2-platform-registry-cache"
                    }
                    spec.forProvider = {
                        bucket = "hops-123456789012-us-east-2-platform-registry-cache"
                        region = "us-east-2"
                        transitionDefaultMinimumObjectSize = "all_storage_classes_128K"
                        rule = [
                            {
                                id = "abort-incomplete-multipart-uploads"
                                status = "Enabled"
                                "filter" = [
                                    {
                                        prefix = ""
                                    }
                                ]
                                abortIncompleteMultipartUpload = [
                                    {
                                        daysAfterInitiation = 2
                                    }
                                ]
                            }
                        ]
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-dist-xpkg-crossplane-config"
                    spec.forProvider.manifest = {
                        apiVersion = "v1"
                        kind = "ConfigMap"
                        metadata = {
                            name = "platform-dist-xpkg-crossplane"
                            namespace = "crossplane-system"
                        }
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-dist-xpkg-crossplane-deploy"
                    spec.forProvider.manifest = {
                        apiVersion = "apps/v1"
                        kind = "Deployment"
                        metadata = {
                            name = "platform-dist-xpkg-crossplane"
                            namespace = "crossplane-system"
                        }
                        spec.template.spec = {
                            serviceAccountName = "platform-distribution"
                            containers = [
                                {
                                    name = "registry"
                                    # renovate: datasource=docker depName=library/registry registryUrl=https://index.docker.io
                                    image = "registry:3"
                                    args = [
                                        "serve"
                                        "/etc/distribution/config.yml"
                                    ]
                                }
                            ]
                        }
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-dist-xpkg-crossplane-service"
                    spec.forProvider.manifest = {
                        apiVersion = "v1"
                        kind = "Service"
                        metadata = {
                            name = "platform-dist-xpkg-crossplane"
                            namespace = "crossplane-system"
                        }
                        spec = {
                            type = "ClusterIP"
                            ports = [
                                {
                                    name = "registry"
                                    port = 5000
                                    targetPort = "registry"
                                }
                            ]
                        }
                    }
                }
            ]
        }
    }

    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "distribution-renders-pod-identity-and-dockerhub-rewrite"
        spec = {
            compositionPath = _composition
            xrdPath = _xrd
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "RegistryCache"
                metadata.name = "platform"
                metadata.namespace = "default"
                spec = {
                    accountId = "123456789012"
                    region = "us-east-2"
                    clusterName = "platform-cluster"
                    providerConfigRefs = {
                        kubernetes = {
                            name = "platform-cluster"
                            kind = "ProviderConfig"
                        }
                    }
                    labels = {
                        team = "platform"
                    }
                    tags = {
                        team = "platform"
                    }
                    distribution = {
                        enabled = True
                        storage = {
                            bucketName = "platform-registry-cache"
                            rootPrefix = "distribution"
                        }
                        podIdentity = {
                            rolePrefix = "platform-"
                        }
                        gateway = {
                            enabled = True
                            hostname = "rc.internal.example.com"
                            gatewayRef = {
                                name = "platform"
                                namespace = "istio-ingress"
                                sectionNames = [
                                    "https-apex"
                                ]
                            }
                        }
                        upstreams = [
                            {
                                name = "docker-hub"
                                sourceRegistry = "registry-1.docker.io"
                                matchPrefix = "docker.io"
                                remoteUrl = "https://registry-1.docker.io"
                                rewrite = {
                                    enabled = True
                                }
                            }
                            {
                                name = "xpkg-upbound"
                                sourceRegistry = "xpkg.upbound.io"
                            }
                        ]
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                    kind = "PodIdentity"
                    metadata.name = "platform-distribution"
                    spec = {
                        clusterName = "platform-cluster"
                        region = "us-east-2"
                        rolePrefix = "platform-"
                        serviceAccount = {
                            name = "platform-distribution"
                            namespace = "crossplane-system"
                        }
                        providerConfigRef = {
                            name = "default"
                            kind = "ProviderConfig"
                        }
                        inlinePolicy = [
                            {
                                name = "distribution-s3-cache"
                            }
                        ]
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-dist-docker-hub-deploy"
                    spec = {
                        providerConfigRef = {
                            name = "platform-cluster"
                            kind = "ProviderConfig"
                        }
                        forProvider.manifest.spec.template.metadata.annotations = {
                            "hops.ops.com.ai/pod-identity-association-id" = "pending"
                        }
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-dist-docker-hub-root-httproute"
                    spec = {
                        providerConfigRef = {
                            name = "platform-cluster"
                            kind = "ProviderConfig"
                        }
                        forProvider.manifest = {
                            apiVersion = "gateway.networking.k8s.io/v1"
                            kind = "HTTPRoute"
                            metadata = {
                                name = "platform-dist-docker-hub-root"
                                namespace = "crossplane-system"
                            }
                            spec = {
                                parentRefs = [
                                    {
                                        name = "platform"
                                        namespace = "istio-ingress"
                                        sectionName = "https-apex"
                                    }
                                ]
                                hostnames = [
                                    "rc.internal.example.com"
                                ]
                                rules = [
                                    {
                                        matches = [
                                            {
                                                path = {
                                                    type = "PathPrefix"
                                                    value = "/v2"
                                                }
                                            }
                                        ]
                                        backendRefs = [
                                            {
                                                name = "platform-dist-docker-hub"
                                                port = 5000
                                            }
                                        ]
                                    }
                                ]
                            }
                        }
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-dist-docker-hub-httproute"
                    spec = {
                        providerConfigRef = {
                            name = "platform-cluster"
                            kind = "ProviderConfig"
                        }
                        forProvider.manifest = {
                            apiVersion = "gateway.networking.k8s.io/v1"
                            kind = "HTTPRoute"
                            metadata = {
                                name = "platform-dist-docker-hub"
                                namespace = "crossplane-system"
                            }
                            spec = {
                                parentRefs = [
                                    {
                                        name = "platform"
                                        namespace = "istio-ingress"
                                        sectionName = "https-apex"
                                    }
                                ]
                                hostnames = [
                                    "rc.internal.example.com"
                                ]
                                rules = [
                                    {
                                        matches = [
                                            {
                                                path = {
                                                    type = "PathPrefix"
                                                    value = "/v2/docker-io"
                                                }
                                            }
                                        ]
                                        filters = [
                                            {
                                                type = "URLRewrite"
                                                urlRewrite = {
                                                    path = {
                                                        type = "ReplacePrefixMatch"
                                                        replacePrefixMatch = "/v2"
                                                    }
                                                }
                                            }
                                        ]
                                        backendRefs = [
                                            {
                                                name = "platform-dist-docker-hub"
                                                port = 5000
                                            }
                                        ]
                                    }
                                ]
                            }
                        }
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-dist-docker-hub-imgcfg"
                    spec = {
                        providerConfigRef = {
                            name = "platform-cluster"
                            kind = "ProviderConfig"
                        }
                        forProvider.manifest = {
                            apiVersion = "pkg.crossplane.io/v1beta1"
                            kind = "ImageConfig"
                            metadata.name = "platform-dist-docker-hub"
                            spec = {
                                matchImages = [
                                    {
                                        prefix = "docker.io"
                                        type = "Prefix"
                                    }
                                ]
                                rewriteImage = {
                                    prefix = "rc.internal.example.com/docker-io"
                                }
                            }
                        }
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-dist-xpkg-upbound-config"
                    spec.forProvider.manifest = {
                        apiVersion = "v1"
                        kind = "ConfigMap"
                        metadata.name = "platform-dist-xpkg-upbound"
                    }
                }
            ]
        }
    }

    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "distribution-supports-custom-service-and-imageconfig"
        spec = {
            compositionPath = _composition
            xrdPath = _xrd
            timeoutSeconds = 60
            validate = False
            xr = {
                apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                kind = "RegistryCache"
                metadata.name = "platform"
                metadata.namespace = "default"
                spec = {
                    accountId = "123456789012"
                    region = "us-east-2"
                    distribution = {
                        enabled = True
                        podIdentity = {
                            enabled = False
                        }
                        upstreams = [
                            {
                                name = "ghcr"
                                sourceRegistry = "ghcr.io"
                                service = {
                                    type = "NodePort"
                                    port = 5050
                                }
                                rewrite = {
                                    enabled = True
                                    imageConfigName = "ghcr-cache"
                                    prefix = "registry-cache.internal:5050"
                                }
                            }
                        ]
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-dist-ghcr-service"
                    spec.forProvider.manifest.spec = {
                        type = "NodePort"
                        ports = [
                            {
                                name = "registry"
                                port = 5050
                                targetPort = "registry"
                            }
                        ]
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-dist-ghcr-imgcfg"
                    spec.forProvider.manifest = {
                        apiVersion = "pkg.crossplane.io/v1beta1"
                        kind = "ImageConfig"
                        metadata.name = "ghcr-cache"
                        spec.rewriteImage = {
                            prefix = "registry-cache.internal:5050"
                        }
                    }
                }
            ]
        }
    }
]

items = _items

_composition = "apis/registrycaches/composition.yaml"
_xrd = "apis/registrycaches/definition.yaml"

_items = [
    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "pull-through-renders-direct-ecr-resources"
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
                    providerConfigRefs = {
                        aws = {
                            name = "aws-prod"
                            kind = "ProviderConfig"
                        }
                    }
                    pullThrough = {
                        enabled = True
                        rules = [
                            {
                                name = "kubernetes"
                                ecrRepositoryPrefix = "kubernetes"
                                upstreamRegistryUrl = "registry.k8s.io"
                                repositoryCreationTemplate = {
                                    enabled = True
                                }
                            }
                        ]
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "ecr.aws.m.upbound.io/v1beta1"
                    kind = "PullThroughCacheRule"
                    metadata.name = "platform-kubernetes"
                    spec = {
                        managementPolicies = ["*"]
                        forProvider = {
                            region = "us-east-2"
                            ecrRepositoryPrefix = "kubernetes"
                            upstreamRegistryUrl = "registry.k8s.io"
                        }
                        providerConfigRef = {
                            name = "aws-prod"
                            kind = "ProviderConfig"
                        }
                    }
                }
                {
                    apiVersion = "ecr.aws.m.upbound.io/v1beta1"
                    kind = "RepositoryCreationTemplate"
                    metadata.name = "platform-kubernetes"
                    spec = {
                        managementPolicies = ["*"]
                        forProvider = {
                            region = "us-east-2"
                            prefix = "kubernetes"
                            appliedFor = ["PULL_THROUGH_CACHE"]
                            resourceTags = {}
                        }
                        providerConfigRef = {
                            name = "aws-prod"
                            kind = "ProviderConfig"
                        }
                    }
                }
            ]
        }
    }

    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "mirror-renders-cronjob-and-read-rbac"
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
                    mirror = {
                        enabled = True
                        podIdentity = {
                            enabled = False
                        }
                        repositories = [
                            {
                                source = "xpkg.crossplane.io/crossplane-contrib/provider-aws-ecr:v2.5.0"
                            }
                        ]
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-mirror-sa"
                    spec.providerConfigRef = {
                        name = "platform-cluster"
                        kind = "ProviderConfig"
                    }
                    spec.forProvider.manifest = {
                        apiVersion = "v1"
                        kind = "ServiceAccount"
                        metadata = {
                            name = "platform-mirror"
                            namespace = "crossplane-system"
                        }
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-mirror-role"
                    spec.forProvider.manifest = {
                        apiVersion = "rbac.authorization.k8s.io/v1"
                        kind = "ClusterRole"
                        rules = [
                            {
                                apiGroups = ["pkg.crossplane.io"]
                                resources = ["providers", "functions", "configurations"]
                                verbs = ["get", "list", "watch"]
                            }
                        ]
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-mirror-cronjob"
                    spec.forProvider.manifest = {
                        apiVersion = "batch/v1"
                        kind = "CronJob"
                        metadata = {
                            name = "platform-mirror"
                            namespace = "crossplane-system"
                        }
                        spec = {
                            schedule = "0 */6 * * *"
                            concurrencyPolicy = "Forbid"
                            jobTemplate.spec.template.spec = {
                                serviceAccountName = "platform-mirror"
                                containers = [
                                    {
                                        name = "mirror"
                                        image = "ghcr.io/hops-ops/registry-cache-mirror:latest"
                                    }
                                ]
                            }
                        }
                    }
                }
            ]
        }
    }

    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "mirror-config-includes-explicit-repositories"
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
                    mirror = {
                        enabled = True
                        podIdentity = {
                            enabled = False
                        }
                        repositories = [
                            {
                                source = "xpkg.crossplane.io/crossplane-contrib/provider-aws-ecr:v2.5.0"
                                tags = {
                                    allow = ["^v2\\."]
                                    deny = [".*-rc\\..*"]
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
                    metadata.name = "platform-mirror-config"
                    spec.forProvider.manifest = {
                        apiVersion = "v1"
                        kind = "ConfigMap"
                        metadata = {
                            name = "platform-mirror"
                            namespace = "crossplane-system"
                        }
                        data = {
                            "mirror-config.json" = "{\"accountId\":\"123456789012\",\"discovery\":{\"crossplanePackages\":{\"enabled\":true,\"mode\":\"repository\",\"namespaces\":[],\"registries\":[\"xpkg.crossplane.io\",\"xpkg.upbound.io\"]}},\"region\":\"us-east-2\",\"regsync\":{\"interval\":\"6h\",\"logLevel\":\"INFO\",\"missingOnly\":true,\"parallel\":2},\"repositories\":[{\"source\":\"xpkg.crossplane.io/crossplane-contrib/provider-aws-ecr:v2.5.0\",\"tags\":{\"allow\":[\"^v2\\\\.\"],\"deny\":[\".*-rc\\\\..*\"],\"mode\":\"all\"}}],\"tags\":{\"allow\":[\"^v.*\"],\"mode\":\"filtered\"},\"target\":{\"prefixes\":{\"xpkg.crossplane.io\":\"xpkg-crossplane\",\"xpkg.upbound.io\":\"xpkg-upbound\"},\"registry\":\"123456789012.dkr.ecr.us-east-2.amazonaws.com\"},\"tool\":\"regsync\"}"
                        }
                    }
                }
            ]
        }
    }

    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "mirror-lifecycle-renders-create-on-push-templates"
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
                    mirror = {
                        enabled = True
                        podIdentity = {
                            enabled = False
                        }
                        lifecyclePolicy = {
                            enabled = True
                            untaggedExpireAfterDays = 2
                        }
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "ecr.aws.m.upbound.io/v1beta1"
                    kind = "RepositoryCreationTemplate"
                    metadata.name = "platform-mirror-xpkg-crossplane"
                    spec = {
                        managementPolicies = ["*"]
                        forProvider = {
                            region = "us-east-2"
                            prefix = "xpkg-crossplane"
                            appliedFor = ["CREATE_ON_PUSH"]
                            description = "Mirror repositories for xpkg.crossplane.io"
                            lifecyclePolicy = "{\"rules\":[{\"action\":{\"type\":\"expire\"},\"description\":\"Expire untagged images after 2 day(s)\",\"rulePriority\":1,\"selection\":{\"countNumber\":2,\"countType\":\"sinceImagePushed\",\"countUnit\":\"days\",\"tagStatus\":\"untagged\"}}]}"
                        }
                    }
                }
                {
                    apiVersion = "ecr.aws.m.upbound.io/v1beta1"
                    kind = "RepositoryCreationTemplate"
                    metadata.name = "platform-mirror-xpkg-upbound"
                    spec.forProvider = {
                        region = "us-east-2"
                        prefix = "xpkg-upbound"
                        appliedFor = ["CREATE_ON_PUSH"]
                    }
                }
                {
                    apiVersion = "kubernetes.m.crossplane.io/v1alpha1"
                    kind = "Object"
                    metadata.name = "platform-mirror-config"
                    spec.forProvider.manifest.data = {
                        "mirror-config.json" = "{\"accountId\":\"123456789012\",\"discovery\":{\"crossplanePackages\":{\"enabled\":true,\"mode\":\"repository\",\"namespaces\":[],\"registries\":[\"xpkg.crossplane.io\",\"xpkg.upbound.io\"]}},\"region\":\"us-east-2\",\"regsync\":{\"interval\":\"6h\",\"logLevel\":\"INFO\",\"missingOnly\":true,\"parallel\":2},\"repositories\":[],\"repositoryCreation\":{\"createRepositories\":false,\"mode\":\"create-on-push\"},\"tags\":{\"allow\":[\"^v.*\"],\"mode\":\"filtered\"},\"target\":{\"prefixes\":{\"xpkg.crossplane.io\":\"xpkg-crossplane\",\"xpkg.upbound.io\":\"xpkg-upbound\"},\"registry\":\"123456789012.dkr.ecr.us-east-2.amazonaws.com\"},\"tool\":\"regsync\"}"
                    }
                }
            ]
        }
    }

    {
        apiVersion = "meta.dev.upbound.io/v1alpha1"
        kind = "CompositionTest"
        metadata.name = "pod-identity-enabled-by-default"
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
                    mirror = {
                        enabled = True
                    }
                }
            }
            assertResources = [
                {
                    apiVersion = "aws.hops.ops.com.ai/v1alpha1"
                    kind = "PodIdentity"
                    metadata.name = "platform-mirror"
                    spec = {
                        region = "us-east-2"
                        clusterName = "platform-cluster"
                        serviceAccount = {
                            name = "platform-mirror"
                            namespace = "crossplane-system"
                        }
                    }
                }
            ]
        }
    }
]

items = _items

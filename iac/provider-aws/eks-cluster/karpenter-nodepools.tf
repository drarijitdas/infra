# --- Computed pool maps ---
# When no explicit pools are configured, create a single default pool from the legacy variables.
locals {
  effective_client_pools = length(var.client_pools) > 0 ? var.client_pools : {
    client = {
      instance_types      = var.client_instance_types
      capacity_types      = var.client_capacity_types
      cpu_limit           = var.client_nodepool_cpu_limit
      memory_limit        = var.client_nodepool_memory_limit
      consolidation_after = var.client_consolidation_after
    }
  }

  effective_build_pools = length(var.build_pools) > 0 ? var.build_pools : {
    build = {
      instance_types      = var.build_instance_types
      capacity_types      = ["spot", "on-demand"]
      cpu_limit           = var.build_nodepool_cpu_limit
      memory_limit        = var.build_nodepool_memory_limit
      consolidation_after = var.build_consolidation_after
    }
  }
}

# --- EC2NodeClass for Firecracker-capable nodes ---
resource "kubectl_manifest" "ec2nodeclass_c8i_firecracker" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.k8s.aws/v1"
    kind       = "EC2NodeClass"
    metadata = {
      name = "c8i-firecracker"
    }
    spec = {
      role = module.karpenter.node_iam_role_name

      amiSelectorTerms = [
        {
          id = var.eks_ami_id
        }
      ]

      subnetSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      securityGroupSelectorTerms = [
        {
          tags = {
            "karpenter.sh/discovery" = var.cluster_name
          }
        }
      ]

      blockDeviceMappings = [
        {
          deviceName = "/dev/xvda"
          ebs = {
            volumeSize          = "${var.boot_disk_size_gb}Gi"
            volumeType          = "gp3"
            deleteOnTermination = true
            encrypted           = true
          }
        },
        {
          deviceName = "/dev/xvdb"
          ebs = {
            volumeSize          = "${var.cache_disk_size_gb}Gi"
            volumeType          = "gp3"
            iops                = var.cache_disk_iops
            throughput          = var.cache_disk_throughput_mbps
            deleteOnTermination = true
            encrypted           = true
          }
        }
      ]

      userData = templatefile("${path.module}/templates/node-userdata.sh", {
        EFS_DNS_NAME         = var.efs_dns_name
        EFS_MOUNT_PATH       = var.efs_mount_path
        CACHE_DISK_DEVICE    = "/dev/xvdb"
        CACHE_MOUNT_PATH     = "/mnt/cache"
        HUGEPAGES_PERCENTAGE = var.client_hugepages_percentage
      })

      tags = merge(var.tags, {
        "karpenter.sh/discovery" = var.cluster_name
      })
    }
  })

  depends_on = [helm_release.karpenter]
}

# --- Client NodePools (orchestrator workloads) ---
resource "kubectl_manifest" "nodepool_client" {
  for_each = local.effective_client_pools

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = each.key
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "e2b.dev/node-pool" = "client"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "c8i-firecracker"
          }
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = each.value.capacity_types
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = each.value.instance_types
            }
          ]
          taints = [
            {
              key    = "e2b.dev/node-pool"
              value  = "client"
              effect = "NoSchedule"
            }
          ]
          topologySpreadConstraints = [
            {
              maxSkew           = 1
              topologyKey       = "topology.kubernetes.io/zone"
              whenUnsatisfiable = "ScheduleAnyway"
            }
          ]
        }
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = each.value.consolidation_after
      }
      limits = {
        cpu    = each.value.cpu_limit
        memory = each.value.memory_limit
      }
    }
  })

  depends_on = [kubectl_manifest.ec2nodeclass_c8i_firecracker]
}

# --- Build NodePools (template-manager workloads, scale-to-zero) ---
resource "kubectl_manifest" "nodepool_build" {
  for_each = local.effective_build_pools

  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = each.key
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "e2b.dev/node-pool" = "build"
          }
        }
        spec = {
          nodeClassRef = {
            group = "karpenter.k8s.aws"
            kind  = "EC2NodeClass"
            name  = "c8i-firecracker"
          }
          requirements = [
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = each.value.capacity_types
            },
            {
              key      = "node.kubernetes.io/instance-type"
              operator = "In"
              values   = each.value.instance_types
            }
          ]
          taints = [
            {
              key    = "e2b.dev/node-pool"
              value  = "build"
              effect = "NoSchedule"
            }
          ]
          topologySpreadConstraints = [
            {
              maxSkew           = 1
              topologyKey       = "topology.kubernetes.io/zone"
              whenUnsatisfiable = "ScheduleAnyway"
            }
          ]
        }
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = each.value.consolidation_after
      }
      limits = {
        cpu    = each.value.cpu_limit
        memory = each.value.memory_limit
      }
    }
  })

  depends_on = [kubectl_manifest.ec2nodeclass_c8i_firecracker]
}

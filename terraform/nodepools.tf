# ------------------------------------------------------------------------------
# Custom Spot NodePool for cost optimization
#
# EKS Auto Mode uses Karpenter under the hood. The built-in general-purpose
# pool is On-Demand only. This custom pool enables Spot instances for
# fault-tolerant workloads, saving 60-70% on compute costs.
#
# NodePool API:  karpenter.sh/v1 (same as self-managed Karpenter)
# NodeClass API: eks.amazonaws.com/v1 (Auto Mode specific)
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "spot_nodeclass" {
  yaml_body = yamlencode({
    apiVersion = "eks.amazonaws.com/v1"
    kind       = "NodeClass"
    metadata = {
      name = "spot-class"
    }
    spec = {
      role = module.eks.node_iam_role_name
      subnetSelectorTerms = [
        {
          tags = {
            "kubernetes.io/role/internal-elb" = "1"
          }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = {
            "aws:eks:cluster-name" = var.project_name
          }
        }
      ]
    }
  })

  depends_on = [module.eks]
}

resource "kubectl_manifest" "spot_nodepool" {
  yaml_body = yamlencode({
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "spot-compute"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            "workload-type" = "spot-eligible"
          }
        }
        spec = {
          nodeClassRef = {
            group = "eks.amazonaws.com"
            kind  = "NodeClass"
            name  = "spot-class"
          }
          requirements = [
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot"]
            },
            {
              key      = "eks.amazonaws.com/instance-category"
              operator = "In"
              values   = ["c", "m", "r"]
            },
            {
              key      = "eks.amazonaws.com/instance-generation"
              operator = "Gte"
              values   = ["5"]
            }
          ]
          expireAfter = "336h"
        }
      }
      disruption = {
        consolidationPolicy = "WhenEmptyOrUnderutilized"
        consolidateAfter    = "1m"
        budgets = [
          { nodes = "20%" }
        ]
      }
      weight = 80
    }
  })

  depends_on = [
    module.eks,
    kubectl_manifest.spot_nodeclass,
  ]
}

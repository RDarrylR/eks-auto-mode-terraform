# ------------------------------------------------------------------------------
# Load Balancer - Ingress API with EKS Auto Mode managed ALB controller
#
# EKS Auto Mode requires explicit IngressClassParams + IngressClass resources.
# The managed ALB controller supports Ingress API and Service annotations (NLB).
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "demo_namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = "demo"
    }
  })

  depends_on = [module.eks]
}

resource "kubectl_manifest" "ingress_class_params" {
  yaml_body = yamlencode({
    apiVersion = "eks.amazonaws.com/v1"
    kind       = "IngressClassParams"
    metadata = {
      name = "alb"
    }
    spec = {
      scheme = "internet-facing"
    }
  })

  depends_on = [module.eks]
}

resource "kubectl_manifest" "ingress_class" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "IngressClass"
    metadata = {
      name = "alb"
      annotations = {
        "ingressclass.kubernetes.io/is-default-class" = "true"
      }
    }
    spec = {
      controller = "eks.amazonaws.com/alb"
      parameters = {
        apiGroup = "eks.amazonaws.com"
        kind     = "IngressClassParams"
        name     = "alb"
      }
    }
  })

  depends_on = [kubectl_manifest.ingress_class_params]
}

resource "kubectl_manifest" "ingress" {
  yaml_body = yamlencode({
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    metadata = {
      name      = "demo-api"
      namespace = "demo"
      annotations = {
        "alb.ingress.kubernetes.io/scheme"           = "internet-facing"
        "alb.ingress.kubernetes.io/target-type"      = "ip"
        "alb.ingress.kubernetes.io/healthcheck-path" = "/health"
      }
    }
    spec = {
      ingressClassName = "alb"
      rules = [{
        http = {
          paths = [{
            path     = "/"
            pathType = "Prefix"
            backend = {
              service = {
                name = "demo-api"
                port = { number = 80 }
              }
            }
          }]
        }
      }]
    }
  })

  depends_on = [kubectl_manifest.ingress_class, kubectl_manifest.demo_namespace]
}

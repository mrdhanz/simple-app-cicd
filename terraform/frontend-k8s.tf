variable "namespace_name" {
  type        = string
}

variable "app_name" {
  type        = string
}

variable "docker_image" {
  type        = string
}

variable "public_port" {
  description = "The port to use for the service"
  type        = number
}

variable "build_number" {
  type        = string
}

variable "app_version" {
  type        = string
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "simple_app_fe" {
  metadata {
    name = var.namespace_name
  }
}

resource "kubernetes_deployment" "simple_app_fe" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.simple_app_fe.metadata[0].name
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = var.app_name
        version = var.app_version
      }
    }

    template {
      metadata {
        labels = {
          app = var.app_name
          build_number = var.build_number
          version = var.app_version
        }
      }

      spec {
        container {
          image = var.docker_image
          name  = var.app_name

          port {
            container_port = 80
          }

          resources {
            requests = {
              cpu    = "100m"  # Ensure to set a request value
              memory = "256Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler" "simple_app_fe" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.simple_app_fe.metadata[0].name
  }

  depends_on = [kubernetes_deployment.simple_app_fe]  # Ensure HPA waits for Deployment

  spec {
    max_replicas = 10
    min_replicas = 2

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.simple_app_fe.metadata[0].name
    }
  }
}

resource "kubernetes_service" "simple_app_fe" {
  metadata {
    name      = "${var.app_name}-service"
    namespace = kubernetes_namespace.simple_app_fe.metadata[0].name
  }

  spec {
    selector = {
      app = var.app_name
      version = var.app_version
    }

    port {
      port        = var.public_port
      target_port = 80
    }

    type = "LoadBalancer"
  }
}
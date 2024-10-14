variable "namespace_name" {
    description = "Namespace for the Kubernetes resources"
    type        = string
}

variable "app_name" {
    description = "The name of the application"
    type        = string
}

variable "docker_image" {
    description = "The Docker image to use for the service"
    type        = string
}

variable "build_number" {
    description = "The build number of the application"
    type        = string
}

variable "app_version" {
    description = "The version of the application"
    type        = string
}

provider "kubernetes" {
    config_path = "~/.kube/config"    
}

resource "kubernetes_namespace" "backend" {
  metadata {
    name = var.namespace_name
  }
}

resource "kubernetes_deployment" "backend" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.backend.metadata[0].name
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

resource "kubernetes_horizontal_pod_autoscaler" "backend" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.backend.metadata[0].name
  }

  depends_on = [kubernetes_deployment.backend]  # Ensure HPA waits for Deployment

  spec {
    max_replicas = 10
    min_replicas = 2

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.backend.metadata[0].name
    }
  }
}
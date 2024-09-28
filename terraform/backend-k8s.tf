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

provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_namespace" "simple_app_be" {
  metadata {
    name = var.namespace_name
  }
}

resource "kubernetes_deployment" "simple_app_be" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.simple_app_be.metadata[0].name
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = var.app_name
      }
    }

    template {
      metadata {
        labels = {
          app = var.app_name
          build_number = var.build_number
        }
      }

      spec {
        container {
          image = var.docker_image
          name  = var.app_name

          port {
            container_port = 3132
          }
        }
      }
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler" "simple_app_be" {
  metadata {
    name      = var.app_name
    namespace = kubernetes_namespace.simple_app_be.metadata[0].name
  }

  spec {
    max_replicas = 10
    min_replicas = 2

    scale_target_ref {
      kind = "Deployment"
      name = kubernetes_deployment.simple_app_be.metadata[0].name
    }
  }
}

resource "kubernetes_service" "simple_app_be" {
  metadata {
    name      = "${var.app_name}-service"
    namespace = kubernetes_namespace.simple_app_be.metadata[0].name
  }

  spec {
    selector = {
      app = var.app_name
    }

    port {
      port        = var.public_port
      target_port = 3132
    }

    type = "LoadBalancer"
  }
}
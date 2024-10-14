variable "namespace_name" {
    description = "Namespace for the Kubernetes resources"
    type        = string
}

variable "service_name" {
    description = "The service name of the application"
    type        = string
}

variable "app_version" {
    description = "The version of the application"
    type        = string
    default = "blue"
}

variable "public_port" {
    description = "The port to use for the service"
    type        = number
}

provider "kubernetes" {
    config_path = "~/.kube/config"    
}

resource "kubernetes_service" "backend" {
  metadata {
    name      = var.service_name
    namespace = var.namespace_name
  }

  spec {
    selector = {
      app = var.app_name
      version = var.app_version
    }

    port {
      port        = var.public_port
      target_port = 3132
    }

    type = "LoadBalancer"
  }
}
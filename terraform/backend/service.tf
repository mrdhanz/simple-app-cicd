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
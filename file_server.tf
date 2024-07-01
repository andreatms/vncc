terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

variable "host" {
  type = string
}

variable "client_certificate" {
  type = string
}

variable "client_key" {
  type = string
}

variable "cluster_ca_certificate" {
  type = string
}

provider "kubernetes" {
  config_path = "~/.kube/config"

  host = var.host

  client_certificate     = base64decode(var.client_certificate)
  client_key             = base64decode(var.client_key)
  cluster_ca_certificate = base64decode(var.cluster_ca_certificate)
}

resource "kubernetes_deployment" "file-server-deployment" {
  metadata {
    name = "file-server-deployment"
    labels = {
      App = "fileServer"
    }
  }

  spec {
    selector {
      match_labels = {
        App = "fileServer"
      }
    }

    template {
        metadata {
            labels = {
                App = "fileServer"
            }
        }
        spec {
            container {
                image = "andreatms/file-server:latest"
                name = "nginx"
            
                port {
                    container_port = 80
                }

                resources {
                  limits = {
                    cpu = "200m"
                    memory = "512Mi"
                  }
                  requests = {
                    cpu = "100m"
                    memory = "256Mi"
                  }
                }
            }
        }
    }
  }
}

resource "kubernetes_service" "file-server" {
  metadata {
    name = "file-server"
  }
  spec {
    selector = {
      App = kubernetes_deployment.file-server-deployment.spec.0.template.0.metadata[0].labels.App
    }
    port {
      port = 80
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler" "file-server-hpa" {
  metadata {
    name = "file-server-hpa"
  }
  spec {
    min_replicas = 1
    max_replicas = 5

    target_cpu_utilization_percentage = 50

    scale_target_ref {
      kind = "Deployment"
      name = kubernetes_deployment.file-server-deployment.metadata[0].name
      api_version = "apps/v1"
    }
  }
}

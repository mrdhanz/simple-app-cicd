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
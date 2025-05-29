variable "image_name" {
  description = "The name of the image to use for the instance"
  type        = string
}

variable "flavor_name" {
  description = "The flavor of the instance"
  type        = string
}

variable "network_name" {
  description = "The network to attach to the instance"
  type        = string
}
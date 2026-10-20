variable "docker_image" {
    default = "AlmaLinux 9 (docker)"
}
variable "os_image" {
    default = "AlmaLinux 9"
}
variable "ssh_key_name" {
    default = "bootstrap"
}
variable "ssh_user_name" {
    default = "almalinux"
}
variable "chef_version" {
    default = "18"
}
variable "network" {
    default = "backend"
}
variable "region2" {
    default = "0"
}
variable "computes" {
    type    = number
    default = 1
    validation {
        condition     = var.computes >= 0 && var.computes <= 3
        error_message = "computes is 0 to 3 (compute, compute2, compute3)."
    }
}

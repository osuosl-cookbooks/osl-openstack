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

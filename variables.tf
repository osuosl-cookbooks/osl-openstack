variable "centos_atomic_image" {
    default = "CentOS Atomic 7.1902"
}
variable "os_image" {
    default = "AlmaLinux 8"
}
variable "ssh_key_name" {
    default = "bootstrap"
}
variable "ssh_user_name" {
    default = "almalinux"
}
variable "network" {
    default = "backend"
}
variable "chef_version" {
    default = "17"
}

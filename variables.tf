variable "centos_atomic_image" {
    default = "CentOS Atomic 7.1902"
}
variable "os_image" {
    default = "CentOS 7.9"
}
variable "ssh_key_name" {
    default = "bootstrap"
}
variable "ssh_user_name" {
    default = "centos"
}
variable "network" {
    default = "backend"
}
variable "chef_version" {
    default = "17"
}

variable "centos_atomic_image" {
    default = "CentOS Atomic 7.1902"
}
variable "centos_image" {
    default = "CentOS 7.9"
}
variable "ssh_key_name" {
    default = "bootstrap"
}
variable "ssh_user_name" {
    default = "centos"
}
variable "public_network" {
    default = "public2"
}
variable "public_subnet" {
    default = "public2"
}
variable "backend_network" {
    default = "vlan42"
}
variable "backend_subnet" {
    default = "vlan42"
}
variable "public_network_id" {
    default = "8dcba61e-5ef8-4e79-953a-ea67a66f32e6"
}
variable "backend_network_id" {
    default = "44ba0b36-1c69-46ce-9993-97e36dbd4ede"
}

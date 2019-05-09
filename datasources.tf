data "openstack_networking_network_v2" "public_network" {
    name = "${var.public_network}"
}
data "openstack_networking_network_v2" "backend_network" {
    name = "${var.backend_network}"
}

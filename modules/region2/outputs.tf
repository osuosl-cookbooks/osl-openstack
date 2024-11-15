output "database_region2" {
    value = "${openstack_compute_instance_v2.database_region2.network.0.fixed_ip_v4}"
}
output "controller_region2" {
    value = "${openstack_compute_instance_v2.controller_region2.network.0.fixed_ip_v4}"
}
output "compute_region2" {
    value = "${openstack_compute_instance_v2.compute_region2.network.0.fixed_ip_v4}"
}

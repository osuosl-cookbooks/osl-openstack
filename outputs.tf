output "chef_zero" {
    value = "${openstack_compute_instance_v2.chef_zero.network.0.fixed_ip_v4}"
}
output "database" {
    value = "${openstack_compute_instance_v2.database.network.0.fixed_ip_v4}"
}
output "database_region2" {
    value = length(module.region2) > 0 ? module.region2[0].database_region2 : null
}
output "ceph" {
    value = "${openstack_compute_instance_v2.ceph.network.0.fixed_ip_v4}"
}
output "controller" {
    value = "${openstack_compute_instance_v2.controller.network.0.fixed_ip_v4}"
}
output "controller_region2" {
    value = length(module.region2) > 0 ? module.region2[0].controller_region2 : null
}
output "compute" {
    value = "${openstack_compute_instance_v2.compute.network.0.fixed_ip_v4}"
}
output "compute_region2" {
    value = length(module.region2) > 0 ? module.region2[0].compute_region2 : null
}

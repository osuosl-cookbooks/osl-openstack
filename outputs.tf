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
output "controller1" {
    value = "${openstack_compute_instance_v2.controller1.network.0.fixed_ip_v4}"
}
output "controller2" {
    value = "${openstack_compute_instance_v2.controller2.network.0.fixed_ip_v4}"
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
output "mq1" {
    value = "${openstack_compute_instance_v2.mq1.network.0.fixed_ip_v4}"
}
output "mq2" {
    value = "${openstack_compute_instance_v2.mq2.network.0.fixed_ip_v4}"
}
output "mq3" {
    value = "${openstack_compute_instance_v2.mq3.network.0.fixed_ip_v4}"
}

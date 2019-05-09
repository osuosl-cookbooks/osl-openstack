output "chef_zero" {
    value = "${openstack_compute_instance_v2.chef_zero.network.0.fixed_ip_v4}"
}
output "controller" {
    value = "${openstack_compute_instance_v2.controller.network.0.fixed_ip_v4}"
}
output "compute" {
    value = "${openstack_compute_instance_v2.compute.network.0.fixed_ip_v4}"
}

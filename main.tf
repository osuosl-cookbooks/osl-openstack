resource "openstack_networking_network_v2" "openstack_network" {
    name            = "openstack_network"
    admin_state_up  = "true"
}

resource "openstack_networking_subnet_v2" "openstack_subnet" {
    network_id      = "${openstack_networking_network_v2.openstack_network.id}"
    cidr            = "192.168.60.0/24"
    enable_dhcp     = "false"
    no_gateway      = "true"
}

resource "openstack_compute_instance_v2" "chef_zero" {
    name            = "chef-zero"
    image_name      = "${var.centos_atomic_image}"
    flavor_name     = "m1.small"
    key_pair        = "${var.ssh_key_name}"
    security_groups = ["default"]
    connection {
        user = "centos"
    }
    network {
        uuid = "${data.openstack_networking_network_v2.backend_network.id}"
    }
    provisioner "remote-exec" {
        inline = [
            "until [ -S /var/run/docker.sock ] ; do sleep 1 && echo 'docker not started...' ; done",
            "sudo docker run -d -p 8889:8889 --name chef-zero osuosl/chef-zero"
        ]
    }

    provisioner "local-exec" {
        command = "rake knife_upload"
        environment = {
            CHEF_SERVER = "${openstack_compute_instance_v2.chef_zero.network.0.fixed_ip_v4}"
        }
    }
}

resource "openstack_compute_instance_v2" "controller" {
    name            = "controller"
    image_name      = "${var.centos_image}"
    flavor_name     = "m1.large"
    key_pair        = "${var.ssh_key_name}"
    security_groups = ["default"]
    connection {
        user = "centos"
    }
    network {
        uuid = "${data.openstack_networking_network_v2.backend_network.id}"
    }
    network {
        name = "openstack_network"
    }
    provisioner "chef" {
        attributes_json = <<EOF
            {
                "ceph": {
                    "keyring": {
                        "mon": "/etc/ceph/$cluster.mon.keyring"
                    }
                }
            }
        EOF
        run_list        = [
            "role[ceph]",
            "role[ceph_mon]",
            "role[ceph_mgr]",
            "role[ceph_osd]",
            "role[ceph_setup]",
            "role[openstack_provisioning]",
            "recipe[osl-prometheus::server]",
            "recipe[osl-openstack::ops_database]",
            "recipe[osl-openstack::controller]",
            "role[openstack_cinder]",
            "recipe[openstack_test::orchestration]",
            "recipe[openstack_test::tempest]",
            "recipe[openstack_test::network]"
        ]
        node_name       = "controller"
        secret_key      = "${file("test/integration/encrypted_data_bag_secret")}"
        server_url      = "http://${openstack_compute_instance_v2.chef_zero.network.0.fixed_ip_v4}:8889"
        recreate_client = true
        user_name       = "fakeclient"
        user_key        = "${file("test/chef-config/fakeclient.pem")}"
        version         = "14"
    }
}

resource "openstack_compute_instance_v2" "compute" {
    name            = "compute"
    image_name      = "${var.centos_image}"
    flavor_name     = "m1.large"
    key_pair        = "${var.ssh_key_name}"
    security_groups = ["default"]
    connection {
        user = "centos"
    }
    network {
        uuid = "${data.openstack_networking_network_v2.backend_network.id}"
    }
    network {
        name = "openstack_network"
    }
    provisioner "chef" {
        run_list        = [
            "role[openstack_provisioning]",
            "role[ceph]",
            "recipe[openstack_test::ceph_compute]",
            "recipe[osl-openstack::compute]"
        ]
        node_name       = "compute"
        secret_key      = "${file("test/integration/encrypted_data_bag_secret")}"
        server_url      = "http://${openstack_compute_instance_v2.chef_zero.network.0.fixed_ip_v4}:8889"
        recreate_client = true
        user_name       = "fakeclient"
        user_key        = "${file("test/chef-config/fakeclient.pem")}"
        version         = "14"
    }

    # Run chef-client again
    provisioner "remote-exec" {
        inline = [
            "sudo chef-client"
        ]
        connection {
            user = "centos"
        }
    }

    depends_on = [ "openstack_compute_instance_v2.controller" ]
}

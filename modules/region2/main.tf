resource "openstack_networking_port_v2" "database_region2" {
    name            = "database_region2"
    admin_state_up  = true
    network_id      = var.network_id
}

resource "openstack_networking_port_v2" "controller_region2" {
    name            = "controller_region2"
    admin_state_up  = true
    network_id      = var.network_id
}

resource "openstack_networking_port_v2" "compute_region2" {
    name            = "compute_region2"
    admin_state_up  = true
    network_id      = var.network_id
}

resource "openstack_networking_port_v2" "database_region2_openstack" {
    name                  = "database_region2_openstack"
    admin_state_up        = true
    port_security_enabled = false
    network_id            = var.openstack_network_id
    fixed_ip {
        subnet_id = var.subnet_id
        ip_address = "10.1.2.101"
    }
}

resource "openstack_networking_port_v2" "controller_region2_openstack" {
    name                  = "controller_region2_openstack"
    admin_state_up        = true
    port_security_enabled = false
    network_id            = var.openstack_network_id
    fixed_ip {
        subnet_id = var.subnet_id
        ip_address = "10.1.2.103"
    }
}

resource "openstack_networking_port_v2" "compute_region2_openstack" {
    name                  = "compute_region2_openstack"
    admin_state_up        = true
    port_security_enabled = false
    network_id            = var.openstack_network_id
    fixed_ip {
        subnet_id = var.subnet_id
        ip_address = "10.1.2.104"
    }
}

resource "openstack_compute_instance_v2" "database_region2" {
    name            = "database_region2"
    image_name      = var.os_image
    flavor_name     = "m1.large"
    key_pair        = var.ssh_key_name
    security_groups = ["default"]
    connection {
        user = var.ssh_user_name
        host = openstack_networking_port_v2.database_region2.all_fixed_ips.0
    }
    network {
        port = openstack_networking_port_v2.database_region2.id
    }
    network {
        port = openstack_networking_port_v2.database_region2_openstack.id
    }
    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /etc/cinc",
            "sudo ln -sf /etc/cinc /etc/chef"
        ]
    }
}

resource "openstack_compute_instance_v2" "controller_region2" {
    name            = "controller_region2"
    image_name      = var.os_image
    flavor_name     = "m1.xlarge"
    key_pair        = var.ssh_key_name
    security_groups = ["default"]
    connection {
        user = var.ssh_user_name
        host = openstack_networking_port_v2.controller_region2.all_fixed_ips.0
    }
    network {
        port = openstack_networking_port_v2.controller_region2.id
    }
    network {
        port = openstack_networking_port_v2.controller_region2_openstack.id
    }
    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /etc/cinc",
            "sudo ln -sf /etc/cinc /etc/chef"
        ]
    }
}

resource "openstack_compute_instance_v2" "compute_region2" {
    name            = "compute_region2"
    image_name      = var.os_image
    flavor_name     = "m1.large"
    key_pair        = var.ssh_key_name
    security_groups = ["default"]
    connection {
        user = var.ssh_user_name
        host = openstack_networking_port_v2.compute_region2.all_fixed_ips.0
    }
    network {
        port = openstack_networking_port_v2.compute_region2.id
    }
    network {
        port = openstack_networking_port_v2.compute_region2_openstack.id
    }
    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /etc/cinc",
            "sudo ln -sf /etc/cinc /etc/chef"
        ]
    }
}

resource "null_resource" "database_region2" {
    provisioner "local-exec" {
        command = <<-EOF
            knife bootstrap -c test/chef-config/knife.rb \
                ${var.ssh_user_name}@${openstack_compute_instance_v2.database_region2.network.0.fixed_ip_v4} \
                --bootstrap-version ${var.chef_version} -y -N database_region2 --sudo \
                -r 'role[openstack_tf_region2],recipe[osl-openstack::ops_database]'
            EOF
        environment = {
            CHEF_SERVER = "${var.chef_zero_ip}"
        }
    }
    depends_on = [
        var.chef_zero_id,
        openstack_compute_instance_v2.database_region2,
    ]
}

resource "null_resource" "controller_region2" {
    connection {
        type = "ssh"
        user = var.ssh_user_name
        host = openstack_compute_instance_v2.controller_region2.network.0.fixed_ip_v4
    }

    provisioner "local-exec" {
        command = <<-EOF
            knife bootstrap -c test/chef-config/knife.rb \
                ${var.ssh_user_name}@${openstack_compute_instance_v2.controller_region2.network.0.fixed_ip_v4} \
                --bootstrap-version ${var.chef_version} -y -N controller_region2 --sudo \
                -r 'role[openstack_tf_common_region2],recipe[osl-openstack::ops_messaging],role[openstack_controller_region2],recipe[openstack_test::image_upload]'
            EOF
        environment = {
            CHEF_SERVER = "${var.chef_zero_ip}"
        }
    }

    provisioner "remote-exec" {
        inline = [
            "sudo cinc-client",
        ]
    }

    depends_on = [
        openstack_compute_instance_v2.controller_region2,
        null_resource.database_region2,
    ]
}

resource "null_resource" "compute_region2" {
    connection {
        type = "ssh"
        user = var.ssh_user_name
        host = openstack_compute_instance_v2.compute_region2.network.0.fixed_ip_v4
    }

    provisioner "local-exec" {
        command = <<-EOF
            knife bootstrap -c test/chef-config/knife.rb \
                ${var.ssh_user_name}@${openstack_compute_instance_v2.compute_region2.network.0.fixed_ip_v4} \
                --bootstrap-version ${var.chef_version} -y -N compute_region2 --sudo \
                -r 'role[openstack_tf_common_region2],recipe[osl-openstack::compute]'
            EOF
        environment = {
            CHEF_SERVER = "${var.chef_zero_ip}"
        }
    }

    provisioner "remote-exec" {
        inline = [
            "sudo cinc-client",
        ]
    }

    depends_on = [
        openstack_compute_instance_v2.compute_region2,
        null_resource.controller_region2,
    ]
}

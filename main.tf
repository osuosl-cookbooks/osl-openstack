resource "openstack_networking_network_v2" "openstack_network" {
    name            = "openstack_network"
    admin_state_up  = "true"
}

resource "openstack_networking_subnet_v2" "openstack_subnet" {
    network_id      = openstack_networking_network_v2.openstack_network.id
    cidr            = "10.1.2.0/23"
    enable_dhcp     = "false"
    no_gateway      = "true"
}

resource "openstack_networking_port_v2" "chef_zero" {
    name            = "chef_zero"
    admin_state_up  = true
    network_id      = data.openstack_networking_network_v2.network.id
}

resource "openstack_compute_instance_v2" "chef_zero" {
    name            = "chef-zero"
    image_name      = var.centos_atomic_image
    flavor_name     = "m1.small"
    key_pair        = var.ssh_key_name
    security_groups = ["default"]
    connection {
        user = "centos"
        host = openstack_networking_port_v2.chef_zero.all_fixed_ips.0
    }
    network {
        port = openstack_networking_port_v2.chef_zero.id
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

resource "openstack_networking_port_v2" "database" {
    name            = "database"
    admin_state_up  = true
    network_id      = data.openstack_networking_network_v2.network.id
}

resource "openstack_networking_port_v2" "ceph" {
    name            = "ceph"
    admin_state_up  = true
    network_id      = data.openstack_networking_network_v2.network.id
}

resource "openstack_networking_port_v2" "controller" {
    name            = "controller"
    admin_state_up  = true
    network_id      = data.openstack_networking_network_v2.network.id
}

resource "openstack_networking_port_v2" "compute" {
    name            = "compute"
    admin_state_up  = true
    network_id      = data.openstack_networking_network_v2.network.id
}

resource "openstack_networking_port_v2" "database_openstack" {
    name                  = "database_openstack"
    admin_state_up        = true
    port_security_enabled = false
    network_id            = openstack_networking_network_v2.openstack_network.id
    fixed_ip {
        subnet_id = openstack_networking_subnet_v2.openstack_subnet.id
        ip_address = "10.1.2.1"
    }
}

resource "openstack_networking_port_v2" "ceph_openstack" {
    name                  = "ceph_openstack"
    admin_state_up        = true
    port_security_enabled = false
    network_id            = openstack_networking_network_v2.openstack_network.id
    fixed_ip {
        subnet_id = openstack_networking_subnet_v2.openstack_subnet.id
        ip_address = "10.1.2.2"
    }
}

resource "openstack_networking_port_v2" "controller_openstack" {
    name                  = "controller_openstack"
    admin_state_up        = true
    port_security_enabled = false
    network_id            = openstack_networking_network_v2.openstack_network.id
    fixed_ip {
        subnet_id = openstack_networking_subnet_v2.openstack_subnet.id
        ip_address = "10.1.2.3"
    }
}

resource "openstack_networking_port_v2" "compute_openstack" {
    name                  = "compute_openstack"
    admin_state_up        = true
    port_security_enabled = false
    network_id            = openstack_networking_network_v2.openstack_network.id
    fixed_ip {
        subnet_id = openstack_networking_subnet_v2.openstack_subnet.id
        ip_address = "10.1.2.4"
    }
}

resource "openstack_compute_instance_v2" "database" {
    name            = "database"
    image_name      = var.os_image
    flavor_name     = "m1.large"
    key_pair        = var.ssh_key_name
    security_groups = ["default"]
    connection {
        user = var.ssh_user_name
        host = openstack_networking_port_v2.database.all_fixed_ips.0
    }
    network {
        port = openstack_networking_port_v2.database.id
    }
    network {
        port = openstack_networking_port_v2.database_openstack.id
    }
    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /etc/cinc",
            "sudo ln -sf /etc/cinc /etc/chef"
        ]
    }
}

resource "openstack_compute_instance_v2" "ceph" {
    name            = "ceph"
    image_name      = "AlmaLinux 8"
    flavor_name     = "m1.large"
    key_pair        = var.ssh_key_name
    security_groups = ["default"]
    connection {
        user = "almalinux"
        host = openstack_networking_port_v2.ceph.all_fixed_ips.0
    }
    network {
        port = openstack_networking_port_v2.ceph.id
    }
    network {
        port = openstack_networking_port_v2.ceph_openstack.id
    }
}

resource "openstack_compute_instance_v2" "controller" {
    name            = "controller"
    image_name      = var.os_image
    flavor_name     = "m1.xlarge"
    key_pair        = var.ssh_key_name
    security_groups = ["default"]
    connection {
        user = var.ssh_user_name
        host = openstack_networking_port_v2.controller.all_fixed_ips.0
    }
    network {
        port = openstack_networking_port_v2.controller.id
    }
    network {
        port = openstack_networking_port_v2.controller_openstack.id
    }
    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /etc/cinc",
            "sudo ln -sf /etc/cinc /etc/chef"
        ]
    }
}

resource "openstack_compute_instance_v2" "compute" {
    name            = "compute"
    image_name      = var.os_image
    flavor_name     = "m1.large"
    key_pair        = var.ssh_key_name
    security_groups = ["default"]
    connection {
        user = var.ssh_user_name
        host = openstack_networking_port_v2.compute.all_fixed_ips.0
    }
    network {
        port = openstack_networking_port_v2.compute.id
    }
    network {
        port = openstack_networking_port_v2.compute_openstack.id
    }
    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /etc/cinc",
            "sudo ln -sf /etc/cinc /etc/chef"
        ]
    }
}

resource "null_resource" "database" {
    provisioner "local-exec" {
        command = <<-EOF
            knife bootstrap -c test/chef-config/knife.rb \
                ${var.ssh_user_name}@${openstack_compute_instance_v2.database.network.0.fixed_ip_v4} \
                --bootstrap-version ${var.chef_version} -y -N database --sudo \
                -r 'role[openstack_tf],recipe[osl-openstack::ops_database]'
            EOF
        environment = {
            CHEF_SERVER = "${openstack_compute_instance_v2.chef_zero.network.0.fixed_ip_v4}"
        }
    }
    depends_on = [
        openstack_compute_instance_v2.chef_zero,
        openstack_compute_instance_v2.database,
    ]
}

resource "null_resource" "ceph" {
    provisioner "local-exec" {
        command = <<-EOF
            knife bootstrap -c test/chef-config/knife.rb \
                almalinux@${openstack_compute_instance_v2.ceph.network.0.fixed_ip_v4} \
                --bootstrap-version ${var.chef_version} -y -N ceph --sudo \
                -r 'recipe[openstack_test::ceph_tf]'
            EOF
        environment = {
            CHEF_SERVER = "${openstack_compute_instance_v2.chef_zero.network.0.fixed_ip_v4}"
        }
    }
    depends_on = [
        openstack_compute_instance_v2.chef_zero,
        openstack_compute_instance_v2.ceph,
    ]
}

resource "null_resource" "controller" {
    connection {
        type = "ssh"
        user = var.ssh_user_name
        host = openstack_compute_instance_v2.controller.network.0.fixed_ip_v4
    }

    provisioner "local-exec" {
        command = <<-EOF
            knife bootstrap -c test/chef-config/knife.rb \
                ${var.ssh_user_name}@${openstack_compute_instance_v2.controller.network.0.fixed_ip_v4} \
                --bootstrap-version ${var.chef_version} -y -N controller --sudo \
                -r 'role[openstack_tf_common],role[openstack_controller],recipe[openstack_test::prometheus],recipe[osl-openstack::ops_messaging],recipe[osl-openstack::controller],recipe[osl-openstack::block_storage],recipe[openstack_test::image_upload]'
            EOF
        environment = {
            CHEF_SERVER = "${openstack_compute_instance_v2.chef_zero.network.0.fixed_ip_v4}"
        }
    }

    provisioner "remote-exec" {
        inline = [
            "sudo cinc-client",
        ]
    }

    depends_on = [
        openstack_compute_instance_v2.controller,
        null_resource.database,
        null_resource.ceph,
    ]
}

resource "null_resource" "compute" {
    connection {
        type = "ssh"
        user = var.ssh_user_name
        host = openstack_compute_instance_v2.compute.network.0.fixed_ip_v4
    }

    provisioner "local-exec" {
        command = <<-EOF
            knife bootstrap -c test/chef-config/knife.rb \
                ${var.ssh_user_name}@${openstack_compute_instance_v2.compute.network.0.fixed_ip_v4} \
                --bootstrap-version ${var.chef_version} -y -N compute --sudo \
                -r 'role[openstack_tf_common],recipe[osl-openstack::compute]'
            EOF
        environment = {
            CHEF_SERVER = "${openstack_compute_instance_v2.chef_zero.network.0.fixed_ip_v4}"
        }
    }

    provisioner "remote-exec" {
        inline = [
            "sudo cinc-client",
        ]
    }

    depends_on = [
        openstack_compute_instance_v2.compute,
        null_resource.controller,
    ]
}

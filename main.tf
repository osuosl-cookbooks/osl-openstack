module "region2" {
    chef_version = var.chef_version
    chef_zero_id = openstack_compute_instance_v2.chef_zero.id
    chef_zero_ip = openstack_compute_instance_v2.chef_zero.network.0.fixed_ip_v4
    count  = var.region2 ? 1: 0
    network_id = data.openstack_networking_network_v2.network.id
    openstack_network_id = openstack_networking_network_v2.openstack_network.id
    os_image = var.os_image
    source = "./modules/region2"
    ssh_key_name = var.ssh_key_name
    ssh_user_name = var.ssh_user_name
    subnet_id = openstack_networking_subnet_v2.openstack_subnet.id
}

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

resource "openstack_networking_subnet_v2" "openstack_subnet_v6" {
    network_id      = openstack_networking_network_v2.openstack_network.id
    cidr            = "fd00:1:2::/64"
    ip_version      = 6
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
    image_name      = var.docker_image
    flavor_name     = "m2.local.2c3m10d"
    key_pair        = var.ssh_key_name
    security_groups = ["default"]
    connection {
        user = var.ssh_user_name
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

# Re-upload cookbooks and data bags to chef-zero on every apply so that
# local recipe / data bag edits are picked up without recreating chef-zero.
resource "null_resource" "knife_upload" {
    triggers = {
        always_run = timestamp()
    }
    provisioner "local-exec" {
        command = "rake knife_upload"
        environment = {
            CHEF_SERVER = "${openstack_compute_instance_v2.chef_zero.network.0.fixed_ip_v4}"
        }
    }
    depends_on = [
        openstack_compute_instance_v2.chef_zero,
    ]
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

resource "openstack_networking_port_v2" "controller1" {
    name            = "controller1"
    admin_state_up  = true
    network_id      = data.openstack_networking_network_v2.network.id
}

resource "openstack_networking_port_v2" "controller2" {
    name            = "controller2"
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

resource "openstack_networking_port_v2" "controller1_openstack" {
    name                  = "controller1_openstack"
    admin_state_up        = true
    port_security_enabled = false
    network_id            = openstack_networking_network_v2.openstack_network.id
    fixed_ip {
        subnet_id = openstack_networking_subnet_v2.openstack_subnet.id
        ip_address = "10.1.2.3"
    }
    fixed_ip {
        subnet_id = openstack_networking_subnet_v2.openstack_subnet_v6.id
        ip_address = "fd00:1:2::3"
    }
}

resource "openstack_networking_port_v2" "controller2_openstack" {
    name                  = "controller2_openstack"
    admin_state_up        = true
    port_security_enabled = false
    network_id            = openstack_networking_network_v2.openstack_network.id
    fixed_ip {
        subnet_id = openstack_networking_subnet_v2.openstack_subnet.id
        ip_address = "10.1.2.13"
    }
    fixed_ip {
        subnet_id = openstack_networking_subnet_v2.openstack_subnet_v6.id
        ip_address = "fd00:1:2::13"
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
    flavor_name     = "m2.local.8c8m100d"
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
    flavor_name     = "m2.local.8c8m100d"
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

resource "openstack_compute_instance_v2" "controller1" {
    name            = "controller1"
    image_name      = var.os_image
    flavor_name     = "m2.local.16c16m200d"
    key_pair        = var.ssh_key_name
    security_groups = ["default"]
    connection {
        user = var.ssh_user_name
        host = openstack_networking_port_v2.controller1.all_fixed_ips.0
    }
    network {
        port = openstack_networking_port_v2.controller1.id
    }
    network {
        port = openstack_networking_port_v2.controller1_openstack.id
    }
    provisioner "remote-exec" {
        inline = [
            "sudo mkdir -p /etc/cinc",
            "sudo ln -sf /etc/cinc /etc/chef"
        ]
    }
}

resource "openstack_compute_instance_v2" "controller2" {
    name            = "controller2"
    image_name      = var.os_image
    flavor_name     = "m2.local.16c16m200d"
    key_pair        = var.ssh_key_name
    security_groups = ["default"]
    connection {
        user = var.ssh_user_name
        host = openstack_networking_port_v2.controller2.all_fixed_ips.0
    }
    network {
        port = openstack_networking_port_v2.controller2.id
    }
    network {
        port = openstack_networking_port_v2.controller2_openstack.id
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
    flavor_name     = "m2.local.8c8m100d"
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
    triggers = {
        instance_id = openstack_compute_instance_v2.database.id
    }
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
    triggers = {
        instance_id = openstack_compute_instance_v2.ceph.id
    }
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

resource "null_resource" "controller1" {
    triggers = {
        instance_id = openstack_compute_instance_v2.controller1.id
    }
    connection {
        type = "ssh"
        user = var.ssh_user_name
        host = openstack_compute_instance_v2.controller1.network.0.fixed_ip_v4
    }

    provisioner "local-exec" {
        command = <<-EOF
            knife bootstrap -c test/chef-config/knife.rb \
                ${var.ssh_user_name}@${openstack_compute_instance_v2.controller1.network.0.fixed_ip_v4} \
                --bootstrap-version ${var.chef_version} -y -N controller1 --sudo \
                -r 'role[openstack_tf_common],role[openstack_controller],recipe[openstack_test::prometheus],recipe[osl-openstack::ops_messaging],recipe[osl-openstack::controller],recipe[osl-openstack::block_storage],recipe[openstack_test::image_upload],recipe[openstack_test::create_network]'
            EOF
        environment = {
            CHEF_SERVER = "${openstack_compute_instance_v2.chef_zero.network.0.fixed_ip_v4}"
        }
    }

    provisioner "remote-exec" {
        inline = [
            "sudo cinc-client",
            "sudo /root/image_upload.sh",
            "sudo /root/create_flavor.sh",
            "sudo /root/create_network.sh",
        ]
    }

    depends_on = [
        openstack_compute_instance_v2.controller1,
        null_resource.database,
        null_resource.ceph,
    ]
}

resource "null_resource" "controller2" {
    triggers = {
        instance_id = openstack_compute_instance_v2.controller2.id
    }
    connection {
        type = "ssh"
        user = var.ssh_user_name
        host = openstack_compute_instance_v2.controller2.network.0.fixed_ip_v4
    }

    provisioner "local-exec" {
        command = <<-EOF
            knife bootstrap -c test/chef-config/knife.rb \
                ${var.ssh_user_name}@${openstack_compute_instance_v2.controller2.network.0.fixed_ip_v4} \
                --bootstrap-version ${var.chef_version} -y -N controller2 --sudo \
                -r 'role[openstack_tf_common],role[openstack_controller],recipe[osl-openstack::ops_messaging],recipe[osl-openstack::controller],recipe[osl-openstack::block_storage]'
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
        openstack_compute_instance_v2.controller2,
        null_resource.controller1,
    ]
}

resource "null_resource" "compute" {
    triggers = {
        instance_id = openstack_compute_instance_v2.compute.id
    }
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
        null_resource.controller1,
    ]
}

# osl-openstack Cookbook

OSL wrapper cookbook for upstream [openstack cookbooks](https://wiki.openstack.org/wiki/Chef). Also includes support for
ppc64le compute nodes.

## Supported Platforms

- OpenStack Ocata release
- CentOS 7

# Multi-host test integration

This cookbook utilizes [Chef Provisioning](https://github.com/chef/chef-provisioning) to test deploying various parts of
this cookbook in multiple nodes, similar to that in production.

## Prereqs

- ChefDK 2.5.3 or later
- Vagrant 2.0.2 or later
- Virtualbox (5.x or later is usually better)
- OpenStack cluster (optional)

### Openstack Provisioning

Ironically enough, you can run this suite on an already deployed OpenStack cluster, which might be easier. This uses the
[Chef Provisioning Fog provider](https://github.com/chef/chef-provisioning-fog) and requires a bit of extra setup:

``` console
$ chef gem install chef-provisioning-fog
```

Next you need to create a ``~/.fog`` file which contains the various bits of information (replace with your
credentials):

``` yaml
default:
    openstack_api_key: <OS_PASSWORD>
    openstack_auth_url: https://openstack.example.org:5000/v2.0/tokens
    openstack_tenant: admin
    openstack_username: admin
    private_key_path: /home/manatee/.ssh/id_rsa
    public_key_path: /home/manatee/.ssh/id_rsa.pub
```

Next you need to set the following environment variables:

``` bash
NODE_OS=        # UUID of CentOS 7 image
FLAVOR=         # UUID of flavor for m1.large
CHEF_DRIVER=fog:OpenStack

# Various OpenStack variables
OS_SSH_KEYPAIR=       # Name of ssh key on OpenStack to use
OS_NETWORK_UUID=      # UUID of the network you want the instances to use
```

## Initial Setup Steps

``` console
$ git clone https://github.com/osuosl-cookbooks/osl-openstack.git
$ cd osl-openstack
$ chef exec rake berks_vendor
```

## Supported Deployments

- Controller / Compute+Cinder
  - Controller node (DB, MQ, Neutron, public apis, web interface, etc)
  - Compute node (also includes Cinder volume service)
- Controller / Network / Compute+Cinder
  - Controller node (DB, MQ, public apis, web interface, etc)
  - Network node (Neutron)
  - Compute node (also includes Cinder volume service)

## Rake Deploy Commands

These commands will spin up various compute nodes.

``` bash
# Spin up Controller and Compute nodes
$ chef exec rake controller_compute
# Spin up only the controller node
$ chef exec rake controller
# Spin up only the compute node
$ chef exec rake compute

# To setup a cluster using a separate network node, please do the following instead
$ chef exec rake controller_network_compute
# Spin up only the controller node
$ chef exec rake controller_sep_net
# Spin up the network node
$ chef exec rake network
# Spin up only the compute node
$ chef exec rake compute_sep_net

```

## Access the nodes

### Vagrant+Virtualbox

``` bash
$ cd vms
# Controller
$ vagrant ssh controller
$ sudo su -
# Network (if deployed)
$ vagrant ssh network
$ sudo su -
# Compute
$ vagrant ssh compute
$ sudo su -
```

### OpenStack

``` bash
# Controller
$ openstack server show -c addresses -f value controller
140.211.168.X
$ ssh centos@140.211.168.X
# Network
$ openstack server show -c addresses -f value network
140.211.168.X
$ ssh centos@140.211.168.X
# Compute
$ openstack server show -c addresses -f value compute
140.211.168.X
$ ssh centos@140.211.168.X
```

## Cleanup

``` bash
# To remove all the nodes and start again, run the following rake command.
$ chef exec rake destroy_machines

# To refresh all the cookbooks, use the following command.
$ chef exec rake berks_vendor

# To cleanup everything, including the cookbooks and machines run the following command.
$ chef exec rake clean
```

## Contributing

1. Fork the repository on Github
2. Create a named feature branch (i.e. `add-new-recipe`)
3. Write you change
4. Write tests for your change (if applicable)
5. Run the tests, ensuring they all pass
6. Submit a Pull Request

## License and Authors

Author:: Oregon State University (<chef@osuosl.org>)

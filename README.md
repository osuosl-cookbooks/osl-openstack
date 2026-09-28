# osl-openstack Cookbook

Cookbook for deploying OpenStack at the OSUOSL

## Supported Platforms

- OpenStack Yoga release, as the OSL-built `osuosl-openstack-*` venv RPMs from
  [openstack-packaging](https://git.osuosl.org/rpms/openstack-packaging)
  (one venv per service under `/opt/openstack/<svc>`), via the `:osuosl`
  source of `osl_repos_openstack`
- AlmaLinux 9

The shared messaging tier (`ops_messaging`, `ops_coordination`) also runs on
AlmaLinux 10.

## ppc64le compute kernels

The compute recipe picks the KVM-capable kernel from the CPU:

- POWER10: the CentOS Kmods SIG 6.18 kernel via `osl_repos_centos_kmods`,
  because AlmaLinux's `kernel-kvm` (5.14) lacks the nested-v2 support needed to
  host KVM guests inside a PowerVM LPAR
- POWER9 bare metal: AlmaLinux's `kernel-kvm`

`kvm_hv` is only loaded when the running kernel ships it as a module, so the
first converge on a new host installs the KVM kernel and the module loads
after the reboot.

## WSGI services

The API services run as uWSGI systemd units shipped by their RPMs. The cookbook
renders each unit's ini from `templates/uwsgi.ini.erb`. Apache keeps the vhost
on the service port and proxies it to the unit's socket through
`mod_proxy_uwsgi`. A config change restarts the uWSGI unit, not Apache.

| Service       | Port | uWSGI unit                | ini                                  | Socket                          |
|---------------|------|---------------------------|--------------------------------------|---------------------------------|
| keystone      | 5000 | `keystone-uwsgi`          | `/etc/keystone/keystone-uwsgi.ini`   | `/run/keystone/uwsgi.sock`      |
| placement     | 8778 | `placement-uwsgi`         | `/etc/placement/placement-uwsgi.ini` | `/run/placement/uwsgi.sock`     |
| nova-api      | 8774 | `openstack-nova-api`      | `/etc/nova/nova-api-uwsgi.ini`       | `/run/nova/api-uwsgi.sock`      |
| nova-metadata | 8775 | `openstack-nova-metadata` | `/etc/nova/nova-metadata-uwsgi.ini`  | `/run/nova/metadata-uwsgi.sock` |
| cinder-api    | 8776 | `openstack-cinder-api`    | `/etc/cinder/cinder-api-uwsgi.ini`   | `/run/cinder/api-uwsgi.sock`    |

## Resources

Every service recipe starts with `osl_openstack_client` and registers itself in
keystone with `osl_openstack_service_user` and `osl_openstack_api`. The
lower-level keystone resources (`osl_openstack_user`, `_service`, `_endpoint`,
`_domain`, `_project`, `_role`) look an object up before creating it, so
re-running them against an existing cloud makes no API writes.

### osl_openstack_client

Adds the OSL OpenStack repository and installs `osuosl-openstack-cli`.

| Property   | Default | Description                                               |
|------------|---------|-----------------------------------------------------------|
| `firewall` | `false` | Also open the service's ports via `osl_firewall_openstack` |
| `openrc`   | `false` | Also write `/root/openrc` via `osl_openstack_openrc`      |

```ruby
osl_openstack_client 'image' do
  firewall true
  openrc true
end
```

### osl_openstack_service_user

Creates a user in the `default` domain and grants it `admin` on the `service`
project.

| Property    | Default       | Description         |
|-------------|---------------|---------------------|
| `user_name` | resource name | Keystone user name  |
| `password`  | (required)    | The user's password |

### osl_openstack_api

Creates a keystone service and its `admin`, `internal` and `public` endpoints,
named `<endpoint_name>-<interface>` in the run.

| Property        | Default       | Description                            |
|-----------------|---------------|----------------------------------------|
| `service_name`  | resource name | Keystone service name                  |
| `type`          | (required)    | Service type, e.g. `image`             |
| `endpoint_name` | (required)    | Endpoint name, e.g. `image`            |
| `url`           | (required)    | URL used for all three interfaces      |
| `region`        | (required)    | Region the endpoints are registered in |

```ruby
osl_openstack_api 'glance' do
  type 'image'
  endpoint_name 'image'
  url 'http://controller.example.org:9292'
  region 'RegionOne'
end
```

# Multi-host test integration

This cookbook utilizes [kitchen-terraform](https://github.com/newcontext-oss/kitchen-terraform) to test deploying
various parts of this cookbook in multiple nodes, similar to that in production.

## Prereqs

- Chef/Cinc Workstation
- Terraform
- kitchen-terraform
- OpenStack cluster

Ensure you have the following in your ``.bashrc`` (or similar):

``` bash
export TF_VAR_ssh_key_name="$OS_SSH_KEYPAIR"
```

## Supported Deployments

- Chef-zero node acting as a Chef Server
- Database node
- Ceph node
- Controller node (MQ, Neutron, public apis, web interface, etc)
- Compute node (also includes Cinder volume service)

## Testing

First, generate some keys for chef-zero and then simply run the following suite.

``` console
# Only need to run this once
$ chef exec rake create_key
$ KITCHEN_YAML=kitchen.multi-node.yml kitchen test multi-node
```

If you want to test multi-regions, you need to do the following instead:

``` console
$ export TF_VAR_region2=1
$ KITCHEN_YAML=kitchen.multi-node.yml kitchen test multi-node
```

Be patient as this will take a while to converge all of the nodes (approximately 40 minutes).

## Access the nodes

Unfortunately, kitchen-terraform doesn't support using ``kitchen console`` so you will need to log into the nodes
manually. To see what their IP addresses are, just run ``terraform output`` which will output all of the IPs.

``` bash
# You can run the following commands to login to each node
$ ssh almalinux@$(terraform output controller)
$ ssh almalinux@$(terraform output compute)
# If you're testing multi-regions
$ ssh almalinux@$(terraform output controller_region2)
$ ssh almalinux@$(terraform output compute_region2)

# Or you can look at the IPs for all for all of the nodes at once
$ terraform output
```

## Interacting with the chef-zero server

All of these nodes are configured using a Chef Server which is a container running chef-zero. You can interact with the
chef-zero server by doing the following:

``` bash
$ CHEF_SERVER="$(terraform output chef_zero)" knife node list -c test/chef-config/knife.rb
controller
compute
$ CHEF_SERVER="$(terraform output chef_zero)" knife node edit -c test/chef-config/knife.rb
```

In addition, on any node that has been deployed, you can re-run ``cinc-client`` like you normally would on a production
system. This should allow you to do development on your multi-node environment as needed. **Just make sure you include
the knife config otherwise you will be interacting with our production chef server!**

## Using Terraform directly

You do not need to use kitchen-terraform directly if you're just doing development. It's primarily useful for testing
the multi-node cluster using inspec. You can simply deploy the cluster using terraform directly by doing the following:

``` bash
# Sanity check
$ terraform plan
# Deploy the cluster
$ terraform apply
# Destroy the cluster
$ terraform destroy
```

## Cleanup

``` bash
# To remove all the nodes and start again, run the following test-kitchen command.
$ kitchen destroy multi-node

# To refresh all the cookbooks, use the following command.
$ CHEF_SERVER="$(terraform output chef_zero)" chef exec rake knife_upload
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

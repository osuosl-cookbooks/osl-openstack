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

## Package updates

Chef, not dnf-automatic, upgrades the `osuosl-openstack-*` RPMs:

- `osl_openstack_client` declares a `dnf_automatic_policy 'osl-openstack'`
  that excludes `osuosl-openstack-*` from base's dnf-automatic baseline, so
  the 10:10 timer leaves them alone.
- Each venv RPM is a `package` resource with `action :upgrade`, so a
  release published to the node's `openstack/<release>/` repo is installed
  on the next converge.
- On one controller per cloud, the db syncs run when a package's version
  differs from the one recorded in `/var/lib/osl-openstack/db-sync/<service>`,
  and the version is recorded after a successful sync. That controller is
  the `ha.keepalived.primary` one in the cloud's data bag item, or any
  controller the `ha` block doesn't list.
- Each service restarts at the end of the run that upgraded its package,
  after that run's syncs. Nothing orders controllers or computes against
  each other yet.

A config template change still triggers its service's db sync, on that same
controller.

## Release upgrades

The `release` key in a cloud's `openstack` data bag item names its target
OpenStack release (default `yoga`). Chef stages the next release on every
node and never moves a node across it; the move is one window per cloud,
driven from the jumphost:

- `osl_openstack_client` reads the installed release from the RPMs' markers,
  stages the target, and raises instead of downgrading or skipping a release.
- `/usr/local/sbin/openstack-node-upgrade` is each node's part of a window.
- `recipe[osl-openstack::upgrade_runner]` on the jumphost installs
  `openstack-upgrade <cloud> <phase>`, which sequences the window and its
  rollback.

[docs/RELEASE_UPGRADES.md](docs/RELEASE_UPGRADES.md) has the runbook, the
points of no return and the rollback.

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
| horizon       | 443  | `horizon-uwsgi`           | `/etc/horizon/horizon-uwsgi.ini`     | `/run/horizon/uwsgi.sock`       |

Horizon reads `/etc/horizon/local_settings.py` through a symlink in its venv. Apache
serves `/static` from `/var/www/horizon/static`, which `collectstatic` and
`compress` fill whenever the settings or the vhost change.

## Migrating a node from RDO

A node that still has RDO's OpenStack packages installed stops at
`osl_openstack_client`. By then the run has written the venv repo and dropped
`/root/migrate-venv.sh`. To migrate the node:

1. Run `cinc-client`. It fails at `ruby_block[rdo migration pending]`.
2. Run `/root/migrate-venv.sh`, which:
   - removes `/etc/cron.d/chef-client`;
   - saves `rpm -qa`, the user-installed package names, the service `/etc`
     dirs, and the enabled and active units under `/root/pre-venv-*`;
   - stops the OpenStack units and httpd, then archives the RDO logs in
     `/var/log/<svc>` to `/root/pre-venv-logs-*.tgz` (dnf deletes
     `keystone.log` with `openstack-keystone`);
   - swaps each RDO package for its `osuosl-openstack-*` replacement in one
     interactive `dnf --allowerasing shell` transaction, which also removes
     `python3-mod_wsgi`. If dnf is aborted, it starts the stopped units again;
   - removes the mod_wsgi module files Chef had enabled for httpd, and
     disables the vhosts still using it until `cinc-client` re-renders them
     for uWSGI;
   - removes, in a second interactive transaction, the RDO libraries that no
     installed package outside RDO still needs (listed in
     `/root/pre-venv-cleanup-*.txt`) and what they pulled in. RDO's
     network-scripts and Open vSwitch packages are marked user-installed and
     kept. Declining it leaves a working node.
3. Review both transactions and note the dnf history ids the script prints.
4. Run `cinc-client`. It renders the configs, starts the units, restores the
   cron file and deletes the script.
5. Compare the units with `/root/pre-venv-units-*.txt`. RDO's packages disable
   their units on removal, and only `cinc-client` enables them again.

Each run logs to `/root/migrate-venv-<timestamp>.log`, and its step markers
also go to journald (`journalctl -t migrate-venv`). The `.rpmsave` files the
swap leaves in `/etc` are listed in the log; `cinc-client` renders every one
of them again.

To roll back, run `dnf history undo` on the cleanup id, then on the swap id,
then `dnf mark install` the names in `/root/pre-venv-userinstalled-*.txt`
that are installed again (the script prints all three). The undo reinstalls
RDO's packages as dependencies, which `dnf autoremove` would remove. Then
move the node to an environment that pins the RDO release of this cookbook,
and run `cinc-client`.

After the swap, services log to journald, not `/var/log/<svc>/*.log`.
`osuosl-openstack-selinux` replaces `openstack-selinux` and labels
`/opt/openstack`, so each daemon runs in the same SELinux domain as under RDO.

## Resources

Every service recipe starts with `osl_openstack_client` and registers itself in
keystone with `osl_openstack_service_user` and `osl_openstack_api`. The
lower-level keystone resources (`osl_openstack_user`, `_service`, `_endpoint`,
`_domain`, `_project`, `_role`) look an object up before creating it, so
re-running them against an existing cloud makes no API writes.

### osl_openstack_client

Adds the OSL OpenStack repository, upgrades `osuosl-openstack-cli` and
`osuosl-openstack-selinux`, and excludes `osuosl-openstack-*` from
dnf-automatic. On a node still running RDO, it stops the run first (see
[Migrating a node from RDO](#migrating-a-node-from-rdo)).

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
- Jumphost running the release upgrade runner

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
# The upgrade runner (docs/RELEASE_UPGRADES.md has the rehearsal)
$ ssh almalinux@$(terraform output jumphost)
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

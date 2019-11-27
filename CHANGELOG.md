CHANGELOG
=========

This file is used to list changes made in each version of the
osl-openstack cookbook.

7.3.1 (2019-11-27)
------------------
- Increase max client settings for libvirtd

7.3.0 (2019-11-08)
------------------
- Switch to using systemd_service_drop_in resource

7.2.0 (2019-11-07)
------------------
- Remove and disable gnocchi

7.1.3 (2019-10-18)
------------------
- Switch to using upstream repo for ppc64le now that it exists

7.1.2 (2019-10-17)
------------------
- Fix nagios checks with cinder and neutron floating ips

7.1.1 (2019-10-14)
------------------
- Temporarily disable memcached for the metadata agent

7.1.0 (2019-10-07)
------------------
- Chef 14 fixes

7.0.3 (2019-07-01)
------------------
- Enable SSD enabled ceph pool for volumes

7.0.2 (2019-06-26)
------------------
- Allow access to controller memcached server from all servers in the cluster

7.0.1 (2019-06-11)
------------------
- Remove resources which restart httpd on every chef run

7.0.0 (2019-06-10)
------------------
- Queens Release

6.0.3 (2019-06-04)
------------------
- Remove zeromq exclude as it's no longer needed and causing issues

6.0.2 (2019-04-22)
------------------
- Add ceph client file for the gnocchi user

6.0.1 (2019-04-09)
------------------
- Fix metadata issues breaking berks upload

6.0.0 (2019-04-09)
------------------
- Pike release

5.0.3 (2019-04-02)
------------------
- Fix Nova compute filters so they work properly

5.0.2 (2018-12-31)
------------------
- Misc upgrade fixes encountered during x86 upgrade

5.0.1 (2018-12-26)
------------------
- Convert to using Inspec

5.0.0 (2018-12-18)
------------------
- Ocata Release

4.1.0 (2018-12-03)
------------------
- Fix deprecation warnings in Newton

4.0.0 (2018-11-09)
------------------
- Chef 13 fixes

3.2.15 (2018-08-30)
-------------------
- Uninstall newer version of fog-openstack which breaks upstream openstack cb

3.2.14 (2018-07-26)
-------------------
- Don't use upcoming newer osl-apache (yet)

3.2.13 (2018-07-11)
-------------------
- Remove base::ifconfig from default recipe

3.2.12 (2018-06-27)
-------------------
- Switch to using yum-kernel-osuosl::install on ppc64

3.2.11 (2018-06-27)
-------------------
- Install older version of cliff python package

3.2.10 (2018-06-19)
-------------------
- Fix duplicated resources for group[ceph]

3.2.9 (2018-06-14)
------------------
- Remove `check_availability` statement and other syntax fixes

3.2.8 (2018-06-04)
------------------
- Account for case sensitivity when loading KVM in x86 cluster

3.2.7 (2018-06-04)
------------------
- Initial support of nested KVM in x86 cluster

3.2.6 (2018-05-29)
------------------
- Remove glusterfs since we no longer use it

3.2.5 (2018-05-29)
------------------
- Newton repo removed from public mirrors so point back to vault mirror…

3.2.4 (2018-05-10)
------------------
- Update openstack-newton repo URI

3.2.3 (2018-05-07)
------------------
- Adjust CMA ratio down to 15 from 20

3.2.2 (2018-05-07)
------------------
- Increase CMA ratio on ppc64le nodes to 20%

3.2.1 (2018-04-27)
------------------
- Lock pip version to < 10.0.0

3.2.0 (2018-04-02)
------------------
- Ceph integration

3.1.7 (2018-03-07)
------------------
- Install 4.14 kernel and set kvm_cma_resv_ratio=10 on ppc64le

3.1.6 (2017-12-09)
------------------
- The default shutdown timeout is 300s (5m), lower to 120s (1.5m)

3.1.5 (2017-12-04)
------------------
- Increase block_device_allocate_retries from 60 (default) to 120

3.1.4 (2017-12-01)
------------------
- Install libguestfs-tools

3.1.3 (2017-11-08)
------------------
- Add 'nova-manage db online_data_migrations' to upgrade script

3.1.2 (2017-11-07)
------------------
- Don't restart this service when the config file updates

3.1.1 (2017-11-07)
------------------
- Safely shutdown and start instances on hypervisor reboots

3.1.0 (2017-10-16)
------------------
- Enable OpenStack Orchestration service (heat)

3.0.7 (2017-10-09)
------------------
- Disable volumes from instance launch window in Horizon

3.0.6 (2017-10-04)
------------------
- Switch to using our fork of osops-tools-monitoring

3.0.5 (2017-09-28)
------------------
- Set API version for check_nova_api

3.0.4 (2017-09-27)
------------------
- Nagios monitoring in Newton

3.0.3 (2017-09-27)
------------------
- Add AggregateInstanceExtraSpecsFilter to Nova Scheduler

3.0.2 (2017-09-26)
------------------
- Arcfour cipher has been completely removed

3.0.1 (2017-09-26)
------------------
- Increase DHCP lease from 120s to 10min

3.0.0 (2017-09-15)
------------------
- Newton Release

2.5.13 (2017-09-15)
-------------------
- Exclude python2-uritemplate python2-google-api-client from epel repo

2.5.12 (2017-09-15)
-------------------
- Update RDO baseurl for Mitaka release

2.5.11 (2017-09-04)
-------------------
- Remove ppc64 as we only use ppc64le currently

2.5.10 (2017-08-24)
-------------------
- Properly fix situations where the initial run has interfaces not setup

2.5.9 (2017-08-23)
------------------
- Add iptable rules to block external DNS traffic on public provider networks

2.5.8 (2017-08-14)
------------------
- Revert fixes

2.5.7 (2017-08-14)
------------------
- Remove semicolon so it works

2.5.6 (2017-08-14)
------------------
- Use correct syntax for nagios plugin

2.5.5 (2017-08-14)
------------------
- Include warn/crit disabled tuning on the nova-services nrpe check

2.5.4 (2017-08-14)
------------------
- Set the server_status_port to port 80 so that munin works

2.5.3 (2017-07-19)
------------------
- Lock systemd cookbook to anything < 3.0.0

2.5.2 (2017-07-06)
------------------
- Switch all archs to qemu-kvm-ev

2.5.1 (2017-06-28)
------------------
- Use controller.example.com for all endpoints and port binding in test-kitchen

2.5.0 (2017-04-13)
------------------
- Separate Network Node logic

2.4.3 (2017-04-12)
------------------
- Fixes the issue with volume not being attachable at all.

2.4.2 (2017-03-20)
------------------
- writeback as default cache mode

2.4.1 (2017-03-16)
------------------
- Remove locks on yum-centos and yum-epel

2.4.0 (2017-03-08)
------------------
- Install and setup the Mellanox NEO service

2.3.9 (2017-03-07)
------------------
- Add lock for yum-epel

2.3.8 (2017-02-06)
------------------
- Only restart keystone apache on an initial install

2.3.7 (2017-02-06)
------------------
- Restart linuxbridge-agent when iptable rules are updated

2.3.6 (2017-01-27)
------------------
- Bump check-load warning threshold a little higher

2.3.5 (2017-01-26)
------------------
- diff package name for qemu-img-ev on ppc64le

2.3.4 (2017-01-25)
------------------
- Including ibm-power as a dependency

2.3.3 (2017-01-25)
------------------
- Update the nrpe_check[check_load] resource instead of trying to override attrs

2.3.2 (2017-01-19)
------------------
- Use the package qemu-img-ev as the preferred package name

2.3.1 (2017-01-18)
------------------
- Rubocop and other updates/fixes for TK

2.3.0 (2016-12-19)
------------------
- Setup ssh keys for nova user for migration

2.2.3 (2016-11-01)
------------------
- Fix iscsi firewall attributes to newer format

2.2.2 (2016-09-21)
------------------
- Bump default_api_return_limit to see more meters

2.2.1 (2016-09-17)
------------------
- Fix ssl verify and setup proper SSL certs for testing

2.2.0 (2016-09-07)
------------------
- Enable SSL keystone endpoints

2.1.4 (2016-09-07)
------------------
- Fix cookbook dependencies

2.1.3 (2016-08-19)
------------------
- Adjust nagios check for cinder services

2.1.2 (2016-08-19)
------------------
- OpenStack nagios service checks

2.1.1 (2016-08-12)
------------------
- Switch to using kernel-modules cookbook instead of modules cookbook

2.1.0 (2016-08-05)
------------------
- Add support for per-host interfaces for vxlan and provider networks.

2.0.4 (2016-08-05)
------------------
- Use RDO rabbitmq-server package

2.0.3 (2016-08-04)
------------------
- Increase disk_allocation_ratio to 1.5 to allow for overcommit

2.0.2 (2016-08-03)
------------------
- Reduce DHCP lease to 120 seconds instead of 1 day

2.0.1 (2016-08-03)
------------------
- Set fallback IP for vxlan local_ip

2.0.0 (2016-08-02)
------------------
- Mitaka release

2.2.21
------

- Require firewall cookbook >= 2.2.0

2.2.18
------

- Adds firewall::rabbitmq_mgt recipe to controller recipe
- Require firewall cookbook >= 2.2.21

# 0.1.0

Initial release of osl-openstack

* Enhancements
  * an enhancement

* Bug Fixes
  * a bug fix

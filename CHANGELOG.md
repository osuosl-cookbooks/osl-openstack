CHANGELOG
=========

This file is used to list changes made in each version of the
osl-openstack cookbook.

17.3.1 (2026-01-06)
-------------------
- Add nova-fix-flavors.py script and fix KSM idempotency

17.3.0 (2025-12-09)
-------------------
- Add KSM support for compute nodes

17.2.2 (2025-12-05)
-------------------
- Install conntrack-tools on nodes with linuxbridge neutron agent

17.2.1 (2025-09-10)
-------------------
- Attempt to resolve issues with snapshots

17.2.0 (2025-08-08)
-------------------
- Only install/use fog-openstack gem when needed

17.1.0 (2025-04-16)
-------------------
- Add OSL virt repo for ppc64le on AlmaLinux 9

17.0.3 (2025-02-26)
-------------------
- Increase dhcp lease to 1hr

17.0.2 (2025-02-26)
-------------------
- Only install qemu-kvm-device-display-virtio-vga on x86

17.0.1 (2024-12-20)
-------------------
- Various fixes for AlmaLinux 9 and local storage

17.0.0 (2024-12-19)
-------------------
- OpenStack Yoga

16.0.1 (2024-12-11)
-------------------
- Make sure we run migrations for placement

16.0.0 (2024-12-11)
-------------------
- OpenStack Xena

15.1.0 (2024-12-10)
-------------------
- Various fixes and adjustments

15.0.0 (2024-12-09)
-------------------
- OpenStack Wallaby

14.0.0 (2024-12-04)
-------------------
- OpenStack Victoria

13.0.2 (2024-11-27)
-------------------
- Increase dropdown max to 200 items

13.0.1 (2024-11-27)
-------------------
- Remove prometheus patch

13.0.0 (2024-11-25)
-------------------
- OpenStack Ussuri

12.3.0 (2024-11-15)
-------------------
- Add support for multiple regions

12.2.5 (2024-10-14)
-------------------
- Install kernel-6.6 on nodes using pci-passthrough

12.2.4 (2024-08-06)
-------------------
- Add ability to set ram_allocation_ratio

12.2.3 (2024-07-15)
-------------------
- Reload apache when the wildcard cert is updated

12.2.2 (2024-06-05)
-------------------
- Update messaging repo to local due to CentOS Stream 8 EOL

12.2.1 (2024-03-22)
-------------------
- Add missing polling.yaml file to fix metrics

12.2.0 (2024-03-13)
-------------------
- Add support for POWER10

12.1.0 (2024-01-26)
-------------------
- Remove support for CentOS 7

12.0.7 (2024-01-11)
-------------------
- Set nova user shell on compute nodes

12.0.6 (2024-01-10)
-------------------
- Do not restart libvirtd-tcp.socket

12.0.5 (2024-01-09)
-------------------
- Start libvirtd-tcp before libvirtd

12.0.4 (2024-01-09)
-------------------
- Switch back to libvirtd.service

12.0.3 (2024-01-08)
-------------------
- Fix libvirtd listening on tcp on AlmaLinux 8

12.0.2 (2024-01-06)
-------------------
- Increase ulimit for number of files for rabbitmq-server

12.0.1 (2023-12-21)
-------------------
- Do not include base::grub on AlmaLinux 8

12.0.0 (2023-12-19)
-------------------
- Update to Train release

11.0.7 (2023-12-18)
-------------------
- Redirect to primary endpoint for keystone and horizon

11.0.6 (2023-12-14)
-------------------
- Move alias config into vhost

11.0.5 (2023-12-13)
-------------------
- Have novnc listen on all IPs

11.0.4 (2023-12-12)
-------------------
- Update test database to MariaDB 10.11

11.0.3 (2023-12-08)
-------------------
- Set server_proxyclient_address to primary host IP as well

11.0.2 (2023-12-08)
-------------------
- Set novnc server address to primary host IP address

11.0.1 (2023-12-06)
-------------------
- Rescue on any error

11.0.0 (2023-12-06)
-------------------
- Refactor all code to no longer use upstream Openstack cookbooks

10.6.1 (2023-10-13)
-------------------
- Use correct bound interface based on the attribute

10.6.0 (2023-10-13)
-------------------
- Refactor mon recipe to use check_http

10.5.0 (2023-08-29)
-------------------
- Update to refactored osl-ceph cookbook

10.4.6 (2023-05-15)
-------------------
- Ensure we have proper permissions for libvirt on NVMe nodes

10.4.5 (2023-02-21)
-------------------
- Move osl-apache to after identity so that it runs properly

10.4.4 (2023-02-21)
-------------------
- Misc fixes

10.4.3 (2022-12-23)
-------------------
- Ensure we run osl-apache before openstack-identity::server-apache

10.4.2 (2022-09-29)
-------------------
- Add feature to only have some provider networks on specific hosts

10.4.1 (2022-08-26)
-------------------
- Switch to osl-repos::oslrepo

10.4.0 (2022-08-23)
-------------------
- Switch to osl-resources

10.3.7 (2022-08-16)
-------------------
- Disable IPv6 autoconf on compute nodes

10.3.6 (2022-06-07)
-------------------
- Add PciPassthroughFilter

10.3.5 (2022-06-02)
-------------------
- Only disable SMT on POWER8

10.3.4 (2022-02-02)
-------------------
- Misc fixes

10.3.3 (2021-10-02)
-------------------
- Add ceph secret into libvirt

10.3.2 (2021-10-01)
-------------------
- Add rbd libvirt options if cinder is using ceph

10.3.1 (2021-10-01)
-------------------
- Include _block_ceph recipe if cinder is using ceph

10.3.0 (2021-10-01)
-------------------
- Split ceph enablement between image, compute and volume services

10.2.1 (2021-07-15)
-------------------
- Replace systemd resource with osl equivilent

10.2.0 (2021-06-30)
-------------------
- Enable unified_mode

10.1.0 (2021-06-14)
-------------------
- Various SSL/TLS fixes for CISA

10.0.1 (2021-05-26)
-------------------
- Ensure that https is open for the dashboard

10.0.0 (2021-05-25)
-------------------
- Update to new osl-firewall resources

9.2.0 (2021-04-07)
------------------
- Update Chef dependency to >= 16

9.1.0 (2021-02-03)
------------------
- Replace any occurrence of yum-centos/yum-epel/yum-elrepo with osl-repos equivalents

9.0.2 (2021-01-14)
------------------
- Cookstyle fixes

9.0.1 (2020-11-19)
------------------
- Misc Stein Fixes

9.0.0 (2020-11-09)
------------------
- Stein updates

8.3.6 (2020-11-08)
------------------
- Convert prometheus script to ruby to gather more information

8.3.5 (2020-11-07)
------------------
- Add prometheus cronjob for listing all projects/instances

8.3.4 (2020-09-01)
------------------
- Remove nova login execute resource as it's causing issues

8.3.3 (2020-08-26)
------------------
- Remove multi-store configuration from glance to fix snapshots

8.3.2 (2020-08-24)
------------------
- Use node['openstack']['release'] for branch

8.3.1 (2020-08-21)
------------------
- Migrate away from using poise to direct execute resources

8.3.0 (2020-08-14)
------------------
- Chef 15 updates

8.2.1 (2020-08-11)
------------------
- Use lscpu to determine whether or not to load kvm_pr or kvm_hv

8.2.0 (2020-06-12)
------------------
- Lock to using osl-apache < 5.0.0

8.1.0 (2019-12-30)
------------------
- Chef 14 post-migration fixes

8.0.2 (2019-12-21)
------------------
- Fix yum repo for aarch64

8.0.1 (2019-12-10)
------------------
- Migrate away from kernel-modules cookbook

8.0.0 (2019-12-09)
------------------
- Rocky release

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

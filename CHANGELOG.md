CHANGELOG
=========

This file is used to list changes made in each version of the
osl-openstack cookbook.

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

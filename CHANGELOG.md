CHANGELOG
=========

This file is used to list changes made in each version of the
osl-openstack cookbook.

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

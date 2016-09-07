CHANGELOG
=========

This file is used to list changes made in each version of the
osl-openstack cookbook.

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

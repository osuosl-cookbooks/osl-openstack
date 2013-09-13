osl-packstack Cookbook
======================
This cookbook sets up a computer to install OpenStack using RedHat's RDO deployment tool. There are two types of nodes this cookbook sets up: a regular node (i.e. a controller, a storage server such as Swift or Glance, etc) or an all-in-one or cmpute node (with kvm/libvirt). This cookbook sets up the nova user with ssh-keys and an ssh config file, it sets up the root user for configuration using Packstack with ssh-keys, and it configures libvirt for instance migration.

Requirements
------------
Platform
* CentOS

This cookbook depends on the yum community `yum` and `user` community cookbooks.

Attributes
----------
#### osl-packstack::default
<table>
  <tr>
    <th>Key</th>
    <th>Type</th>
    <th>Description</th>
    <th>Default</th>
  </tr>
  <tr>
    <td><tt>['osl-packstack']['rdo']['release]</tt></td>
    <td>String</td>
    <td>which version of the RHEL openstack repo to use (Currently only supports Grizzly and Havana)</td>
    <td><tt>"grizzly" or "havana"</tt></td>
  </tr>
  <tr>
    <td><tt>['osl-packstack']['type']</tt></td>
    <td><String</td>
    <td>Determines what type of node you are adding to your OpenStack setup.</td>
    <td>"compute" or "other"</td>
  </tr>
</table>

Usage
-----
#### osl-packstack::default


Just include `osl-packstack` in your node's `run_list`:

```json
{
  "name":"my_node",
  "run_list": [
    "recipe[osl-packstack]"
  ]
}
```

Contributing
------------
1. Fork the repository on Github
2. Create a named feature branch (like `add_component_x`)
3. Write your change
4. Write tests for your change (if applicable)
5. Run the tests, ensuring they all pass
6. Submit a Pull Request using Github

License and Authors
-------------------
Author:: [Geoffrey Corey][stumped2] (<coreyg@osuosl.org>)

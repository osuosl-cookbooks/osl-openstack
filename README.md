osl-packstack Cookbook
======================
This cookbook sets up a computer to install OpenStack using RedHat's Foreman-Openstack deployment tool. There are two types of nodes this cookbook sets up: a regular node (i.e. a controller, a storage server such as Swift or Glance, etc) or an all-in-one or cmpute node (with kvm/libvirt). This cookbook sets up the nova user with ssh-keys and an ssh config file and it sets up the repos necessary for installing deploying a node into an openstack infrastructure.

Requirements
------------
Platform
* CentOS

This cookbook depends on the yum community `yum` community cookbooks.

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
    <td><tt>['osl-packstack']['secret_file']</tt></td>
    <td>String</td>
    <td>Location to where the scret_file is to decrypt data bags</td>
    <td><tt></tt></td>
  </tr>
  <tr>
    <td><tt>['rdo_repo_url']</tt></td>
    <td>String</td>
    <td>The url for the rdo-release rpm to download and install. Can be used to control what release inst installed (i.e. Grizzly, Havana, Ice House)</td>
    <td></td>
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

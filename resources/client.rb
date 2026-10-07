resource_name :osl_openstack_client
provides :osl_openstack_client
default_action :create
unified_mode true

property :firewall, [true, false], default: false
property :openrc, [true, false], default: false

action :create do
  osl_repos_openstack 'default' do
    source :osuosl
  end

  # A node still on RDO stops here until /root/migrate-venv.sh swaps the packages
  rdo = openstack_rdo_installed?

  cookbook_file '/root/migrate-venv.sh' do
    cookbook 'osl-openstack'
    source 'migrate-venv.sh'
    mode '0750'
    action rdo ? :create : :delete
  end

  ruby_block 'rdo migration pending' do
    block { raise 'RDO OpenStack packages are installed: run /root/migrate-venv.sh, then cinc-client' }
    only_if { rdo }
  end

  # The db sync markers; templates can trigger a sync before a recipe's own resources
  directory '/var/lib/osl-openstack/db-sync' do
    recursive true
  end

  # Chef upgrades the venv RPMs and restarts after its db syncs, not dnf-automatic
  dnf_automatic_policy 'osl-openstack' do
    exclude %w(osuosl-openstack-*)
  end

  package openstack_client_pkg do
    action :upgrade
  end

  osl_openstack_openrc new_resource.name if new_resource.openrc
  osl_firewall_openstack new_resource.name if new_resource.firewall
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end

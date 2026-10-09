resource_name :osl_openstack_client
provides :osl_openstack_client
default_action :create
unified_mode true

property :firewall, [true, false], default: false
property :openrc, [true, false], default: false

action :create do
  # The bag's release only stages the next one; nodes cross it via openstack-node-upgrade
  installed = openstack_release_installed
  target = openstack_release_target
  stage = openstack_release_action(installed, target) == :stage
  # A new node joins what the cloud's controllers run; only a new cloud starts on the target
  release = installed || openstack_release_cloud || target
  controller = node['osl-openstack']['node_type'] == 'controller'

  osl_repos_openstack 'default' do
    source :osuosl
    version release
  end

  directory '/var/lib/osl-openstack' do
    recursive true
  end

  if stage
    osl_repos_openstack target do
      source :osuosl
      version target
      repo_name "OSL-openstack-#{target}"
      enabled false
    end

    # keepcache: with dnf's default, the next transaction of any kind deletes the download
    execute "stage OpenStack #{target}" do
      command "dnf -y -q --setopt=keepcache=True --enablerepo=OSL-openstack-#{target} --downloadonly " \
              "upgrade 'osuosl-openstack-*' " \
              "&& touch #{openstack_release_staged_marker(target)}"
      creates openstack_release_staged_marker(target)
    end if openstack_release_published?(target)
  end

  # Drops a release's staging repo once the node runs it, or the bag no longer targets it
  openstack_releases.each do |rel|
    next if stage && rel == target
    yum_repository "OSL-openstack-#{rel}" do
      action :remove
    end if ::File.exist?("/etc/yum.repos.d/OSL-openstack-#{rel}.repo")
  end

  # What the node runs once this run finishes; a new node has no RPMs yet when this runs
  state = {
    'installed' => release,
    'target' => target,
    'staged' => release == target || ::File.exist?(openstack_release_staged_marker(target)),
    'node_type' => node['osl-openstack']['node_type'],
  }
  state['db_node'] = openstack_db_node? if controller
  node.default['osl-openstack']['release'] = state.except('db_node', 'node_type')
  node.default['osl-openstack']['db_node'] = state['db_node'] if controller

  directory '/etc/osl-openstack'

  file '/etc/osl-openstack/release.json' do
    content "#{JSON.pretty_generate(state)}\n"
  end

  # backup dumps the service databases from the DB controller; MariaDB's client also ships it
  package 'mysql' if controller && !openstack_mysqldump?

  # This node's part of a release upgrade window; see docs/RELEASE_UPGRADES.md
  cookbook_file '/usr/local/sbin/openstack-node-upgrade' do
    cookbook 'osl-openstack'
    source 'openstack-node-upgrade.py'
    mode '0755'
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
  directory '/var/lib/osl-openstack/db-sync'

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

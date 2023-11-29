resource_name :osl_openstack_client
provides :osl_openstack_client
default_action :create
unified_mode true

action :create do
  osl_repos_openstack 'default'

  # TODO: Workaround for issue on CentOS 7
  package %w(
    python
    python-devel
    python-libs
    tkinter
    yum-plugin-versionlock
  )
  execute 'downgrade to python-2.7.5-93.el7_9' do
    command <<~EOC
      yum versionlock add python-2.7.5-93.el7_9 python-libs-2.7.5-93.el7_9 \
        tkinter-2.7.5-93.el7_9 python-devel-2.7.5-93.el7_9 && \
      yum -y downgrade python python-devel tkinter python-libs
    EOC
    not_if { ::File.readlines('/etc/yum/pluginconf.d/versionlock.list').grep(/python/).any? }
  end

  package openstack_client_pkg
end

action_class do
  include OSLOpenstack::Cookbook::Helpers
end

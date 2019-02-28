require_relative 'spec_helper'

describe 'osl-openstack::default' do
  cached(:chef_run) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      node.automatic['filesystem2']['by_mountpoint']
    end.converge(described_recipe)
  end
  include_context 'identity_stubs'
  it do
    expect(chef_run).to_not add_yum_repository('OSL-Openpower')
  end
  context 'setting arch to ppc64le' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.automatic['kernel']['machine'] = 'ppc64le'
        node.automatic['filesystem2']['by_mountpoint']
        node.normal['ibm_power']['cpu']['cpu_model'] = nil
      end.converge(described_recipe)
    end
    it do
      expect(chef_run).to add_yum_repository('OSL-openpower-openstack')
        .with(
          description: 'OSL Openpower OpenStack repo for centos-7/openstack-pike',
          gpgkey: 'http://ftp.osuosl.org/pub/osl/repos/yum/RPM-GPG-KEY-osuosl',
          gpgcheck: true,
          baseurl: 'http://ftp.osuosl.org/pub/osl/repos/yum/openpower/centos-$releasever/$basearch/openstack-pike'
        )
    end
  end
  it do
    expect(chef_run).to install_package(%w(libffi-devel openssl-devel crudini))
  end
  it do
    expect(chef_run).to create_yum_repository('epel').with(exclude: 'zeromq* python-django-bash-completion')
  end
  %w(
    base::packages
    build-essential
    firewall
    openstack-common
    openstack-common::client
    openstack-common::logging
    openstack-common::python
    openstack-common::sysctl
    openstack-identity::openrc
    selinux::permissive
    yum-qemu-ev
  ).each do |r|
    it do
      expect(chef_run).to include_recipe(r)
    end
  end
  it do
    expect(chef_run).to delete_link('/usr/local/bin/openstack')
  end
  it do
    expect(chef_run).to install_package('python-memcached')
  end

  [
    %r{^export OS_CACERT="/etc/ssl/certs/ca-bundle.crt"$},
    /^export OS_AUTH_TYPE=password$/,
  ].each do |line|
    it do
      expect(chef_run).to render_file('/root/openrc').with_content(line)
    end
  end
end

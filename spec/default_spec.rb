require_relative 'spec_helper'

describe 'osl-openstack::default' do
  cached(:chef_run) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS).converge(described_recipe)
  end
  include_context 'identity_stubs'
  it do
    expect(chef_run).to_not add_yum_repository('OSL-Openpower')
  end
  context 'setting arch to ppc64le' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.automatic['kernel']['machine'] = 'ppc64le'
      end.converge(described_recipe)
    end
    it do
      expect(chef_run).to add_yum_repository('OSL-openpower-openstack')
        .with(
          description: 'OSL Openpower OpenStack repo for centos-7/openstack-mitaka',
          gpgkey: 'http://ftp.osuosl.org/pub/osl/repos/yum/RPM-GPG-KEY-osuosl',
          gpgcheck: true,
          baseurl: 'http://ftp.osuosl.org/pub/osl/repos/yum/openpower/centos-$releasever/$basearch/openstack-mitaka'
        )
    end
  end
  %w(
    base::ifconfig
    selinux::permissive
    yum-qemu-ev
    openstack-common
    openstack-common::logging
    openstack-common::sysctl
    openstack-identity::openrc
    openstack-common::client
    openstack-telemetry::client
  ).each do |r|
    it do
      expect(chef_run).to include_recipe(r)
    end
  end
  it do
    expect(chef_run).to install_package('python-memcached')
  end
  it do
    expect(chef_run).to upgrade_package('mariadb-libs')
  end
end

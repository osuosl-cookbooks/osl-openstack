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
      end.converge(described_recipe)
    end
    %w(libffi-devel openssl-devel).each do |pkg|
      it do
        expect(chef_run).to install_package(pkg)
      end
    end
    it do
      expect(chef_run).to add_yum_repository('OSL-openpower-openstack')
        .with(
          description: 'OSL Openpower OpenStack repo for centos-7/openstack-newton',
          gpgkey: 'http://ftp.osuosl.org/pub/osl/repos/yum/RPM-GPG-KEY-osuosl',
          gpgcheck: true,
          baseurl: 'http://ftp.osuosl.org/pub/osl/repos/yum/openpower/centos-$releasever/$basearch/openstack-newton'
        )
    end
  end
  %w(libffi-devel openssl-devel).each do |pkg|
    it do
      expect(chef_run).to_not install_package(pkg)
    end
  end
  it do
    expect(chef_run).to create_yum_repository('epel').with(exclude: 'zeromq*')
  end
  %w(
    base::packages
    selinux::permissive
    yum-qemu-ev
    openstack-common
    openstack-common::logging
    openstack-common::sysctl
    openstack-identity::openrc
  ).each do |r|
    it do
      expect(chef_run).to include_recipe(r)
    end
  end
  it do
    expect(chef_run).to install_python_runtime('2')
      .with(
        provider: PoisePython::PythonProviders::System,
        pip_version: '9.0.3'
      )
  end
  it do
    expect(chef_run).to create_python_virtualenv('/opt/osc').with(system_site_packages: true)
  end
  it do
    expect(chef_run).to install_python_package('cliff')
      .with(
        version: '2.9.0',
        # virtualenv: '/opt/osc'
      )
  end
  it do
    expect(chef_run).to install_python_package('python-openstackclient')
      .with(
        version: '3.11.0',
        # virtualenv: '/opt/osc'
      )
  end
  it do
    expect(chef_run.link('/usr/local/bin/openstack')).to link_to('/opt/osc/bin/openstack')
  end
  it do
    expect(chef_run).to install_package('python-memcached')
  end
  it do
    expect(chef_run).to upgrade_package('mariadb-libs')
  end
end

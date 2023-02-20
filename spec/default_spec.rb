require_relative 'spec_helper'

describe 'osl-openstack::default' do
  cached(:chef_run) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      node.automatic['filesystem2']['by_mountpoint']
    end.converge(described_recipe)
  end
  include_context 'identity_stubs'
  it do
    expect(chef_run).to add_yum_repository('RDO-stein')
      .with(
        baseurl: 'http://centos.osuosl.org/$releasever/cloud/$basearch/openstack-stein',
        gpgkey: 'https://www.centos.org/keys/RPM-GPG-KEY-CentOS-SIG-Cloud',
        priority: '20'
      )
  end
  it do
    expect(chef_run).to create_yum_repository('OSL-openstack').with(
      description: 'OSL OpenStack repo for centos-7/openstack-stein',
      gpgkey: 'https://ftp.osuosl.org/pub/osl/repos/yum/RPM-GPG-KEY-osuosl',
      gpgcheck: true,
      baseurl: 'https://ftp.osuosl.org/pub/osl/repos/yum/$releasever/openstack-stein/$basearch',
      priority: '10'
    )
  end
  context 'setting arch to ppc64le' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.automatic['kernel']['machine'] = 'ppc64le'
        node.automatic['filesystem2']['by_mountpoint']
        node.override['ibm_power']['cpu']['cpu_model'] = nil
      end.converge(described_recipe)
    end
    it do
      expect(chef_run).to add_yum_repository('RDO-stein')
        .with(
          baseurl: 'http://centos-altarch.osuosl.org/$releasever/cloud/$basearch/openstack-stein',
          gpgkey: 'https://www.centos.org/keys/RPM-GPG-KEY-CentOS-SIG-Cloud',
          priority: '20'
        )
    end
  end
  context 'setting arch to aarch64' do
    cached(:chef_run) do
      ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
        node.automatic['kernel']['machine'] = 'aarch64'
        node.automatic['filesystem2']['by_mountpoint']
        node.override['ibm_power']['cpu']['cpu_model'] = nil
      end.converge(described_recipe)
    end
    it do
      expect(chef_run).to add_yum_repository('RDO-stein')
        .with(
          baseurl: 'http://centos-altarch.osuosl.org/$releasever/cloud/$basearch/openstack-stein',
          gpgkey: 'https://www.centos.org/keys/RPM-GPG-KEY-CentOS-SIG-Cloud',
          priority: '20'
        )
    end
  end
  it do
    expect(chef_run).to install_package(%w(libffi-devel openssl-devel crudini))
  end
  %w(
    base::packages
    openstack-common
    openstack-common::client
    openstack-common::logging
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
    expect(chef_run).to install_build_essential('osl-openstack')
  end
  it do
    expect(chef_run).to delete_link('/usr/local/bin/openstack')
  end
  it do
    expect(chef_run).to upgrade_package('python2-urllib3')
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

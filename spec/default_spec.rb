require_relative 'spec_helper'

describe 'osl-openstack::default', default: true do
  let(:runner) do
    ChefSpec::SoloRunner.new(REDHAT_OPTS) do |node|
      # Work around for base::ifconfig:47
      node.automatic['virtualization']['system']
    end
  end
  let(:node) { runner.node }
  cached(:chef_run) { runner.converge(described_recipe) }
  include_context 'identity_stubs'
  context 'setting arch to x86_64' do
    before do
      node.automatic['kernel']['machine'] = 'x86_64'
    end
    it 'does not add OSL-Openpower repository on x86_64' do
      expect(chef_run).to_not add_yum_repository('OSL-Openpower')
    end
  end
  %w(ppc64 ppc64le).each do |a|
    context "setting arch to #{a}" do
      let(:chef_run) { runner.converge(described_recipe) }
      before do
        node.automatic['kernel']['machine'] = a
      end
      it "add OSL-openpower-openstack repository on #{a}" do
        expect(chef_run).to add_yum_repository('OSL-openpower-openstack')
          .with(
            description: 'OSL Openpower OpenStack repo for centos-7/openstack' \
              '-mitaka',
            gpgkey: 'http://ftp.osuosl.org/pub/osl/repos/yum/RPM-GPG-KEY-osuosl',
            gpgcheck: true,
            baseurl: 'http://ftp.osuosl.org/pub/osl/repos/yum/openpower/cento' \
              's-$releasever/$basearch/openstack-mitaka'
          )
      end
    end
  end
  describe '/etc/sysconfig/iptables-config' do
    let(:file) { chef_run.template('/etc/sysconfig/iptables-config') }
    [
      /^IPTABLES_SAVE_ON_STOP="yes"$/,
      /^IPTABLES_SAVE_ON_RESTART="yes"$/
    ].each do |line|
      it do
        expect(chef_run).to render_config_file(file.name)
          .with_content(line)
      end
    end
  end
  cached(:chef_run) { runner.converge(described_recipe) }
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
    it "includes cookbook #{r}" do
      expect(chef_run).to include_recipe(r)
    end
  end
  it do
    expect(chef_run).to upgrade_package('mariadb-libs')
  end
end

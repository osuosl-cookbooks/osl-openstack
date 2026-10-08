require_relative '../../spec_helper'

describe 'osl-openstack::network' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      include_context 'common_stubs'

      it_behaves_like 'restarts on package upgrade', 'osuosl-openstack-neutron-agent', ['neutron-linuxbridge-agent']

      it_behaves_like 'oslo messaging config', '/etc/neutron/neutron.conf'

      it { is_expected.to install_package(%w(conntrack-tools ebtables ipset)) }
      it { is_expected.to upgrade_package 'osuosl-openstack-neutron-agent' }
      it { is_expected.to include_recipe 'osl-openstack::network_common' }
      it do
        is_expected.to create_template('/etc/neutron/neutron.conf').with(
          owner: 'root',
          group: 'neutron',
          mode: '0640',
          sensitive: true,
          variables: neutron_conf_vars(controller: false)
        )
      end
      it do
        is_expected.to render_file('/etc/neutron/neutron.conf')
          .with_content('root_helper = sudo /opt/openstack/neutron-agent/bin/neutron-rootwrap /etc/neutron/rootwrap.conf')
          .with_content('root_helper_daemon = sudo /opt/openstack/neutron-agent/bin/neutron-rootwrap-daemon /etc/neutron/rootwrap.conf')
          .with_content("[privsep]\nhelper_command = sudo /opt/openstack/neutron-agent/bin/privsep-helper\n")
      end
      it { is_expected.to_not render_file('/etc/neutron/neutron.conf').with_content(/^\[experimental\]$/) }

      context 'region2' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['fqdn'] = 'node1.testing.osuosl.org'
          end.converge(described_recipe)
        end

        include_context 'region2_stubs'

        it do
          is_expected.to create_template('/etc/neutron/neutron.conf').with(
            owner: 'root',
            group: 'neutron',
            mode: '0640',
            sensitive: true,
            variables: neutron_conf_vars(controller: false, region2: true)
          )
        end
      end
    end
  end
end

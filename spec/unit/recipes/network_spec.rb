require_relative '../../spec_helper'

describe 'osl-openstack::network' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      include_context 'common_stubs'

      it_behaves_like 'oslo messaging config', '/etc/neutron/neutron.conf'

      it { is_expected.to install_package(%w(conntrack-tools ebtables ipset osuosl-openstack-neutron-agent)) }
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

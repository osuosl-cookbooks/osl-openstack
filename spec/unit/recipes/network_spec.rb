require_relative '../../spec_helper'

describe 'osl-openstack::network' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to install_package(%w(ebtables ipset openstack-neutron-linuxbridge)) }
      it { is_expected.to include_recipe 'osl-openstack::network_common' }
      it do
        is_expected.to create_template('/etc/neutron/neutron.conf').with(
          owner: 'root',
          group: 'neutron',
          mode: '0640',
          sensitive: true,
          variables: {
              auth_endpoint: 'controller.example.com',
              compute_pass: 'nova',
              controller: false,
              database_connection: 'mysql+pymysql://neutron_x86:neutron@localhost:3306/neutron_x86',
              memcached_endpoint: 'controller.example.com:11211',
              region: 'RegionOne',
              service_pass: 'neutron',
              transport_url: 'rabbit://openstack:openstack@controller.example.com:5672',
          }
        )
      end

      context 'region2' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.automatic['fqdn'] = 'node1.example.com'
          end.converge(described_recipe)
        end

        include_context 'region2_stubs'

        it do
          is_expected.to create_template('/etc/neutron/neutron.conf').with(
            owner: 'root',
            group: 'neutron',
            mode: '0640',
            sensitive: true,
            variables: {
                auth_endpoint: 'controller.example.com',
                compute_pass: 'nova',
                controller: false,
                database_connection: 'mysql+pymysql://neutron_x86:neutron@localhost_region2:3306/neutron_x86',
                memcached_endpoint: 'controller_region2.example.com:11211',
                region: 'RegionTwo',
                service_pass: 'neutron',
                transport_url: 'rabbit://openstack:openstack@controller_region2.example.com:5672',
            }
          )
        end
      end
    end
  end
end

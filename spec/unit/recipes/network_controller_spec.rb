require_relative '../../spec_helper'

describe 'osl-openstack::network_controller' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm) do |node|
          node.normal['osl-openstack']['cluster_name'] = 'x86'
          node.normal['osl-openstack']['node_type'] = 'controller'
        end.converge(described_recipe)
      end

      include_context 'common_stubs'
      include_context 'network_stubs'

      it { is_expected.to add_osl_repos_openstack 'network' }
      it { is_expected.to create_osl_openstack_client 'network' }
      it { is_expected.to accept_osl_firewall_openstack 'network' }
      it do
        is_expected.to create_osl_openstack_user('neutron').with(
          domain_name: 'default',
          role_name: 'admin',
          project_name: 'service',
          password: 'neutron'
        )
      end
      it { is_expected.to grant_role_osl_openstack_user 'neutron' }
      it { is_expected.to create_osl_openstack_service('neutron').with(type: 'network') }
      %w(
        admin
        internal
        public
      ).each do |int|
        it do
          is_expected.to create_osl_openstack_endpoint("network-#{int}").with(
            endpoint_name: 'network',
            service_name: 'neutron',
            interface: int,
            url: 'http://controller.example.com:9696',
            region: 'RegionOne'
          )
        end
      end
      it do
        is_expected.to install_package %w(
          ebtables
          openstack-neutron
          openstack-neutron-linuxbridge
          openstack-neutron-metering-agent
          openstack-neutron-ml2
        )
      end
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
              controller: true,
              database_connection: 'mysql+pymysql://neutron:neutron@localhost:3306/x86_neutron',
              memcached_endpoint: 'controller.example.com:11211',
              service_pass: 'neutron',
              transport_url: 'rabbit://openstack:openstack@controller.example.com:5672',
          }
        )
      end
      it do
        is_expected.to create_cookbook_file('/etc/neutron/plugins/ml2/ml2_conf.ini').with(
          owner: 'root',
          group: 'neutron',
          mode: '0640'
        )
      end
      it { expect(chef_run.link('/etc/neutron/plugin.ini')).to link_to('/etc/neutron/plugins/ml2/ml2_conf.ini') }
      it do
        is_expected.to create_osl_systemd_unit_drop_in('part_of_iptables').with(
          content: {
            'Unit' => {
              'PartOf' => 'iptables.service',
            },
          },
          unit_name: 'neutron-linuxbridge-agent.service'
        )
      end
      it do
        is_expected.to create_template('/etc/neutron/plugins/ml2/linuxbridge_agent.ini').with(
          owner: 'root',
          group: 'neutron',
          mode: '0640',
          variables: {
            local_ip: '127.0.0.1',
            physical_interface_mappings: %w(public:eth1),
          }
        )
      end
      it do
        expect(chef_run.template('/etc/neutron/plugins/ml2/linuxbridge_agent.ini')).to \
          notify('service[neutron-linuxbridge-agent]').to(:restart)
      end
      it { is_expected.to enable_service 'neutron-linuxbridge-agent' }
      it { is_expected.to start_service 'neutron-linuxbridge-agent' }
      it do
        expect(chef_run.service('neutron-linuxbridge-agent')).to subscribe_to('template[/etc/neutron/neutron.conf]').on(:restart)
      end
      it do
        is_expected.to nothing_execute('neutron: db_sync').with(
          user: 'neutron',
          group: 'neutron',
          command: <<~EOC
            neutron-db-manage --config-file /etc/neutron/neutron.conf --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head
          EOC
        )
      end
      it do
        expect(chef_run.execute('neutron: db_sync')).to \
          subscribe_to('template[/etc/neutron/neutron.conf]').on(:run).immediately
      end
      it do
        is_expected.to create_template('/etc/neutron/metadata_agent.ini').with(
          owner: 'root',
          group: 'neutron',
          mode: '0640',
          sensitive: true,
          variables: {
            memcached_endpoint: 'controller.example.com:11211',
            metadata_proxy_shared_secret: '2SJh0RuO67KpZ63z',
            nova_metadata_host: 'controller.example.com',
          }
        )
      end
      it do
        expect(chef_run.template('/etc/neutron/metadata_agent.ini')).to notify('service[neutron-metadata-agent]').to(:restart)
      end
      it { is_expected.to create_cookbook_file('/etc/neutron/dhcp_agent.ini').with(owner: 'root', group: 'neutron') }
      it { expect(chef_run.cookbook_file('/etc/neutron/dhcp_agent.ini')).to notify('service[neutron-dhcp-agent]').to(:restart) }
      it { is_expected.to create_cookbook_file('/etc/neutron/l3_agent.ini').with(owner: 'root', group: 'neutron') }
      it { expect(chef_run.cookbook_file('/etc/neutron/l3_agent.ini')).to notify('service[neutron-l3-agent]').to(:restart) }
      it { is_expected.to create_cookbook_file('/etc/neutron/metering_agent.ini').with(owner: 'root', group: 'neutron') }
      it { expect(chef_run.cookbook_file('/etc/neutron/metering_agent.ini')).to notify('service[neutron-metering-agent]').to(:restart) }
      %w(
        neutron-dhcp-agent
        neutron-l3-agent
        neutron-metadata-agent
        neutron-metering-agent
        neutron-server
      ).each do |srv|
        it { is_expected.to enable_service srv }
        it { is_expected.to start_service srv }
        it { expect(chef_run.service(srv)).to subscribe_to('template[/etc/neutron/neutron.conf]').on(:restart) }
        it { expect(chef_run.service(srv)).to subscribe_to('cookbook_file[/etc/neutron/plugins/ml2/ml2_conf.ini]').on(:restart) }
      end
      it do
        is_expected.to run_bash('block external dns on public').with(
          code: <<~EOC
            ip netns exec qdhcp-8df74e06-c4aa-4eb2-b312-0e915bf8f97f iptables -A INPUT -p tcp --dport 53 ! -s 10.0.0.0/24 -j DROP
            ip netns exec qdhcp-8df74e06-c4aa-4eb2-b312-0e915bf8f97f iptables -A INPUT -p udp --dport 53 ! -s 10.0.0.0/24 -j DROP
          EOC
        )
      end
      it { is_expected.to_not run_bash 'block external dns on private1' }
    end
  end
end

require_relative '../../spec_helper'

describe 'osl-openstack::network_controller' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm) do |node|
          node.normal['osl-openstack']['node_type'] = 'controller'
        end.converge(described_recipe)
      end

      include_context 'common_stubs'

      it do
        is_expected.to render_file('/etc/neutron/neutron.conf')
          .with_content(/^\[database\]\nconnection = .*\n#.*\nconnection_recycle_time = 300$/)
      end
      it do
        is_expected.to render_file('/etc/neutron/neutron.conf')
          .with_content(/^\[experimental\]\n#.*\nlinuxbridge = true$/)
      end
      it { is_expected.to_not render_file('/etc/neutron/neutron.conf').with_content(/allow_overlapping_ips/) }
      include_context 'network_stubs'

      # The DNS-blocking bash only runs where the qdhcp namespace exists
      let(:qdhcp_ns_present) { true }
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?)
          .with('/run/netns/qdhcp-8df74e06-c4aa-4eb2-b312-0e915bf8f97f')
          .and_return(qdhcp_ns_present)
      end

      it { is_expected.to create_osl_openstack_client('network').with(firewall: true, openrc: false) }
      it { is_expected.to create_osl_openstack_service_user('neutron').with(password: 'neutron') }
      it do
        is_expected.to create_osl_openstack_api('neutron').with(
          type: 'network',
          endpoint_name: 'network',
          url: 'http://controller.testing.osuosl.org:9696',
          region: 'RegionOne'
        )
      end
      it { is_expected.to install_package %w(conntrack-tools ebtables osuosl-openstack-neutron-agent osuosl-openstack-neutron-controller) }
      it { is_expected.to include_recipe 'osl-openstack::network_common' }
      it do
        is_expected.to create_template('/etc/neutron/neutron.conf').with(
          owner: 'root',
          group: 'neutron',
          mode: '0640',
          sensitive: true,
          variables: neutron_conf_vars(controller: true)
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
            neutron_venv: '/opt/openstack/neutron-agent',
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
        expect(chef_run.execute('neutron: db_sync')).to \
          subscribe_to('cookbook_file[/etc/neutron/plugins/ml2/ml2_conf.ini]').on(:run).immediately
      end
      it do
        is_expected.to render_file('/etc/neutron/neutron.conf')
          .with_content("[AGENT]\nroot_helper = sudo /opt/openstack/neutron-controller/bin/neutron-rootwrap /etc/neutron/rootwrap.conf\n")
          .with_content("root_helper_daemon = sudo /opt/openstack/neutron-controller/bin/neutron-rootwrap-daemon /etc/neutron/rootwrap.conf\n")
      end
      %w(privsep privsep_conntrack privsep_dhcp_release privsep_link privsep_namespace).each do |section|
        it do
          is_expected.to render_file('/etc/neutron/neutron.conf')
            .with_content("[#{section}]\nhelper_command = sudo /opt/openstack/neutron-controller/bin/privsep-helper\n")
        end
        it do
          is_expected.to render_file('/etc/neutron/plugins/ml2/linuxbridge_agent.ini')
            .with_content("[#{section}]\nhelper_command = sudo /opt/openstack/neutron-agent/bin/privsep-helper\n")
        end
      end
      it do
        is_expected.to render_file('/etc/neutron/plugins/ml2/linuxbridge_agent.ini')
          .with_content(%r{^\[AGENT\]\npolling_interval = 2\n.*\nroot_helper = sudo /opt/openstack/neutron-agent/bin/neutron-rootwrap })
          .with_content("root_helper_daemon = sudo /opt/openstack/neutron-agent/bin/neutron-rootwrap-daemon /etc/neutron/rootwrap.conf\n")
      end
      it do
        is_expected.to create_template('/etc/neutron/metadata_agent.ini').with(
          owner: 'root',
          group: 'neutron',
          mode: '0640',
          sensitive: true,
          variables: {
            memcached_endpoint: 'controller.testing.osuosl.org:11211',
            metadata_proxy_shared_secret: '2SJh0RuO67KpZ63z',
            nova_metadata_host: 'controller.testing.osuosl.org',
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

      # Also an HA secondary whose dhcp-agent doesn't host the network yet
      context 'fqdn controller' do
        let(:qdhcp_ns_present) { false }
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.normal['osl-openstack']['node_type'] = 'controller'
            node.automatic['fqdn'] = 'controller2.testing.osuosl.org'
            node.automatic['network']['interfaces']['p2p1']['addresses'] = {
              '192.168.1.100' => {
                'family' => 'inet',
              },
            }
          end.converge(described_recipe)
        end
        it do
          is_expected.to create_template('/etc/neutron/plugins/ml2/linuxbridge_agent.ini').with(
            owner: 'root',
            group: 'neutron',
            mode: '0640',
            variables: {
              local_ip: '192.168.1.100',
              neutron_venv: '/opt/openstack/neutron-agent',
              physical_interface_mappings: %w(public:p1p2),
            }
          )
        end
        it { is_expected.to_not run_bash 'block external dns on public' }
      end

      context 'fqdn compute' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.normal['osl-openstack']['node_type'] = 'compute'
            node.automatic['fqdn'] = 'node1.testing.osuosl.org'
            node.automatic['network']['interfaces']['eno2']['addresses'] = {
              '192.168.1.101' => {
                'family' => 'inet',
              },
            }
          end.converge(described_recipe)
        end
        it do
          is_expected.to create_template('/etc/neutron/plugins/ml2/linuxbridge_agent.ini').with(
            owner: 'root',
            group: 'neutron',
            mode: '0640',
            variables: {
              local_ip: '192.168.1.101',
              neutron_venv: '/opt/openstack/neutron-agent',
              physical_interface_mappings: %w(public:eno1),
            }
          )
        end
      end
      context 'region2' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm) do |node|
            node.normal['osl-openstack']['node_type'] = 'controller'
            node.automatic['fqdn'] = 'node1.testing.osuosl.org'
          end.converge(described_recipe)
        end

        include_context 'region2_stubs'
        it do
          is_expected.to create_osl_openstack_api('neutron').with(
            type: 'network',
            endpoint_name: 'network',
            url: 'http://controller_region2.testing.osuosl.org:9696',
            region: 'RegionTwo'
          )
        end

        it do
          is_expected.to create_template('/etc/neutron/neutron.conf').with(
            owner: 'root',
            group: 'neutron',
            mode: '0640',
            sensitive: true,
            variables: neutron_conf_vars(controller: true, region2: true)
          )
        end

        it do
          is_expected.to create_template('/etc/neutron/metadata_agent.ini').with(
            owner: 'root',
            group: 'neutron',
            mode: '0640',
            sensitive: true,
            variables: {
              memcached_endpoint: 'controller_region2.testing.osuosl.org:11211',
              metadata_proxy_shared_secret: '2SJh0RuO67KpZ63z',
              nova_metadata_host: 'controller_region2.testing.osuosl.org',
            }
          )
        end
      end
    end
  end
end

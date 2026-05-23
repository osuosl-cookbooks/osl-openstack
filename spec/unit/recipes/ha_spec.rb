require_relative '../../spec_helper'

describe 'osl-openstack::ha' do
  ALL_PLATFORMS.each do |p|
    context "#{p[:platform]} #{p[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(p).converge(described_recipe)
      end

      before do
        stub_data_bag_item('openstack', 'x86').and_return(
          'ha' => {
            'keepalived' => {
              'primary' => { 'fauxhai.local' => true },
              'interface' => { 'fauxhai.local' => 'eth1' },
              'priority' => { 'fauxhai.local' => 100 },
              'virtual_router_id' => 1,
              'auth_pass' => 'auth_pass',
              # CIDR notation - keepalived gets the full string,
              # haproxy bind directives must use the stripped form.
              'vip_v4' => '192.168.60.10/24',
              'vip_v6' => 'fc00::10/64',
            },
            'api_listen_ip' => {
              'fauxhai.local' => '192.168.60.11',
            },
            'haproxy' => {
              'stats_user' => 'admin',
              'stats_pass' => 'stats_pass',
            },
          }
        )
      end

      it 'converges successfully' do
        expect { chef_run }.to_not raise_error
      end

      it 'tells osl-apache it is behind a load balancer' do
        # So Apache trusts X-Forwarded-For / X-Forwarded-Proto from
        # haproxy and REMOTE_ADDR reflects the real client.
        expect(chef_run.node['osl-apache']['behind_loadbalancer']).to be true
      end

      it 'passes the VIP to keepalived in CIDR form' do
        expect(chef_run).to create_keepalived_vrrp_instance('openstack-ipv4').with(
          virtual_ipaddress: ['192.168.60.10/24']
        )
        expect(chef_run).to create_keepalived_vrrp_instance('openstack-ipv6').with(
          virtual_ipaddress: ['fc00::10/64']
        )
      end

      it 'strips the CIDR before passing the VIPs to haproxy bind' do
        # keystone is representative; every haproxy_listen in the
        # openstack_ha_services loop builds its v4 + v6 binds the same
        # way. Without the strip we'd see '192.168.60.10/24:5000' or
        # '[fc00::10/64]:5000'.
        binds = chef_run.find_resources(:haproxy_listen)
                        .select { |r| r.name == 'keystone' }
                        .map(&:bind)
        expect(binds).to contain_exactly(
          '192.168.60.10:5000',
          '[fc00::10]:5000'
        )
      end

      it 'does not write the stub haproxy.cfg or the wildcard-release execute' do
        # Removed in favor of letting the haproxy.cfg template's
        # delayed_action :create handle initial rendering. EL9's
        # haproxy package preset is `disabled`, so the package install
        # doesn't auto-start the daemon with bind *:5000.
        expect(chef_run.find_resources(:file).map(&:name)).not_to include('/etc/haproxy/haproxy.cfg')
        expect(chef_run.find_resources(:execute).map(&:name)).not_to include('haproxy_release_wildcards')
      end
    end
  end
end

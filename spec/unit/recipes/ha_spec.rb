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

      it 'strips the CIDR and appends ssl crt to tls listeners' do
        # keystone is tls: true in openstack_ha_services, so each bind
        # has `ssl crt <bundle>` appended. Without the CIDR strip we'd
        # see '192.168.60.10/24:5000 ssl crt ...'.
        binds = chef_run.find_resources(:haproxy_listen)
                        .select { |r| r.name == 'keystone' }
                        .map(&:bind)
        expect(binds).to contain_exactly(
          '192.168.60.10:5000 ssl crt /etc/haproxy/certs/wildcard.pem',
          '[fc00::10]:5000 ssl crt /etc/haproxy/certs/wildcard.pem'
        )
      end

      it 'binds plain HTTP listeners (no tls) without ssl crt' do
        # glance-api is tls:false (still plain HTTP today), so no
        # ssl crt should be appended.
        binds = chef_run.find_resources(:haproxy_listen)
                        .select { |r| r.name == 'glance-api' }
                        .map(&:bind)
        expect(binds).to contain_exactly(
          '192.168.60.10:9292',
          '[fc00::10]:9292'
        )
      end

      it 'switches tls listeners to mode http with option forwardfor' do
        keystone_first = chef_run.find_resources(:haproxy_listen)
                                 .find { |r| r.name == 'keystone' }
        expect(keystone_first.mode).to eq('http')
        expect(keystone_first.option).to include('forwardfor')
      end

      it 'keeps non-tls listeners in mode tcp' do
        glance_first = chef_run.find_resources(:haproxy_listen)
                               .find { |r| r.name == 'glance-api' }
        expect(glance_first.mode).to eq('tcp')
        expect(glance_first.option).to be_nil # property unset
      end

      it 'builds the haproxy wildcard PEM bundle' do
        expect(chef_run).to create_directory('/etc/haproxy/certs').with(
          owner: 'haproxy', group: 'haproxy', mode: '0700'
        )
        expect(chef_run).to create_certificate_manage('wildcard-haproxy').with(
          cert_path: '/etc/haproxy/certs',
          combined_file: true,
          create_subfolders: false,
          owner: 'haproxy',
          group: 'haproxy'
        )
        expect(chef_run.certificate_manage('wildcard-haproxy')).to notify('haproxy_service[haproxy]').to(:reload)
      end

      it 'starts haproxy during converge so the VIP serves before keystone calls' do
        # The ruby_block renders haproxy.cfg and notifies the eager
        # start; without it a fresh bootstrap fails at osl_openstack_role
        # with connection-refused on the VIP (haproxy's normal :start is
        # delayed to end-of-run). Guarded by not_if so it only fires
        # when haproxy isn't already running (kept idempotent).
        rb = chef_run.ruby_block('render haproxy.cfg + start haproxy before api calls')
        expect(rb).to notify('service[haproxy_eager_start]').to(:start).immediately
        expect(rb).to notify('service[haproxy_eager_start]').to(:enable).immediately
        expect(chef_run.service('haproxy_eager_start').service_name).to eq('haproxy')
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

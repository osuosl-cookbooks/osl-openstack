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
              'vip_v4' => '192.168.60.10',
              'vip_v6' => 'fc00::10',
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
    end
  end
end

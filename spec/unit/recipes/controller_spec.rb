require_relative '../../spec_helper'

describe 'osl-openstack::controller' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm).converge(described_recipe)
      end

      include_context 'common_stubs'
      include_context 'network_stubs'
      include_context 'compute_stubs'
      include_context 'telemetry_stubs'

      before do
        stub_data_bag_item('prometheus', 'openstack_exporter')
          .and_return(
            x86: {
              username: 'admin',
              user_domain_name: 'default',
              password: 'admin',
              project_name: 'admin',
              project_domain_name: 'default',
              identity_api_version: 3,
              auth_url: 'https://controller.example.org:5000/v3',
              region_name: 'RegionOne',
            }
          )
      end

      it { is_expected.to include_recipe 'osl-openstack::identity' }
      it { is_expected.to include_recipe 'osl-openstack::image' }
      it { is_expected.to include_recipe 'osl-openstack::network_controller' }
      it { is_expected.to include_recipe 'osl-openstack::compute_controller' }
      it { is_expected.to include_recipe 'osl-openstack::block_storage_controller' }
      it { is_expected.to include_recipe 'osl-openstack::orchestration' }
      it { is_expected.to include_recipe 'osl-openstack::telemetry_controller' }
      it { is_expected.to include_recipe 'osl-openstack::dashboard' }
      it { is_expected.to include_recipe 'osl-prometheus::openstack' }
      it { is_expected.to include_recipe 'osl-openstack::mon' }
      it do
        is_expected.to render_file('/etc/sysconfig/prometheus-openstack-exporter').with_content(
          'OS_AUTH_URL=https://controller.example.org:5000/v3'
        )
      end
    end
  end
end

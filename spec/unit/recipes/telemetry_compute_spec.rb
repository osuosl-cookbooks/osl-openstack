require_relative '../../spec_helper'

describe 'osl-openstack::telemetry_compute' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm) do |node|
          node.normal['osl-openstack']['cluster_name'] = 'x86'
        end.converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to add_osl_repos_openstack 'telemetry' }
      it { is_expected.to create_osl_openstack_client 'telemetry' }
      it { is_expected.to accept_osl_firewall_openstack 'telemetry' }
      it { is_expected.to include_recipe 'osl-openstack::telemetry_common' }
      it { is_expected.to install_package 'openstack-ceilometer-compute' }
      it { is_expected.to enable_service 'openstack-ceilometer-compute' }
      it { is_expected.to start_service 'openstack-ceilometer-compute' }
      it do
        expect(chef_run.service('openstack-ceilometer-compute')).to \
          subscribe_to('template[/etc/ceilometer/ceilometer.conf]').on(:restart)
      end
    end
  end
end

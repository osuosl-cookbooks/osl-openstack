require_relative '../../spec_helper'

# osl_openstack_client with its defaults; every production caller sets firewall
describe 'openstack_test::client' do
  ALL_PLATFORMS.each do |pltfrm|
    context "#{pltfrm[:platform]} #{pltfrm[:version]}" do
      cached(:chef_run) do
        ChefSpec::SoloRunner.new(pltfrm.merge(step_into: %w(osl_openstack_client))).converge(described_recipe)
      end

      include_context 'common_stubs'

      it { is_expected.to create_osl_openstack_client('test').with(firewall: false, openrc: false) }
      it { is_expected.to add_osl_repos_openstack('default').with(source: :osuosl) }
      it { is_expected.to install_package %w(osuosl-openstack-cli) }
      it { is_expected.to_not create_osl_openstack_openrc 'test' }
      it { is_expected.to_not accept_osl_firewall_openstack 'test' }
    end
  end
end

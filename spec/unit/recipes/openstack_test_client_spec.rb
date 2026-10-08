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
      it { is_expected.to upgrade_package %w(osuosl-openstack-cli osuosl-openstack-selinux) }
      it { is_expected.to_not create_osl_openstack_openrc 'test' }
      it { is_expected.to_not accept_osl_firewall_openstack 'test' }
      it { is_expected.to delete_cookbook_file '/root/migrate-venv.sh' }
      it { is_expected.to_not run_ruby_block 'rdo migration pending' }

      context 'on a node still running RDO' do
        cached(:chef_run) do
          ChefSpec::SoloRunner.new(pltfrm.merge(step_into: %w(osl_openstack_client))).converge(described_recipe)
        end

        before do
          stubs_for_provider('osl_openstack_client[test]') do |provider|
            allow(provider).to receive(:openstack_rdo_installed?).and_return(true)
          end
        end

        it do
          is_expected.to create_cookbook_file('/root/migrate-venv.sh').with(
            cookbook: 'osl-openstack', source: 'migrate-venv.sh', mode: '0750'
          )
        end
        it { is_expected.to run_ruby_block 'rdo migration pending' }
      end
    end
  end
end

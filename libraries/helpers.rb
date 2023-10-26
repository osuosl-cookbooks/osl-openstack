module OSLOpenstack
  module Cookbook
    module Helpers
      include Chef::Mixin::ShellOut

      def os_secrets
        data_bag_item('openstack', node['osl-openstack']['databag_item'])
      end

      def openstack_rabbitmq_user?(user)
        cmd = shell_out!('rabbitmqctl -q list_users')
        cmd.stdout.match(/^#{user}/)
      end

      def openstack_rabbitmq_permissions?(user)
        cmd = shell_out!('rabbitmqctl -q list_permissions')
        cmd.stdout.match(/^#{user}\s+\.\*\s+\.\*\s+\.\*/)
      end

      def openstack_services
        {
          'aodh' => 'aodh',
          'application_catalog' => 'murano',
          'baremetal' => 'ironic',
          'block-storage' => 'cinder',
          'compute_api' => 'nova_api',
          'compute_cell0' => 'nova_cell0',
          'compute' => 'nova',
          'dashboard' => 'horizon',
          'database' => 'trove',
          'dns' => 'designate',
          'identity' => 'keystone',
          'image' => 'glance',
          'load_balancer' => 'octavia',
          'network' => 'neutron',
          'object_storage' => 'swift',
          'orchestration' => 'heat',
          'placement' => 'placement',
          'telemetry' => 'ceilometer',
          'telemetry_metric' => 'gnocchi',
        }
      end

      def openstack_client_pkg
        'python-openstackclient'
      end

      def openstack_transport_url
        m = os_secrets['messaging']

        "rabbit://#{m['user']}:#{m['pass']}@#{m['endpoint']}:5672"
      end

      def openstack_database_connection(service)
        s = os_secrets
        db_name = "#{s['database_server']['suffix']}_#{openstack_services[service]}"
        db_host = s['database_server']['endpoint']

        "mysql+pymysql://#{s[service]['db']['user']}:#{s[service]['db']['pass']}@#{db_host}:3306/#{db_name}"
      end
    end
  end
end
Chef::DSL::Recipe.include ::OSLOpenstack::Cookbook::Helpers
Chef::Resource.include ::OSLOpenstack::Cookbook::Helpers

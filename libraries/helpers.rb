module OSLOpenstack
  module Cookbook
    module Helpers
      include Chef::Mixin::ShellOut

      # Process-wide caches. Module-level so they survive across the
      # per-action-class instances Chef creates for each resource - the
      # alternative (per-instance @ivars) re-fetches the data bag and
      # builds a fresh keystone connection for every osl_openstack_*
      # resource, which adds up fast on a controller run.
      class << self
        attr_accessor :secrets_cache, :conn_cache
      end

      def self.collection_cache
        @collection_cache ||= {}
      end

      # Reset all module-level caches. Call between ChefSpec examples so
      # cached state doesn't leak across tests.
      def self.reset_cache!
        @secrets_cache = nil
        @conn_cache = nil
        @collection_cache = {}
      end

      def install_fog_openstack_gem
        return if gem_installed?('fog-openstack')
        declare_resource(:package, 'gcc') { compile_time(true) }

        declare_resource(:chef_gem, 'fog-openstack') do
          version '~> 1.1'
          compile_time true
        end
      end

      def os_secrets
        OSLOpenstack::Cookbook::Helpers.secrets_cache ||=
          data_bag_item('openstack', node['osl-openstack']['databag_item'])
      end

      def openstack_rabbitmq_user?(user)
        cmd = shell_out!('rabbitmqctl -q list_users')
        cmd.stdout.match?(/^#{Regexp.escape(user)}\s/)
      end

      # nil checks the default vhost; pass a name for a per-cloud vhost.
      def openstack_rabbitmq_permissions?(user, vhost = nil)
        flag = vhost ? " -p #{vhost}" : ''
        cmd = shell_out!("rabbitmqctl -q list_permissions#{flag}")
        cmd.stdout.match?(/^#{Regexp.escape(user)}\s+\.\*\s+\.\*\s+\.\*/)
      end

      def openstack_rabbitmq_vhost?(vhost)
        cmd = shell_out!('rabbitmqctl -q list_vhosts')
        cmd.stdout.match?(/^#{Regexp.escape(vhost)}\s*$/)
      end

      # Messaging SIG selects version by subdir: EL8/9 use rabbitmq-38
      # (3.9.x), EL10 only ships rabbitmq-4 (4.x).
      def openstack_rabbitmq_repo
        case node['platform_version'].to_i
        when 8
          'https://ftp.osuosl.org/pub/osl/vault/$releasever-stream/messaging/$basearch/rabbitmq-38'
        when 9
          'https://centos-stream.osuosl.org/SIGs/$releasever-stream/messaging/$basearch/rabbitmq-38'
        when 10
          'https://centos-stream.osuosl.org/SIGs/$releasever-stream/messaging/$basearch/rabbitmq-4'
        end
      end

      # Join the local RabbitMQ broker to the primary's Mnesia cluster
      # so queue metadata is shared across both nodes. Without clustering
      # the brokers are isolated and OpenStack RPC reply queues become
      # undeliverable when request and reply go through different nodes.
      def openstack_rabbitmq_join_cluster(primary_node_name)
        # Extract the primary's short hostname from "rabbit@<host>.<domain>"
        # and compare exactly to node['hostname'] - substring matching
        # would conflate "controller" with "controller2".
        primary_short_hostname = primary_node_name.split('@', 2).last.split('.', 2).first
        if primary_short_hostname == node['hostname']
          Chef::Log.info("This node IS the RabbitMQ primary ('#{primary_node_name}'). No join needed.")
          return false
        end
        # rabbitmqctl 3.8 doesn't accept --format json on cluster_status.
        # Parse the plain text output - if the primary's node name shows
        # up at all, we're already clustered with it.
        cluster_status = shell_out('rabbitmqctl cluster_status')
        cluster_status.error!
        if cluster_status.stdout.include?(primary_node_name)
          Chef::Log.info("Already clustered with '#{primary_node_name}'. Skipping.")
          return false
        end
        Chef::Log.info("Joining RabbitMQ cluster with primary '#{primary_node_name}'.")
        begin
          shell_out!('rabbitmqctl stop_app')
          shell_out!("rabbitmqctl join_cluster #{primary_node_name}")
          shell_out!('rabbitmqctl start_app')
          true
        rescue Mixlib::ShellOut::ShellCommandFailed => e
          Chef::Log.error("RabbitMQ join_cluster failed: #{e.message}")
          shell_out('rabbitmqctl start_app')
          raise 'Failed to join RabbitMQ cluster; see chef logs.'
        end
      end

      def openstack_services
        {
          'block-storage' => 'cinder',
          'compute_api' => 'nova_api',
          'compute_cell0' => 'nova_cell0',
          'compute' => 'nova',
          'dashboard' => 'horizon',
          'identity' => 'keystone',
          'image' => 'glance',
          'network' => 'neutron',
          'orchestration' => 'heat',
          'placement' => 'placement',
          'telemetry' => 'ceilometer',
        }
      end

      def openstack_python_bin
        case node['platform_version'].to_i
        when 8, 9
          '/usr/bin/python3'
        end
      end

      def openstack_python_lib
        case node['platform_version'].to_i
        when 8
          '/usr/lib/python3.6'
        when 9
          '/usr/lib/python3.9'
        end
      end

      def openstack_client_pkg
        case node['platform_version'].to_i
        when 8, 9
          %w(
            openstack-selinux
            python3-openstackclient
          )
        end
      end

      def openstack_compute_controller_pkgs
        case node['platform_version'].to_i
        when 8, 9
          %w(
            openstack-nova-api
            openstack-nova-conductor
            openstack-nova-novncproxy
            openstack-nova-scheduler
            openstack-placement-api
            python3-osc-placement
          )
        end
      end

      def openstack_compute_pkgs
        case node['platform_version'].to_i
        when 8
          %w(
            device-mapper
            device-mapper-multipath
            libguestfs-rescue
            libguestfs-tools
            libvirt
            openstack-nova-compute
            python3-libguestfs
            sg3_utils
            sysfsutils
          )
        when 9
          pkgs =
            %w(
              device-mapper
              device-mapper-multipath
              libguestfs-rescue
              libvirt
              openstack-nova-compute
              python3-libguestfs
              qemu-kvm
              qemu-kvm-device-display-virtio-gpu
              qemu-kvm-device-display-virtio-gpu-pci
              sg3_utils
              sysfsutils
              virt-win-reg
            )
          pkgs << 'qemu-kvm-device-display-virtio-vga' if intel?
          pkgs.sort!
        end
      end

      def openstack_transport_url
        m = os_secrets['messaging']
        user = m['user']
        pass = m['pass']
        port = openstack_rabbit_tls? ? 5671 : 5672
        hosts = Array(m['endpoint']).sort.map { |endpoint| "#{user}:#{pass}@#{endpoint}:#{port}" }.join(',')
        # messaging.vhost is the URL path; absent or '/' = the default
        # vhost, a name like 'x86' isolates that cloud on the tier.
        vhost = m['vhost'].to_s
        vhost = '' if vhost == '/'
        "rabbit://#{hosts}/#{vhost}"
      end

      def openstack_memcached_endpoints
        Array(os_secrets['memcached']['endpoint']).sort
      end

      def openstack_memcached_servers
        openstack_memcached_endpoints.join(',')
      end

      # Per-host listen address for Apache/WSGI vhosts so that HAProxy can
      # bind to the VIP on the same port. Returns '*' when the cloud is not
      # configured for HA (back-compat with single-controller deployments).
      def openstack_api_listen_ip
        ha = safe_dig(os_secrets, 'ha')
        return '*' unless ha
        safe_dig(ha, 'api_listen_ip', node['fqdn']) || '*'
      end

      # Concrete IP that local healthchecks (NRPE etc.) should connect to
      # in order to hit *this* node's API daemons directly, bypassing
      # the VIP / HAProxy. On HA controllers Apache binds the per-host
      # private IP (ha.api_listen_ip[node['fqdn']]); on non-HA
      # single-controller deploys Apache binds wildcard, so
      # node['ipaddress'] is the right local target.
      def openstack_local_api_endpoint
        safe_dig(os_secrets, 'ha', 'api_listen_ip', node['fqdn']) || node['ipaddress']
      end

      # Whether haproxy terminates TLS on the VIP (forwarding plain HTTP
      # to the Apache / native daemon backends on the per-host IP).
      # True whenever the cloud is configured for HA - the cert lives
      # only on haproxy then, and Apache vhosts serve plain HTTP behind
      # it. False on single-controller deploys, where Apache still
      # terminates TLS itself.
      def openstack_tls_on_haproxy?
        !!safe_dig(os_secrets, 'ha')
      end

      # Declare quorum (Raft-replicated) queues instead of classic.
      # Separate flag, not `ha`: queue type/replicas are fixed at
      # declaration, so flip this only once the full cluster is up
      # (see docs/HA_MIGRATION.md).
      def openstack_rabbit_quorum_queue?
        !!safe_dig(os_secrets, 'messaging', 'quorum_queues')
      end

      # Connect to RabbitMQ over TLS (AMQPS 5671); set messaging.tls.
      def openstack_rabbit_tls?
        !!safe_dig(os_secrets, 'messaging', 'tls')
      end

      # CA bundle to verify the broker cert; nil uses the system trust
      # store.
      def openstack_rabbit_ssl_ca_file
        safe_dig(os_secrets, 'messaging', 'ssl_ca_file')
      end

      # True when the haproxy service is already active. Gates the
      # one-time eager start in the ha recipe so re-running chef on an
      # already-running controller is a no-op (keeps the converge
      # idempotent). shell_out (not shell_out!) so an inactive/absent
      # unit's non-zero exit just reads as "not running"; the rescue
      # covers hosts without systemctl (e.g. the chefspec runner), so
      # specs don't need to stub the command.
      def haproxy_running?
        shell_out('systemctl is-active --quiet haproxy').exitstatus.zero?
      rescue
        false
      end

      # Reachability probe for the keystone API on the controller VIP.
      # nova-compute makes a blocking keystone call at startup and exits
      # non-zero if the VIP isn't reachable yet - on a fresh converge a
      # cold-ARP blip the instant the daemon starts is enough to crash it
      # and abort the run, even though systemd's Restart=always recovers
      # it seconds later. A plain TCP connect both confirms keystone is
      # listening and warms this host's ARP/neighbor entry for the VIP.
      # The rescue reads an unreachable VIP as "not yet" rather than
      # raising (and keeps specs from needing a live socket).
      def openstack_keystone_reachable?
        require 'socket'
        require 'timeout'
        host = os_secrets['identity']['endpoint']
        Timeout.timeout(5) { TCPSocket.new(host, 5000).close }
        true
      rescue
        false
      end

      # Block until the keystone VIP accepts connections, so chef only
      # starts the compute daemons once their keystone dependency is
      # actually reachable. Backoff mirrors os_conn; raises after the
      # budget so a genuine outage surfaces instead of hanging forever.
      def openstack_wait_for_keystone
        host = os_secrets['identity']['endpoint']
        count = 0
        max_attempts = 30
        until openstack_keystone_reachable?
          count += 1
          raise "keystone VIP #{host}:5000 unreachable after #{count} attempts" if count >= max_attempts
          Chef::Log.warn("Waiting for keystone VIP #{host}:5000 before starting compute daemons (attempt ##{count})")
          sleep([2 * count, 15].min)
        end
      end

      # Comma-joined glance endpoint URLs for nova/cinder. Accepts either
      # a single string or an array in os_secrets['image']['endpoint'].
      def openstack_image_api_servers
        Array(os_secrets['image']['endpoint']).map { |e| "http://#{e}:9292" }.join(',')
      end

      # OpenStack APIs to put behind HAProxy on the controller VIP.
      # horizon-https uses 'source' for session affinity; horizon-http
      # is a redirect-only listener that 301s to https (the rewrite
      # that used to live in the Apache horizon vhost moves to haproxy
      # in HA mode). Everything else round-robins. The
      # openstack_exporter (port 9183) is intentionally NOT fronted -
      # its package only supports listen_port (no listen_address), so
      # it always binds 0.0.0.0 which would conflict with a VIP bind
      # on the same host. Prometheus should scrape both controllers
      # directly as separate targets.
      #
      # `tls: true` marks services that already serve TLS today
      # (keystone + horizon-https via Apache vhost SSL, novnc via
      # nova-novncproxy `--ssl_only`). In HA mode
      # (openstack_tls_on_haproxy?) the listener flips to haproxy
      # `mode http` + `ssl crt ...` and the backend serves plain
      # HTTP. Services without `tls:` are plain-HTTP today (the data
      # bag endpoints are `http://...`); migrating those to HTTPS is
      # tracked separately and would just add `tls: true` here.
      def openstack_ha_services
        [
          { name: 'keystone',       port: 5000, tls: true },
          { name: 'glance-api',     port: 9292 },
          { name: 'nova-api',       port: 8774 },
          { name: 'nova-metadata',  port: 8775 },
          { name: 'placement',      port: 8778 },
          { name: 'neutron-server', port: 9696 },
          { name: 'cinder-api',     port: 8776 },
          { name: 'heat-api',       port: 8004 },
          { name: 'heat-cfn',       port: 8000 },
          { name: 'novnc',          port: 6080, tls: true },
          { name: 'horizon-http',   port: 80,  redirect_to_https: true },
          { name: 'horizon-https',  port: 443, balance: 'source', tls: true },
        ]
      end

      def openstack_database_connection(service)
        s = os_secrets
        suffix = s['database_server']['suffix']
        db_name = "#{openstack_services[service]}_#{suffix}"
        db_user = "#{s[service]['db']['user']}_#{suffix}"
        db_host = s['database_server']['endpoint']

        "mysql+pymysql://#{db_user}:#{s[service]['db']['pass']}@#{db_host}:3306/#{db_name}"
      end

      def openstack_vxlan_ip(controller)
        node_type = controller ? 'controller' : 'compute'
        vxlan = os_secrets['network']['vxlan_interface']
        vxlan_interface = vxlan[node_type][node['fqdn']] || vxlan[node_type]['default']
        vxlan_addrs = node['network']['interfaces'][vxlan_interface]

        if vxlan_addrs.nil? || vxlan_addrs['addresses'].empty?
          # Fall back to localhost if the interface has no IP
          '127.0.0.1'
        else
          address = vxlan_addrs['addresses'].find do |_, attrs|
            attrs['family'] == 'inet'
          end
          if address.nil?
            '127.0.0.1'
          else
            address.first
          end
        end
      end

      def openstack_pci_alias
        pci_alias = os_secrets['compute']['pci_alias']
        if pci_alias
          pci_alias[node['fqdn']] || nil
        end
      end

      def openstack_pci_passthrough_whitelist
        pci_passthrough_whitelist = os_secrets['compute']['pci_passthrough_whitelist']
        if pci_passthrough_whitelist
          pci_passthrough_whitelist[node['fqdn']] || nil
        end
      end

      def openstack_local_storage_compute
        local_storage = os_secrets['compute']['local_storage']
        if local_storage
          local_storage[node['fqdn']] || false
        else
          false
        end
      end

      def openstack_cinder_disabled?
        cinder_disabled = os_secrets['compute']['cinder_disabled']
        if cinder_disabled
          cinder_disabled[node['fqdn']] || false
        else
          false
        end
      end

      def openstack_local_storage_image
        local_storage = os_secrets['image']['local_storage']
        if local_storage
          local_storage[node['fqdn']] || false
        else
          false
        end
      end

      def openstack_physical_interface_mappings(controller)
        node_type = controller ? 'controller' : 'compute'
        int_mappings = []
        physical_interface_mappings = os_secrets['network']['physical_interface_mappings']

        physical_interface_mappings.each do |int|
          interface = int[node_type][node['fqdn']] || int[node_type]['default']
          int_mappings.push("#{int['name']}:#{interface}") unless interface == 'disabled'
        end

        int_mappings
      end

      def openstack_power8?
        node.read('cpu', 'model_name').to_s.match?(/POWER8/)
      end

      def openstack_power10?
        node.read('cpu', 'model_name').to_s.match?(/POWER10/)
      end

      def openstack_qemu_guest?
        if node['kernel']['machine'] == 'ppc64le'
          node.read('cpu', 'machine').to_s.match?(/qemu/i)
        else
          node['virtualization']['role'] == 'guest'
        end
      end

      # OpenStack API helpers
      def os_conn
        return OSLOpenstack::Cookbook::Helpers.conn_cache if OSLOpenstack::Cookbook::Helpers.conn_cache

        install_fog_openstack_gem unless gem_installed?('fog-openstack')
        raise 'fog-openstack Gem missing' unless gem_installed?('fog-openstack')
        require 'fog/openstack' unless defined?(::Fog)

        s = os_secrets
        params = {
          openstack_auth_url: "https://#{s['identity']['endpoint']}:5000/v3",
          openstack_username: 'admin',
          openstack_api_key: s['users']['admin'],
          openstack_project_name: 'admin',
          openstack_domain_name: 'default',
        }

        # On a fresh controller bootstrap, Apache + keystone may not be
        # ready when this is first called. Retry with backoff and surface
        # the actual error if all attempts fail (rather than returning
        # nil and letting callers fail with NoMethodError on nil).
        count = 0
        max_attempts = 20
        last_error = nil
        loop do
          begin
            OSLOpenstack::Cookbook::Helpers.conn_cache = Fog::OpenStack::Identity.new(params)
            return OSLOpenstack::Cookbook::Helpers.conn_cache
          rescue => e
            last_error = e
            count += 1
            break if count >= max_attempts
            Chef::Log.warn("Unable to connect to keystone at #{params[:openstack_auth_url]} (#{e.class}: #{e.message}), retry ##{count}")
            sleep([2**count, 30].min)
          end
        end
        raise "Failed to connect to keystone at #{params[:openstack_auth_url]} after #{count} attempts: #{last_error.class}: #{last_error.message}"
      end

      # Memoized fetch of a top-level keystone collection (roles,
      # services, domains, projects, users, endpoints). Resources that
      # mutate a collection MUST call os_collection_invalidate after
      # the create succeeds so the next lookup re-fetches.
      def os_collection(name)
        OSLOpenstack::Cookbook::Helpers.collection_cache[name] ||= os_conn.send(name).all
      end

      def os_collection_invalidate(name)
        OSLOpenstack::Cookbook::Helpers.collection_cache.delete(name)
      end

      def os_role(new_resource)
        os_collection(:roles).find { |r| r.name == new_resource.role_name }
      end

      def os_service(new_resource)
        os_collection(:services).find { |s| s.name == new_resource.service_name }
      end

      def os_domain(new_resource)
        os_collection(:domains).find do |d|
          d.id == new_resource.domain_name || d.name == new_resource.domain_name
        end
      end

      def os_endpoint(new_resource)
        service = os_service(new_resource)
        raise "service_name #{new_resource.service_name} not found" if service.nil?
        os_collection(:endpoints).find do |e|
          e.service_id == service.id && e.interface == new_resource.interface && e.region == new_resource.region
        end
      end

      def os_project(new_resource)
        domain = os_domain(new_resource)
        os_collection(:projects).find do |p|
          p.name == new_resource.project_name && (domain.nil? || p.domain_id == domain.id)
        end
      end

      def os_user(new_resource)
        domain = os_domain(new_resource)
        os_collection(:users).find do |u|
          u.name == new_resource.user_name && (domain.nil? || u.domain_id == domain.id)
        end
      end

      def os_user_grant_role(new_resource)
        project = os_project(new_resource)
        role = os_role(new_resource)
        user = os_user(new_resource)
        raise "project_name #{new_resource.project_name} not found" if project.nil?
        raise "role #{new_resource.role_name} not found" if role.nil?
        raise "user #{new_resource.user_name} not found" if user.nil?
        user.projects.find { |p| p['name'] == new_resource.project_name }
      end

      def os_user_grant_domain(new_resource)
        role = os_role(new_resource)
        user = os_user(new_resource)
        raise "role #{new_resource.role_name} not found" if role.nil?
        raise "user #{new_resource.user_name} not found" if user.nil?
        user.check_role role.id
      end

      private

      def safe_dig(hash, *keys)
        keys.reduce(hash) do |acc, key|
          case acc
          when Hash, Chef::DataBagItem, Chef::EncryptedDataBagItem
            acc[key]
          end
        end
      end

      # Check if a given gem is installed and available for require
      #
      # @return [true, false] Gem installed result
      #
      def gem_installed?(gem_name)
        !Gem::Specification.find_by_name(gem_name).nil?
      rescue Gem::LoadError
        false
      end
    end
  end
end
Chef::DSL::Recipe.include ::OSLOpenstack::Cookbook::Helpers
Chef::Resource.include ::OSLOpenstack::Cookbook::Helpers

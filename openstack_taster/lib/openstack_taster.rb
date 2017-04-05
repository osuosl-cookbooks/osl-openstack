# frozen_string_literal: true

require 'date'
require 'excon'
require 'net/ssh'
require 'pry'

class OpenStackTaster
  IMAGE_NAME_PREFIX = 'openstack-taster'
  INSTANCE_FLAVOR_NAME = 'm1.osltiny'
  INSTANCE_NETWORK_NAME = 'public'
  INSTANCE_NAME_PREFIX = 'taster'
  INSTANCE_VOLUME_DEV = '/dev/vdz'
  INSTANCE_VOLUME_MOUNT_POINT = '/mnt/taster_volume'

  VOLUME_TEST_FILE_NAME = 'test' # FIXME
  VOLUME_TEST_FILE_CONTENTS = 'contents' # FIXME
  TIMEOUT_INSTANCE_CREATE = 20
  TIMEOUT_VOLUME_ATTACH = 10
  TIMEOUT_VOLUME_PERSIST = 10

  TIME_SLUG_FORMAT = '%Y%m%d_%H%M%S'

  # rubocop:disable ParameterLists
  def initialize(
    compute_service,
    volume_service,
    image_service,
    network_service,
    ssh_keys,
    fixed_ip
  )
    @compute_service = compute_service
    @volume_service  = volume_service
    @image_service   = image_service
    @network_service = network_service

    @volumes = @volume_service.volumes
    @images  = @compute_service.images # FIXME: Images over compute service is deprecated
      .reject { |image| image.name.start_with?(INSTANCE_NAME_PREFIX) } # FIXME: Filter images by IMAGE_NAME_PREFIX
    # @images = @image_service.images
    #   .select { |image| image.name.start_with?(IMAGE_NAME_PREFIX) }

    puts "Tasting with #{@images.count} images and #{@volumes.count} volumes."

    @ssh_keypair     = ssh_keys[:keypair]
    @ssh_private_key = ssh_keys[:private_key]
    @ssh_public_key  = ssh_keys[:public_key] # REVIEW

    @fixed_ip = fixed_ip
    @instance_flavor = @compute_service.flavors
      .select { |flavor|  flavor.name  == INSTANCE_FLAVOR_NAME  }.first
    @instance_network = @network_service.networks
      .select { |network| network.name == INSTANCE_NETWORK_NAME }.first
  end

  def taste_all
    @images.each(&method(:taste))
  end

  def taste(image)
    distro_user_name = image.name.downcase.gsub(/[^a-z].*$/, '') # truncate downcased name at first non-alpha char
    instance_name = format(
      '%s-%s-%s',
      INSTANCE_NAME_PREFIX,
      Time.new.strftime(TIME_SLUG_FORMAT),
      distro_user_name
    )

    puts "\nTasting #{image.name} as '#{instance_name}' with username '#{distro_user_name}'"

    instance = @compute_service.servers.create(
      name: instance_name,
      flavor_ref: @instance_flavor.id,
      image_ref: image.id,
      fixed_ip: @fixed_ip, # FIXME
      networks: @instance_network.id, # REVIEW
      key_name: @ssh_keypair
    )

    if instance.nil?
      puts 'Failed to create instance.'
      error_log(instance_name, 'Failed to create instance.')
      return
    end

    instance.wait_for(20) { ready? }
    test_volumes(instance, distro_user_name)
  rescue Fog::Errors::TimeoutError
    puts 'Instance creation timed out.'
    error_log(instance.name, "Instance fault: #{instance.fault}")
  ensure
    if instance
      puts 'Destroying instance.'
      instance.destroy
    end
  end

  def error_log(filename, message)
    File.open(filename, 'a') do |file|
      file.puts(message)
    end
  end

  def test_volumes(instance, username)
    failures = @volumes.reject do |volume|
      print "Testing volume '#{volume.name}'... "

      unless volume_attach?(instance, volume)
        puts 'Failed to attach.'
        next
      end

      unless volume_mount_unmount?(instance, username)
        puts 'Failed to mount/unmount.'
        next
      end

      unless volume_detach?(instance, volume)
        puts 'Failed to detach.'
        next
      end

      puts 'Success.'
      true
    end

    return true if failures.empty?

    puts 'Encountered failures; creating image...'
    response = instance.create_image(instance.name)
    image = @image_service.images.find_by_id(response.body['image']['id'])
    image.wait_for { status == 'active' }
  end

  def volume_attach?(instance, volume)
    volume_attached = lambda do |_|
      volume_attachments.any? do |attachment|
        attachment['volumeId'] == volume.id
      end
    end

    instance.attach_volume(volume.id, INSTANCE_VOLUME_DEV)
    instance.wait_for(TIMEOUT_VOLUME_ATTACH, &volume_attached)

    sleep TIMEOUT_VOLUME_PERSIST

    return true if instance.instance_eval(&volume_attached)

    error_log(instance.name, "Failed to attach volume'#{volume.name}': Volume was unexpectedly detached.")
    false
  rescue Excon::Error => e
    error_log(instance.name, e.message)
    false
  rescue Fog::Errors::TimeoutError
    error_log(instance.name, "Failed to attach volume '#{volume.name}': Operation timed out")
    false
  end

  def volume_mount_unmount?(instance, username)
    commands = [
      ["sudo mkdir #{INSTANCE_VOLUME_MOUNT_POINT}",                        ''],
      ["sudo mount #{INSTANCE_VOLUME_DEV} #{INSTANCE_VOLUME_MOUNT_POINT}", ''],
      ["sudo cat #{INSTANCE_VOLUME_MOUNT_POINT}/#{VOLUME_TEST_FILE_NAME}", VOLUME_TEST_FILE_CONTENTS],
      ["sudo umount #{INSTANCE_VOLUME_MOUNT_POINT}",                       '']
    ]
    Net::SSH.start(
      instance.addresses['public'].first['addr'],
      username,
      keys: [@ssh_private_key]
    ) do |ssh|
      commands.each do |command, expected|
        result = ssh.exec!(command)
        if result != expected
          error_log(instance.name, "Failure while running '#{command}': expected '#{expected}', got '#{result}'")
          return false # returns from parent method
        end
      end
    end
    true
  rescue Net::SSH::AuthenticationFailed => e
    error_log(instance.name, e.message)
    false
  end

  def volume_detach?(instance, volume)
    instance.detach_volume(volume.id)
  rescue Excon::Error => e
    error_log(instance.name, e.message)
    false
  end
end

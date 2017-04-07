# frozen_string_literal: true

require 'date'
require 'excon'
require 'net/ssh'
require 'pry'

class OpenStackTaster
  INSTANCE_FLAVOR_NAME = 'm1.small'
  INSTANCE_NETWORK_NAME = 'public'
  INSTANCE_NAME_PREFIX = 'taster'
  INSTANCE_VOLUME_DEV = '/dev/vdz'
  INSTANCE_VOLUME_MOUNT_POINT = '/mnt/taster_volume'

  VOLUME_TEST_FILE_NAME = 'test' # FIXME
  VOLUME_TEST_FILE_CONTENTS = 'contents' # FIXME
  TIMEOUT_INSTANCE_CREATE = 20
  TIMEOUT_VOLUME_ATTACH = 10
  TIMEOUT_VOLUME_PERSIST = 20
  TIMEOUT_SSH_STARTUP = 30

  TIME_SLUG_FORMAT = '%Y%m%d_%H%M%S'
  SAFE_IMAGE_NAMES = [ # FIXME: Remove hard coding
    'OpenSUSE Leap 42.2 LE',
    'Ubuntu 14.04 BE',
    'Fedora 23 BE',
    'Fedora 23 LE',
    'Fedora 24 BE',
    'Fedora 24 LE',
    'Debian 8 LE',
    'Debian 8 BE',
    'CentOS 7.2 BE',
    'Ubuntu 14.04 LE',
    'Ubuntu 16.04 BE',
    'Ubuntu 16.04 LE',
    'Ubuntu 16.10 BE',
    'Ubuntu 16.10 LE',
    'CentOS 7.2 LE'
  ].freeze

  # rubocop:disable ParameterLists
  def initialize(
    compute_service,
    volume_service,
    image_service,
    network_service,
    ssh_keys,
    log_dir,
    fixed_ip
  )
    @compute_service = compute_service
    @volume_service  = volume_service
    @image_service   = image_service
    @network_service = network_service

    @volumes = @volume_service.volumes
    @images  = @compute_service.images # FIXME: Images over compute service is deprecated
      .select { |image| SAFE_IMAGE_NAMES.include?(image.name) }

    puts "Tasting with #{@images.count} images and #{@volumes.count} volumes."

    @ssh_keypair     = ssh_keys[:keypair]
    @ssh_private_key = ssh_keys[:private_key]
    @ssh_public_key  = ssh_keys[:public_key] # REVIEW

    @log_dir         = log_dir
    @fixed_ip        = fixed_ip

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
    distro_arch = image.name.downcase.slice(-2, 2)
    instance_name = format(
      '%s-%s-%s-%s',
      INSTANCE_NAME_PREFIX,
      Time.new.strftime(TIME_SLUG_FORMAT),
      distro_user_name,
      distro_arch
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
    Dir.mkdir(@log_dir) unless Dir.exist?(@log_dir)
    File.open("#{@log_dir}/#{filename}.log", 'a') do |file|
      file.puts(message)
    end
  end

  def create_image(instance)
    response = instance.create_image(instance.name)
    image = @image_service.images.find_by_id(response.body['image']['id'])
    image.wait_for { status == 'active' }
  end

  def test_volumes(instance, username)
    failures = @volumes.reject do |volume|
      print "Testing volume '#{volume.name}'... "

      if volume.attachments.any?
        puts "Volume '#{volume.name}' is already in an attached state; skipping volume."
        next
      end

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

    if failures.empty?
      error_log(instance.name, 'Encountered 0 failures. This is a perfect machine; creating image')
      create_image(instance)
      return true
    else
      error_log(instance.name, "Encountered #{failures.count} failures; continuing on the path to greatness...")
      return false
    end
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
    error_log(instance.name, "Failed to attach volume '#{volume.name}': Operation timed out.")
    false
  end

  def volume_mount_unmount?(instance, username)
    # commands to record the state of the instance
    record_info_commands = [
      'cat /proc/partitions',
      'dmesg | tail -n 20'
    ]

    # commands to actually mount the volume
    dev = INSTANCE_VOLUME_DEV
    mount_point = INSTANCE_VOLUME_MOUNT_POINT
    file_name = VOLUME_TEST_FILE_NAME
    file_contents = VOLUME_TEST_FILE_CONTENTS

    commands = [
      ["sudo mkdir #{mount_point}",            ''],
      ["sudo mount #{dev} #{mount_point}",     ''],
      ["sudo cat #{mount_point}/#{file_name}", file_contents],
      ["sudo umount #{mount_point}",           '']
    ]

    puts "Sleeping for #{TIMEOUT_SSH_STARTUP} seconds for the volume to be actually attached"
    sleep TIMEOUT_SSH_STARTUP

    @ssh_logger = Logger.new('logs/' + instance.name + '_ssh_log')

    puts 'Mounting volume from inside the instance...'
    tries = 0
    Net::SSH.start(
      instance.addresses['public'].first['addr'],
      username,
      verbose: :debug,
      paranoid: false,
      logger: @ssh_logger,
      keys: [@ssh_private_key]
    ) do |ssh|

      tries += 1
      record_info_commands.each do |command|
        result = ssh.exec!(command)
        error_log(instance.name, "Ran '#{command}' and got '#{result}'")
      end

      commands.each do |command, expected|
        result = ssh.exec!(command)
        if result != expected
          error_log(instance.name, "Failure while running '#{command}': expected '#{expected}', got '#{result.chomp}'")
          return false # returns from parent method
        end
      end
    end
    true
  rescue Net::SSH::AuthenticationFailed => e # This possibly means a problem with the key
    puts "Encountered #{e.message} while connecting to the instance. Ir-recoverable"
    error_log(instance.name, e.backtrace)
    error_log(instance.name, e.message)
    false
  rescue Errno::ECONNREFUSED => e # This generally occurs when the instance is booting up
    print "Encountered #{e.message} while connecting to the instance."
    error_log(instance.name, e.backtrace)
    error_log(instance.name, e.message)
    puts "Trying SSH connection again for #{tries}+1 time"
    retry unless tries >= 3
    exit!
    false
  end

  def volume_detach?(instance, volume)
    instance.detach_volume(volume.id)
  rescue Excon::Error => e
    error_log(instance.name, e.message)
    false
  end
end

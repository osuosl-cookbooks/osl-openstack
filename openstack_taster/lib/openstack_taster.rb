# frozen_string_literal: true

require 'date'
require 'excon'
require 'net/ssh'
require 'pry'

class OpenStackTaster
  INSTANCE_FLAVOR_NAME = 'm1.small'
  INSTANCE_NETWORK_NAME = 'public'
  INSTANCE_NAME_PREFIX = 'taster'
  INSTANCE_VOLUME_MOUNT_POINT = '/mnt/taster_volume'

  VOLUME_TEST_FILE_NAME = 'test' # FIXME
  VOLUME_TEST_FILE_CONTENTS = 'contents' # FIXME
  TIMEOUT_INSTANCE_CREATE = 20
  TIMEOUT_VOLUME_ATTACH = 10
  TIMEOUT_VOLUME_PERSIST = 20
  TIMEOUT_INSTANCE_STARTUP = 30
  TIMEOUT_SSH_RETRY = 15

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
    print 'Building... '
    instance = @compute_service.servers.create(
      name: instance_name,
      flavor_ref: @instance_flavor.id,
      image_ref: image.id,
      fixed_ip: @fixed_ip, # FIXME
      networks: @instance_network.id, # REVIEW
      key_name: @ssh_keypair
    )

    if instance.nil?
      error_log(instance_name, 'Failed to create instance.', true)
      return
    end

    instance.wait_for(20) { ready? }
    puts 'Done.'

    ssh_logger = Logger.new('logs/' + instance.name + '_ssh_log')
    test_volumes(instance, distro_user_name, ssh_logger)
  rescue Fog::Errors::TimeoutError
    puts 'Instance creation timed out.'
    error_log(instance.name, "Instance fault: #{instance.fault}")
  rescue Interrupt
    puts "\nCaught interrupt"
    raise SystemExit
  ensure
    if instance
      puts 'Destroying instance.'
      instance.destroy
    end
  end

  def error_log(filename, message, dup_stdout = false)
    puts message if dup_stdout

    Dir.mkdir(@log_dir) unless Dir.exist?(@log_dir)
    File.open("#{@log_dir}/#{filename}.log", 'a') do |file|
      file.puts(message)
    end
  end

  def create_image(instance)
    image_id = instance.create_image(instance.name).body['image']['id']
    @image_service.images
      .find_by_id(image_id)
      .wait_for { status == 'active' }
  end

  def test_volumes(instance, username, ssh_logger)
    failures = @volumes.reject do |volume|
      error_log(instance.name, "\n## Testing volume '#{volume.name}' ##", true)

      volume = @volume_service.volumes.find_by_id(volume.id)

      if volume.attachments.any?
        puts "Volume '#{volume.name}' is already in an attached state; skipping volume."
        next
      end

      next unless (vdev = volume_attach?(instance, volume))

      begin
        mount_success = volume_mount_unmount?(instance, vdev, username, ssh_logger)
        log_partitions(instance, username, ssh_logger)
      rescue Net::SSH::AuthenticationFailed => e
        puts "Fatal: encountered #{e.message} while connecting to the instance."
        error_log(instance.name, e.backtrace)
        error_log(instance.name, e.message)
      end

      next unless volume_detach?(instance, volume)

      puts 'Volume test completed.'
      mount_success
    end

    if failures.empty?
      error_log(instance.name, "\nEncountered 0 failures. This is a perfect machine; creating image", true)
      create_image(instance)
      return true
    else
      error_log(instance.name, "\nEncountered #{failures.count} failures; continuing on the path to greatness...", true)
      return false
    end
  end

  def volume_attach?(instance, volume)
    volume_attached = lambda do |_|
      volume_attachments.any? do |attachment|
        attachment['volumeId'] == volume.id
      end
    end

    puts 'Attaching...'

    response = @compute_service.attach_volume(volume.id, instance.id, nil)
    vdev = response.body['volumeAttachment']['device']
    instance.wait_for(TIMEOUT_VOLUME_ATTACH, &volume_attached)

    sleep TIMEOUT_VOLUME_PERSIST

    return vdev if instance.instance_eval(&volume_attached)

    error_log(instance.name, "Failed to attach volume '#{volume.name}': Volume was unexpectedly detached.", true)
    false
  rescue Excon::Error => e
    puts 'Error attaching volume.'
    error_log(instance.name, e.message)
    false
  rescue Fog::Errors::TimeoutError
    error_log(instance.name, "Failed to attach volume '#{volume.name}': Operation timed out.", true)
    false
  end

  def with_ssh(instance, username, ssh_logger, &block)
    tries = 0
    begin
      Net::SSH.start(
        instance.addresses['public'].first['addr'],
        username,
        verbose: :info,
        paranoid: false,
        logger: ssh_logger,
        keys: [@ssh_private_key],
        &block
      )
    rescue Errno::ECONNREFUSED => e
      puts "Encountered #{e.message} while connecting to the instance."
      if tries < 3
        tries += 1
        puts "Initiating SSH attempt #{tries} in #{TIMEOUT_SSH_RETRY} seconds"
        sleep TIMEOUT_SSH_RETRY
        retry
      end
      error_log(instance.name, e.backtrace)
      error_log(instance.name, e.message)
      exit 1 # TODO: Don't crash when connection refused
    end
  end

  def volume_mount_unmount?(instance, vdev, username, ssh_logger)
    # commands to mount the volume
    mount = INSTANCE_VOLUME_MOUNT_POINT
    file_name = VOLUME_TEST_FILE_NAME
    file_contents = VOLUME_TEST_FILE_CONTENTS
    vdev += '1'

    commands = [
      ['sudo partprobe',                           ''],
      ["[ -d '#{mount}' ] || sudo mkdir #{mount}", ''],
      ["sudo mount #{vdev} #{mount}",              ''],
      ["sudo cat #{mount}/#{file_name}",           file_contents],
      ["sudo umount #{mount}",                     '']
    ]

    puts "Sleeping #{TIMEOUT_INSTANCE_STARTUP}s for OS startup..."
    sleep TIMEOUT_INSTANCE_STARTUP

    puts 'Mounting from inside the instance...'
    with_ssh(instance, username, ssh_logger) do |ssh|
      commands.each do |command, expected|
        result = ssh.exec!(command)
        # rubocop:disable Style/Next
        if result != expected
          error_log(
            instance.name,
            "Failure while running '#{command}':\n\texpected '#{expected}'\n\tgot '#{result.chomp}'",
            true
          )
          return false # returns from parent method
        end
      end
    end
    true
  end

  def log_partitions(instance, username, ssh_logger)
    puts 'Logging partition list and dmesg...'

    record_info_commands = [
      'cat /proc/partitions',
      'dmesg | tail -n 20'
    ]

    with_ssh(instance, username, ssh_logger) do |ssh|
      record_info_commands.each do |command|
        result = ssh.exec!(command)
        error_log(instance.name, "Ran '#{command}' and got '#{result}'")
      end
    end
  end

  def volume_detach?(instance, volume)
    puts 'Detaching...'
    instance.detach_volume(volume.id)
  rescue Excon::Error => e
    puts 'Failed to detach.'
    error_log(instance.name, e.message)
    false
  end
end

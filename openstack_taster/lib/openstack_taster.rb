# frozen_string_literal: true

require 'fileutils'
require 'date'
require 'excon'
require 'net/ssh'
require 'pry'

class OpenStackTaster
  INSTANCE_FLAVOR_NAME = 'm1.small'
  INSTANCE_NETWORK_NAME = 'public'
  INSTANCE_NAME_PREFIX = 'taster'
  INSTANCE_VOLUME_MOUNT_POINT = '/mnt/taster_volume'

  VOLUME_TEST_FILE_NAME = 'info'
  VOLUME_TEST_FILE_CONTENTS = nil # Contents would be something like 'test-vol-1 on openpower8.osuosl.bak'
  TIMEOUT_INSTANCE_CREATE = 20
  TIMEOUT_VOLUME_ATTACH = 10
  TIMEOUT_VOLUME_PERSIST = 20
  TIMEOUT_INSTANCE_TO_BE_CREATED = 20
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

  def initialize(
    compute_service,
    volume_service,
    image_service,
    network_service,
    ssh_keys,
    log_dir
  )
    @compute_service = compute_service
    @volume_service  = volume_service
    @image_service   = image_service
    @network_service = network_service

    @volumes = @volume_service.volumes
    @images  = @compute_service.images # FIXME: Images over compute service is deprecated
      .select { |image| SAFE_IMAGE_NAMES.include?(image.name) }.reverse

    puts "Tasting with #{@images.count} images and #{@volumes.count} volumes."

    @ssh_keypair     = ssh_keys[:keypair]
    @ssh_private_key = ssh_keys[:private_key]
    @ssh_public_key  = ssh_keys[:public_key] # REVIEW

    @session_id      = object_id
    @log_dir         = log_dir + "/#{@session_id}"

    @instance_flavor = @compute_service.flavors
      .select { |flavor|  flavor.name  == INSTANCE_FLAVOR_NAME  }.first
    @instance_network = @network_service.networks
      .select { |network| network.name == INSTANCE_NETWORK_NAME }.first
  end

  def taste_all
    puts "Starting session id #{@session_id}...\n"
    successes = @images.select(&method(:taste))
    failures = @images.reject do |image|
      successes.map(&:id).include?(image.id)
    end

    puts 'SUCCESS >'
    successes.each { |image| puts '    ', image.name }
    puts 'FAILURE >'
    failures.each { |image| puts '    ', image.name }
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

    error_log(
      instance_name,
      "Tasting #{image.name} as '#{instance_name}' with username '#{distro_user_name}'.\nBuilding...",
      true
    )

    instance = @compute_service.servers.create(
      name: instance_name,
      flavor_ref: @instance_flavor.id,
      image_ref: image.id,
      nics: [{ net_id: @instance_network.id }],
      key_name: @ssh_keypair
    )

    if instance.nil?
      error_log(instance_name, 'Failed to create instance.', true)
      return false
    end

    instance.wait_for(TIMEOUT_INSTANCE_TO_BE_CREATED) { ready? }

    error_log(instance.name, "Sleeping #{TIMEOUT_INSTANCE_STARTUP} seconds for OS startup...", true)
    sleep TIMEOUT_INSTANCE_STARTUP

    error_log(instance.name, "\nTesting for instance '#{instance.id}'.", true)

    ssh_logger = Logger.new('logs/' + instance.name + '_ssh_log')

    return test_volumes(instance, distro_user_name, ssh_logger)
  rescue Fog::Errors::TimeoutError
    puts 'Instance creation timed out.'
    error_log(instance.name, "Instance fault: #{instance.fault}")
    return false
  rescue Interrupt
    puts "\nCaught interrupt"
    puts "\nYou are exiting session #{@session_id}\n"
    raise SystemExit
  ensure
    if instance
      puts "Destroying instance for session #{@session_id}."
      instance.destroy
    end
  end

  def error_log(filename, message, dup_stdout = false)
    puts message if dup_stdout

    FileUtils.mkdir_p(@log_dir) unless Dir.exist?(@log_dir)
    File.open("#{@log_dir}/#{filename}.log", 'a') do |file|
      file.puts(message)
    end
  end

  def get_image_name(instance)
    @image_service
      .get_image_by_id(instance.image['id'])
      .body['name']
  end

  def create_image(instance)
    image_name = [
      instance.name,
      get_image_name(instance)
    ].join('_')

    response = instance.create_image(image_name)
    image_id = response.body['image']['id']

    @image_service.images
      .find_by_id(image_id)
      .wait_for { status == 'active' }
  end

  def test_volumes(instance, username, ssh_logger)
    mount_failures = @volumes.reject do |volume|
      if volume.attachments.any?
        error_log(instance.name, "Volume '#{volume.name}' is already in an attached state; skipping.", true)
        next
      end

      unless volume_attach?(instance, volume)
        error_log("Volume '#{volume.name}' failed to attach. Creating image...", true)
        create_image(instance)
        return false # Returns from test_volumes
      end

      volume_mount_unmount?(instance, username, ssh_logger, volume)
    end

    detach_failures = @volumes.reject do |volume|
      volume_detach?(instance, volume)
    end

    if mount_failures.empty? && detach_failures.empty?
      error_log(instance.name, "\nEncountered 0 failures. Not creating image...", true)
      true
    else
      error_log(
        instance.name,
        "\nEncountered #{mount_failures.count} mount failures and #{detach_failures.count} detach failures.",
        true
      )
      error_log(instance.name, "\nEncountered failures. Creating image...", true)
      create_image(instance)
      false
    end
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

  def volume_attach?(instance, volume)
    volume_attached = lambda do |_|
      volume_attachments.any? do |attachment|
        attachment['volumeId'] == volume.id
      end
    end

    error_log(instance.name, "Attaching volume '#{volume.name}' (#{volume.id})...", true)
    instance.wait_for(TIMEOUT_VOLUME_ATTACH, &volume_attached)

    error_log(instance.name, "Sleeping #{TIMEOUT_VOLUME_PERSIST} seconds for attachment persistance...", true)
    sleep TIMEOUT_VOLUME_PERSIST

    return true if instance.instance_eval(&volume_attached)

    error_log(instance.name, "Failed to attach '#{volume.name}': Volume was unexpectedly detached.", true)
    false
  rescue Excon::Error => e
    puts 'Error attaching volume, check log for details.'
    error_log(instance.name, e.message)
    false
  rescue Fog::Errors::TimeoutError
    error_log(instance.name, "Failed to attach '#{volume.name}': Operation timed out.", true)
    false
  end

  def volume_mount_unmount?(instance, username, ssh_logger, volume)
    mount = INSTANCE_VOLUME_MOUNT_POINT
    file_name = VOLUME_TEST_FILE_NAME
    file_contents = VOLUME_TEST_FILE_CONTENTS
    vdev = @volume_service.volumes.find_by_id(volume.id)
      .attachments.first['device']
    vdev << '1'

    log_partitions(instance, username, ssh_logger)

    commands = [
      ["echo -e \"127.0.0.1\t$HOSTNAME\" | sudo tee -a /etc/hosts", nil], # to fix problems with sudo and DNS resolution
      ['sudo partprobe -s',                        nil],
      ["[ -d '#{mount}' ] || sudo mkdir #{mount}", ''],
      ["sudo mount #{vdev} #{mount}",              ''],
      ["sudo cat #{mount}/#{file_name}",           file_contents],
      ["sudo umount #{mount}",                     '']
    ]

    error_log(instance.name, "Mounting volume '#{volume.name}' (#{volume.id})...", true)

    error_log(instance.name, 'Mounting from inside the instance...', true)
    with_ssh(instance, username, ssh_logger) do |ssh|
      commands.each do |command, expected|
        result = ssh.exec!(command).chomp
        if expected.nil?
          error_log(instance.name, "#{command} yielded '#{result}'")
        elsif result != expected
          error_log(
            instance.name,
            "Failure while running '#{command}':\n\texpected '#{expected}'\n\tgot '#{result}'",
            true
          )
          return false # returns from volume_mount_unmount?
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
    error_log(instance.name, "Detaching #{volume.name}.", true)
    instance.detach_volume(volume.id)
  rescue Excon::Error => e
    puts 'Failed to detach. check log for details.'
    error_log(instance.name, e.message)
    false
  end
end

# frozen_string_literal: true

require 'date'
require 'excon'
require 'pry'

class OpenStackTaster
  IMAGE_NAME_PREFIX = 'openstack-taster'
  SAFE_IMAGE_NAMES = ['Fedora 23 BE', 'Ubuntu 16.04 LE'].freeze
  INSTANCE_FLAVOR_NAME = 'm1.tiny'
  INSTANCE_NETWORK_NAME = 'public'
  INSTANCE_NAME_PREFIX = 'taster'
  INSTANCE_VOLUME_DEVICE_NAME = '/dev/vdz'
  TIME_SLUG_FORMAT = '%Y%m%d_%H%M%S'

  def initialize(compute_service, volume_service, image_service, network_service, fixed_ip)
    @compute_service = compute_service
    @volume_service  = volume_service
    @image_service   = image_service
    @network_service = network_service

    @volumes = @volume_service.volumes
    @images  = @image_service.images # FIXME
    @images  = @compute_service.images # .select { |image| # FIXME
    #  image.name.start_with?(IMAGE_NAME_PREFIX)
    # }

    @fixed_ip = fixed_ip
    @instance_flavor = @compute_service.flavors
      .select { |flavor|  flavor.name  == INSTANCE_FLAVOR_NAME  }.first
    @instance_network = @network_service.networks
      .select { |network| network.name == INSTANCE_NETWORK_NAME }.first
  end

  def taste_all
    # @images.each(&method(:taste))
    @images
      .select { |image| SAFE_IMAGE_NAMES.include?(image.name) }
      .tap { |images| raise 'No images found with safe names' if images.empty? }
      .each(&method(:taste))
  end

  def taste(image)
    # truncate downcased name at first non-alpha char
    distro_user_name = image.name.downcase.gsub(/[^a-z].*$/, '')
    instance_name = name_instance(distro_user_name)
    puts "\nTasting #{image.name} as '#{instance_name}' with username '#{distro_user_name}'"

    instance = @compute_service.servers.create(
      name: instance_name,
      flavor_ref: @instance_flavor.id,
      image_ref: image.id,
      fixed_ip: @fixed_ip, # FIXME
      networks: @instance_network.id # REVIEW
    )

    instance.wait_for { ready? }
    test_attach_volumes(instance)
  ensure
    puts 'Destroying instance.'
    instance.destroy
  end

  def name_instance(distro)
    time_slug = Time.new.strftime(TIME_SLUG_FORMAT)
    "#{INSTANCE_NAME_PREFIX}-#{time_slug}-#{distro}"
  end

  def test_attach_volumes(instance)
    @volumes.each do |volume|
      puts "Testing volume '#{volume.name}'"
      next unless volume_attach?(instance, volume)

      unless volume_detach?(instance, volume)
        puts 'Creating image...'
        response = instance.create_image(instance.name)
        image = @image_service.images.find_by_id(response.body['image']['id'])
        image.wait_for { status == 'active' }
        next
      end
      puts "Volume '#{volume.name}' successful."
    end
  end

  def volume_attach?(instance, volume)
    volume_attached = lambda do |_|
      volume_attachments.any? do |attachment|
        attachment['volumeId'] == volume.id
      end
    end

    puts 'Attaching...'
    instance.attach_volume(volume.id, INSTANCE_VOLUME_DEVICE_NAME)
    instance.wait_for(&volume_attached)

    sleep 10

    return true if instance.instance_eval(&volume_attached)

    puts 'Failed to attach volume'
    error_log(instance, 'Volume mounted and immediately unmounted.')
    false

  rescue Excon::Error => e
    puts "Failed to attach '#{volume.name}'."
    error_log(instance, e.message)
    false

  rescue Fog::Errors::TimeoutError
    error_log(instance, 'Failed to attach volume: timed out')
    false
  end

  def volume_detach?(instance, volume)
    puts 'Detaching...'
    instance.detach_volume(volume.id)

  rescue Excon::Error => e
    puts "Failed to detach '#{volume.name}'."
    error_log(instance, e.message)
    false
  end

  def error_log(instance, message)
    File.open(instance.name, 'a') do |file|
      file.puts(message)
    end
  end
end

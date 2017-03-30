# frozen_string_literal: true

require 'date'

class OpenStackTaster
  IMAGE_NAME_PREFIX = 'osl'
  INSTANCE_FLAVOR_NAME = 'm1.tiny'
  INSTANCE_NETWORK_NAME = 'public'
  INSTANCE_NAME_PREFIX = 'taster'
  TIME_SLUG_FORMAT = '%Y%m%d_%H%M%S'

  def initialize(compute_service, network_service, fixed_ip)
    @compute_service = compute_service
    @network_service = network_service

    @images = @compute_service.images
    # @images = @compute_service.images.select { |image| image.name.start_with? IMAGE_NAME_PREFIX }
    @volumes = @compute_service.volumes.all

    @fixed_ip = fixed_ip
    @instance_flavor = @compute_service
      .flavors
      .select { |flavor| flavor.name == INSTANCE_FLAVOR_NAME }
      .first
    @instance_network = @network_service
      .networks
      .select { |network| network.name == INSTANCE_NETWORK_NAME }
      .first
  end

  def taste_all
    # @images.each(&method(:taste))
    @images
      .select { |image| ['Fedora 23 BE', 'Ubuntu 16.04 LE'].include?(image.name) }
      .tap { |images| raise 'No images found with safe names' if images.empty? }
      .each(&method(:taste))
  end

  def taste(image)
    # truncate downcased name at first non-alpha char
    distro_name = image.name.downcase.gsub(/[^a-z].*$/, '')
    instance_name = name_instance(distro_name)
    puts "\nTasting #{image.name} as '#{instance_name}' with username '#{distro_name}'"

    instance = fetch_running(
      @compute_service.servers.create(
        name: instance_name,
        flavor_ref: @instance_flavor.id,
        image_ref: image.id,
        fixed_ip: @fixed_ip, # FIXME
        networks: @instance_network.id # REVIEW
      )
    )

    if volume_failures?(instance)
      instance.shelve
    else
      puts 'No failures found, destroying instance.'
      instance.destroy
    end
  end

  def name_instance(distro)
    time_slug = Time.new.strftime(TIME_SLUG_FORMAT)
    "#{INSTANCE_NAME_PREFIX}-#{time_slug}-#{distro}"
  end

  def fetch_running(instance) # OPTIMIZE
    print 'Building instance'
    while instance.state != 'ACTIVE'
      sleep 1
      print '.'
      instance = @compute_service.servers.get(instance.id)
    end
    print "\n"
    instance
  end

  def volume_failures?(instance)
    @volumes.any? do |volume|
      instance_volume_fails?(instance, volume)
    end
  end

  # rubocop:disable UnusedMethodArgument
  def instance_volume_fails?(instance, volume)
    puts "Testing volume '#{volume.name}'"
    # TODO
    # print if volume fails to mount or detach
    # return (mount_fail? || detach_fail?)
    false
  end
end

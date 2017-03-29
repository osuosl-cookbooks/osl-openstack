# frozen_string_literal: true

require 'date'

class OpenStackTaster
  INSTANCE_FLAVOR_NAME = 'm1.tiny'
  INSTANCE_NAME_PREFIX = 'taster'
  TIME_SLUG_FORMAT = '%Y%m%d_%H%M%S'

  attr_accessor :images, :volumes

  def initialize(openstack, fixed_ip)
    @openstack = openstack
    @fixed_ip = fixed_ip
    @images = @openstack.images
    @volumes = @openstack.volumes.all
    @instance_flavor = @openstack
      .flavors
      .select { |flavor| flavor.name = INSTANCE_FLAVOR_NAME }
      .first
  end

  def taste_all
    # @images.each(&method(:taste))
    taste(@images.first)
  end

  def taste(image)
    # truncate downcased name at first non-alpha char
    distro_name = image.name.downcase.gsub(/[^a-z].*$/, '')
    puts "\nTasting #{image.name} with username '#{distro_name}'"

    instance = @openstack.servers.create(
      name: name_instance(distro_name),
      flavor_ref: @instance_flavor.id,
      image_ref: image.id
    )

    failures = @volumes.any? do |volume|
      instance_volume_fails?(instance, volume)
    end

    instance.shelve
    instance.destroy unless failures
  end

  def name_instance(distro)
    time_slug = Time.new.strftime(TIME_SLUG_FORMAT)
    "#{INSTANCE_NAME_PREFIX}-#{time_slug}-#{distro}"
  end

  def instance_volume_fails?(instance, volume)
    # print if volume fails to mount or detach
    # return (mount_fail? || detach_fail?)
    false
  end
end

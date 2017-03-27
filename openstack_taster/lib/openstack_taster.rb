# frozen_string_literal: true

class OpenStackTaster
  INSTANCE_FLAVOR = 'm1.tiny'

  attr_accessor :images, :volumes

  def initialize(openstack, fixed_ip)
    @openstack = openstack
    @fixed_ip = fixed_ip
    @images = @openstack.images
    @volumes = @openstack.volumes.all
  end

  def taste_all
    @images.each { |image| taste(image) }
  end

  def taste(image)
    puts "Tasting #{image.name}"

    username = image.name.downcase.gsub(/[^a-z].*$/, '')
    puts "Username will be #{username}"

    puts <<-CREATE
instance = @openstack.servers.create(
  name: 'test-instance',
  flavor_ref: INSTANCE_FLAVOR,
  image_ref: image.id
)
    CREATE

    failures = @volumes.any? do |volume|
      instance_volume_fails?(instance, volume)
    end

    # shut down instance

    puts 'instance.destroy unless failures'
  end

  def instance_volume_fails?(instance, volume)
    # print if volume fails to mount or detach
    # return (mount_fail? || detach_fail?)
    false
  end
end

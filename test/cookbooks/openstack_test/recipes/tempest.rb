include_recipe 'openstack-integration-test::setup'

edit_resource(:python_virtualenv, '/opt/tempest-venv') do
  system_site_packages true
  setuptools_version '40.0.0'
  wheel_version '0.31.1'
end

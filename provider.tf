terraform {
  required_providers {
    openstack = {
      source = "terraform-provider-openstack/openstack"
      version = "~> 3.0"
    }
    null = {
      source = "hashicorp/null"
      version = "~> 3.2"
    }
    tls = {
      source = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# A reject from the API's connection throttle is retried rather than failing the build
provider "openstack" {
  max_retries = 5
}

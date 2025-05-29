provider "openstack" {
  cloud = "mycloud"  # this refers to clouds.yaml
}

resource "openstack_compute_keypair_v2" "default" {
  name       = "terraform-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "openstack_compute_instance_v2" "demo" {
  name            = "terraform-vm"
  image_name      = var.image_name
  flavor_name     = var.flavor_name
  key_pair        = openstack_compute_keypair_v2.default.name
  security_groups = ["default"]

  network {
    name = var.network_name
  }
}

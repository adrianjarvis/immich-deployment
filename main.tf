terraform {
  required_version = ">= 1.2"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 2.1.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.3"
    }
  }
}

variable "vault_password" {
  type = string
  description = "The ansible vault password"
  sensitive = true
}

variable "public_key" {
  type = string
  description = "Path to your public ssh key file to use for SSH access to the server."
  
}

variable "public_ip" {
  type = string
  description = "The floating IP to associate to the immish server"
}

data "openstack_networking_router_v2" "router" {
  name = "border-router"
}

data "openstack_images_image_v2" "ubuntu" {
  name        = "ubuntu-26.04-x86_64"
  most_recent = true
}

data "http" "ip_info" {
  url = "https://api.ipify.org?format=json"
}

locals {
  remote_ip = jsondecode(data.http.ip_info.response_body)["ip"]
}

resource "openstack_compute_keypair_v2" "keypair" {
  name       = "immich-keypair"
  public_key = file(var.public_key)
}

resource "openstack_networking_secgroup_v2" "security_group" {
  name        = "immich-sg"
  description = "Security Group to allow access to Immich"
}

resource "openstack_networking_secgroup_rule_v2" "sg_rule_1" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = join("/", [local.remote_ip, "32"])
  security_group_id = openstack_networking_secgroup_v2.security_group.id
}

resource "openstack_networking_secgroup_rule_v2" "sg_rule_2" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.security_group.id
}

resource "openstack_networking_secgroup_rule_v2" "sg_rule_3" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.security_group.id
}

resource "openstack_networking_network_v2" "network" {
  name           = "immich-net"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "subnet" {
  name       = "immich-subnet"
  network_id = openstack_networking_network_v2.network.id
  cidr       = "192.168.199.0/24"
  ip_version = 4
}

resource "openstack_networking_router_interface_v2" "router_interface" {
  router_id = data.openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.subnet.id
}

resource "openstack_networking_floatingip_v2" "floatip" {
  pool = "public-net"
}

resource "openstack_blockstorage_volume_v3" "bootdisk" {
    name = "immich-root-disk"
    size = 15
    volume_type = "b1.sr-r3-nvme-1000"
    image_id = data.openstack_images_image_v2.ubuntu.id
}

resource "openstack_blockstorage_volume_v3" "appdisk" {
    name = "immich-app-disk"
    size = 100
    volume_type = "b1.sr-r3-nvme-1000"
}

resource "openstack_compute_instance_v2" "server" {
  name            = "immich-server"
  flavor_name       = "c1.c4r8"
  key_pair        = openstack_compute_keypair_v2.keypair.name
  security_groups = [openstack_networking_secgroup_v2.security_group.name]
  user_data       = templatefile("cloud-init.tftbl", 
    { vault_pass = var.vault_password } 
    )

  block_device {
    delete_on_termination = true
    uuid = openstack_blockstorage_volume_v3.bootdisk.id
    source_type = "volume"
    destination_type = "volume"
    boot_index = 0
  }

  block_device {
    delete_on_termination = false
    uuid = openstack_blockstorage_volume_v3.appdisk.id
    source_type = "volume"
    destination_type = "volume"
    boot_index = -1
  }

  network {
    name = openstack_networking_network_v2.network.name
  }
}

data "openstack_networking_port_v2" "port" {
  device_id  = openstack_compute_instance_v2.server.id
  network_id = openstack_networking_network_v2.network.id
}

resource "openstack_networking_floatingip_associate_v2" "fip_vm" {
  floating_ip = var.public_ip
  port_id     = data.openstack_networking_port_v2.port.id
}

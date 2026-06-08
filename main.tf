variable "db_password" {
  type = string
  description = "The password to use for the Postgres DB used by Immich"
  default = "postgres"
  sensitive = true
}

variable "public_key" {
  type = string
  description = "Path to your public ssh key file to use for SSH access to the server."
  
}

variable "remote_ip" {
  type = string
  description = "IP address that you will connect to the Immisch server from"
}

data "openstack_compute_flavor_v2" "flavor" {
    name = "c1.c4r8"
}

data "openstack_images_image_v2" "ubuntu" {
  name        = "ubuntu-26.04-x86_64"
  most_recent = true
}

data "openstack_networking_router_v2" "router" {
  name = "border-router"
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
  remote_ip_prefix  = join("/", [var.remote_ip, "32"])
  security_group_id = openstack_networking_secgroup_v2.security_group.id
}

resource "openstack_networking_secgroup_rule_v2" "sg_rule_2" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 2283
  port_range_max    = 2283
  remote_ip_prefix  = join("/", [var.remote_ip, "32"])
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
    size = 80
    volume_type = "b1.sr-r3-nvme-1000"
    image_id = data.openstack_images_image_v2.ubuntu.id
}

resource "openstack_compute_instance_v2" "server" {
  name            = "immich-server"
  flavor_id       = data.openstack_compute_flavor_v2.flavor.id
  key_pair        = openstack_compute_keypair_v2.keypair.name
  security_groups = [openstack_networking_secgroup_v2.security_group.name]
  user_data       = templatefile("cloud-init.tftbl", { db_password = var.db_password } )

  block_device {
    delete_on_termination = false
    uuid = openstack_blockstorage_volume_v3.bootdisk.id
    source_type = "volume"
    destination_type = "volume"
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
  floating_ip = openstack_networking_floatingip_v2.floatip.address
  port_id     = data.openstack_networking_port_v2.port.id
}

output "server_ip" {
  value = openstack_networking_floatingip_v2.floatip.address
}
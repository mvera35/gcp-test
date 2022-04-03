provider "google" {
  credentials = file("./credentials-gcp.json")
  project = file("./project-id.txt")
  region  = "us-west4"
  zone    = "us-west4-b"
}

resource "google_compute_network" "custom-vpc" {
  name = "custom-vpc"
  auto_create_subnetworks = "false"
}

resource "google_compute_firewall" "firewall-ssh" {
  name    = "firewall-externalssh"
  network = google_compute_network.custom-vpc.name
  allow {
    protocol = "tcp"
    ports    = ["22","80","443"]
  }
  allow {
    protocol = "icmp"
  }
  allow { //RDP
    protocol = "tcp"
    ports = ["3389"]
  }

  source_ranges = ["0.0.0.0/0"]   
  target_tags   = ["externalssh"]
  depends_on = [google_compute_network.custom-vpc]
}

resource "google_compute_address" "static" {
  name = "public-address"
  project = file("./project-id.txt")
  depends_on = [ google_compute_firewall.firewall-ssh ]
}

resource "google_compute_subnetwork" "public-subnet"{
  name = "public-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region  = "us-west4"
  network = google_compute_network.custom-vpc.id
  depends_on = [google_compute_network.custom-vpc]
}

resource "google_compute_subnetwork" "private-subnet"{
  name = "private-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region  = "us-west4"
  network = google_compute_network.custom-vpc.id
  depends_on = [google_compute_network.custom-vpc]
}

resource "google_compute_instance_group_manager" "private-servers" {
   name = "private-servers"
   base_instance_name = "private"
   
   version {
     instance_template = google_compute_instance_template.server-template.id
   }

   target_size = 2
   depends_on = [google_compute_instance_template.server-template]

}

resource "google_compute_instance_template" "server-template" {
  name = "server-template"
  description = "Plantilla usada para montar servidores sencillos"
  machine_type = "f1-micro"
  tags = ["externalssh"]

  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete = true
    disk_size_gb = 10
    boot = true
  }

  network_interface {
    network = "custom-vpc"
    subnetwork = "private-subnet"
    access_config {}
  }

  metadata_startup_script = "sudo apt update -y; sudo apt install nginx -y; hostname -I | awk '{print $1}' > index.html; sudo cp index.html /var/www/html/"

  depends_on = [google_compute_subnetwork.private-subnet, google_compute_subnetwork.public-subnet]
  metadata = {
    ssh-keys = "mvera:${file("/home/mvera/.ssh/id_rsa.pub")}"
  }

}
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

resource "google_compute_subnetwork" "public-subnet"{
  name = "public-subnet"
  ip_cidr_range = "10.0.1.0/24"
  network = google_compute_network.custom-vpc.id
}

resource "google_compute_subnetwork" "private-subnet"{
  name = "private-subnet"
  ip_cidr_range = "10.0.0.0/24"
  private_ip_google_access = true
  network = google_compute_network.custom-vpc.id
}

resource "google_compute_instance_template" "server-template" {
  name = "server-template"
  description = "Plantilla usada para montar servidores sencillos"
  machine_type = "f1-micro"

  disk {
    source_image = "debian-cloud/debian-11"
    auto_delete = true
    disk_size_gb = 10
    boot = true
  }

  network_interface {
    network = "custom-vpc"
    subnetwork = "private-subnet"
  }

  depends_on = [google_compute_subnetwork.private-subnet, google_compute_subnetwork.public-subnet]
}

resource "google_compute_instance_from_template" "public-server-1" {
  name = "public-server-1"

  source_instance_template = google_compute_instance_template.server-template.id

  network_interface {
    network = "custom-vpc"
    subnetwork = "public-subnet"
  }

  depends_on = [google_compute_instance_template.server-template]
}
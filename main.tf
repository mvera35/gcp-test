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
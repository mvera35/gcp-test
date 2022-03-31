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

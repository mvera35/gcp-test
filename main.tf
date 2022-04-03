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

   named_port {
     name = "http"
     port = "80"
   }

   target_size = 2
   depends_on = [google_compute_instance_template.server-template]

}

// NAT Router
resource "google_compute_address" "nat-ip" {
  name = "nat-ip"
  project = file("./project-id.txt")
}

resource "google_compute_router" "nat-router" {
  name = "nat-router"
  network = google_compute_network.custom-vpc.name
  depends_on = [google_compute_network.custom-vpc]
}

resource "google_compute_router_nat" "nat-gateway" {
  name = "nat-gateway"
  router = google_compute_router.nat-router.name
  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips = [ google_compute_address.nat-ip.self_link ]
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES" 
  depends_on = [ google_compute_address.nat-ip ]
}

output "nat_ip_address" {
  value = google_compute_address.nat-ip.address
}
// NAT Router

// Balanceador de Cargas

resource "google_compute_global_forwarding_rule" "global_forwarding_rule" {
  name = "global-forwarding-rule"
  project = file("./project-id.txt")
  target = google_compute_target_http_proxy.target_http_proxy.self_link
  port_range = "80"
}

resource "google_compute_target_http_proxy" "target_http_proxy" {
  name = "proxy"
  project = file("./project-id.txt")
  url_map = google_compute_url_map.url_map.self_link
}

resource "google_compute_backend_service" "backend_service" {
  name = "backend-service"
  project = file("./project-id.txt")
  port_name = "http"
  protocol = "HTTP"
  health_checks =["${google_compute_health_check.healthcheck.self_link}"]
  backend {
    group = google_compute_instance_group_manager.private-servers.instance_group
    balancing_mode = "RATE"
    max_rate_per_instance = 100
  }
}

resource "google_compute_health_check" "healthcheck" {
  name = "healthcheck"
  timeout_sec = 1
  check_interval_sec = 1
  http_health_check {
    port = 80
  }
}

resource "google_compute_url_map" "url_map" {
  name = "load-balancer"
  project = file("./project-id.txt")
  default_service = google_compute_backend_service.backend_service.self_link
}

output "load-balancer-ip-address" {
  value = google_compute_global_forwarding_rule.global_forwarding_rule.ip_address
}

// Balanceador de Cargas

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
  }

  metadata_startup_script = "sudo apt update -y; sudo apt install nginx -y; hostname -I | awk '{print $1}' > index.html; sudo cp index.html /var/www/html/"

  depends_on = [google_compute_subnetwork.private-subnet, google_compute_subnetwork.public-subnet]
}
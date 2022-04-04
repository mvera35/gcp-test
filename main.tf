provider "google" {
  credentials = file("${var.credentials_gcp}")
  project = file("${var.project_id}")
  region  = "${var.project_region}"
  zone    = "${var.project_zone}"
}

resource "google_compute_network" "custom-vpc" {
  name = "${var.project_name}-custom-vpc"
  auto_create_subnetworks = "false"
}

resource "google_compute_firewall" "firewall-ssh" {
  name    = "${var.project_name}-firewall-externalssh"
  network = google_compute_network.custom-vpc.name
  allow {
    protocol = "tcp"
    ports    = ["80","443"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]   
  target_tags   = ["externalssh"]
  depends_on = [google_compute_network.custom-vpc]
}

// Subredes pública y privada
resource "google_compute_subnetwork" "public-subnet"{
  name = "${var.project_name}-public-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region  = "${var.project_region}"
  network = google_compute_network.custom-vpc.id
  depends_on = [google_compute_network.custom-vpc]
}

resource "google_compute_subnetwork" "private-subnet"{
  name = "${var.project_name}-private-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region  = "${var.project_region}"
  network = google_compute_network.custom-vpc.id
  depends_on = [google_compute_network.custom-vpc]
}
// Subredes pública y privada

// Política de autoescalado
resource "google_compute_autoscaler" "scale-in" {
  name   = "${var.project_name}-autoscaler"
  zone   = "${var.project_zone}"
  target = google_compute_instance_group_manager.private-servers.id

  autoscaling_policy {
    max_replicas    = 3
    min_replicas    = 2
    scale_in_control {
      max_scaled_in_replicas {
        percent = 100
      }
      time_window_sec = 60
    }
    cpu_utilization { // scale in : CPU utilization > 40%
      target = 0.4 
    }
  }
}
// Política de autoescalado

// Compute instances
resource "google_compute_instance_group_manager" "private-servers" {
   name = "${var.project_name}-private-servers"
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
// Compute instances

// NAT Router
resource "google_compute_address" "nat-ip" {
  name = "${var.project_name}-nat-ip"
  project = file("${var.project_id}")
}

resource "google_compute_router" "nat-router" {
  name = "${var.project_name}-nat-router"
  network = google_compute_network.custom-vpc.name
  depends_on = [google_compute_network.custom-vpc]
}

resource "google_compute_router_nat" "nat-gateway" {
  name = "${var.project_name}-nat-gateway"
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
  name = "${var.project_name}-global-forwarding-rule"
  project = file("${var.project_id}")
  target = google_compute_target_http_proxy.target_http_proxy.self_link
  port_range = "80"
}

resource "google_compute_target_http_proxy" "target_http_proxy" {
  name = "${var.project_name}-proxy"
  project = file("${var.project_id}")
  url_map = google_compute_url_map.url_map.self_link
}

resource "google_compute_backend_service" "backend_service" {
  name = "${var.project_name}-backend-service"
  project = file("${var.project_id}")
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
  name = "${var.project_name}-healthcheck"
  timeout_sec = 1
  check_interval_sec = 1
  http_health_check {
    port = 80
  }
}

resource "google_compute_url_map" "url_map" {
  name = "${var.project_name}-load-balancer"
  project = file("${var.project_id}")
  default_service = google_compute_backend_service.backend_service.self_link
}

output "load-balancer-ip-address" {
  value = google_compute_global_forwarding_rule.global_forwarding_rule.ip_address
}

// Balanceador de Cargas

// Plantilla del servidor
resource "google_compute_instance_template" "server-template" {
  name = "${var.project_name}-server-template"
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
    network = google_compute_network.custom-vpc.name
    subnetwork = google_compute_subnetwork.private-subnet.name
  }
  //Instalación de nginx
  metadata_startup_script = "sudo apt update -y; sudo apt install nginx -y; hostname -I | awk '{print $1}' > index.html; sudo cp index.html /var/www/html/"

  depends_on = [google_compute_subnetwork.private-subnet, google_compute_subnetwork.public-subnet]
}
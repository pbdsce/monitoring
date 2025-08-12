
set -e

echo "Starting Production Deployment..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    print_error "Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

print_status "Checking prerequisites..."

# Check for .env file
if [ ! -f ".env" ]; then
    print_warning ".env file not found!"
    print_status "Creating .env file from template..."
    
    if [ -f "env.example" ]; then
        cp env.example .env
        print_warning " Please edit .env file with your actual values before continuing!"
        print_status "Required variables to update:"
        echo "  - GRAFANA_PASSWORD: Set a strong password"
        echo "  - WEBSITE_SERVER_IP: Your website server IP address"
        echo "  - WEBSITE_DOMAIN: Your website domain"
        echo ""
        print_status "After updating .env, run this script again."
        exit 1
    else
        print_error "env.example not found! Cannot create .env file."
        exit 1
    fi
fi

# Load environment variables
print_status "Loading environment variables..."
source .env

# Validate required environment variables
if [ -z "$GRAFANA_PASSWORD" ] || [ "$GRAFANA_PASSWORD" = "your_secure_password_here" ]; then
    print_error "GRAFANA_PASSWORD not set in .env file"
    exit 1
fi

if [ -z "$WEBSITE_SERVER_IP" ] || [ "$WEBSITE_SERVER_IP" = "your_website_server_ip" ]; then
    print_error "WEBSITE_SERVER_IP not set in .env file"
    exit 1
fi

if [ -z "$WEBSITE_DOMAIN" ] || [ "$WEBSITE_DOMAIN" = "your-website-domain.com" ]; then
    print_error "WEBSITE_DOMAIN not set in .env file"
    exit 1
fi

print_status "Environment variables validated!"

# Create necessary directories
print_status "Creating directories..."
mkdir -p grafana/provisioning/datasources
mkdir -p grafana/provisioning/dashboards
mkdir -p grafana/dashboards

# Check if configuration files exist
if [ ! -f "docker-compose.yml" ]; then
    print_error "docker-compose.yml not found!"
    exit 1
fi

if [ ! -f "prometheus.yml" ]; then
    print_error "prometheus.yml not found!"
    exit 1
fi

print_status "Configuration files found!"

# Copy production configs (no longer needed since we have single files)
print_status "Setting up configuration..."

# Check if Grafana provisioning files exist
if [ ! -f "grafana/provisioning/datasources/prometheus.yml" ]; then
    print_warning "Grafana datasource configuration not found. Creating default..."
    cat > grafana/provisioning/datasources/prometheus.yml << EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
    editable: true
    uid: PB_PROM
EOF
fi

if [ ! -f "grafana/provisioning/dashboards/dashboard.yml" ]; then
    print_warning "Grafana dashboard configuration not found. Creating default..."
    cat > grafana/provisioning/dashboards/dashboard.yml << EOF
apiVersion: 1
providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    updateIntervalSeconds: 10
    allowUiUpdates: true
    options:
      path: /var/lib/grafana/dashboards
EOF
fi

# Check if dashboard JSON exists
if [ ! -f "grafana/dashboards/pb-website-dashboard.json" ]; then
    print_warning "Dashboard JSON not found. Please ensure pb-website-dashboard.json is in grafana/dashboards/"
fi

# Set proper permissions
print_status "Setting file permissions..."
chmod 644 prometheus.yml
chmod 644 grafana/provisioning/datasources/prometheus.yml
chmod 644 grafana/provisioning/dashboards/dashboard.yml
chmod 600 .env

# Stop any existing containers
print_status "Stopping existing containers..."
docker-compose --env-file .env down 2>/dev/null || true

# Pull latest images
print_status "Pulling latest Docker images..."
docker-compose --env-file .env pull

# Start the services
print_status "Starting monitoring stack..."
docker-compose --env-file .env up -d

# Wait for services to start
print_status "Waiting for services to start..."
sleep 30

# Check service status
print_status "Checking service status..."
docker-compose --env-file .env ps

# Check if services are healthy
print_status "Checking service health..."

# Check Prometheus
if curl -s http://localhost:${PROMETHEUS_PORT:-9090}/-/healthy > /dev/null; then
    print_status "Prometheus is healthy"
else
    print_warning "Prometheus health check failed"
fi

# Check Grafana
if curl -s http://localhost:${GRAFANA_PORT:-3000}/api/health > /dev/null; then
    print_status "Grafana is healthy"
else
    print_warning "Grafana health check failed"
fi

print_status "Deployment completed!"

echo
echo "Monitoring Stack URLs:"
echo "  Grafana Dashboard: http://${MONITORING_SERVER_IP:-localhost}:${GRAFANA_PORT:-3000} (admin/${GRAFANA_PASSWORD})"
echo "  Prometheus: http://${MONITORING_SERVER_IP:-localhost}:${PROMETHEUS_PORT:-9090}"
echo

print_status "Configuration Summary:"
echo "  Website Server IP: ${WEBSITE_SERVER_IP}"
echo "  Website Domain: ${WEBSITE_DOMAIN}"
echo "  Grafana Port: ${GRAFANA_PORT:-3000}"
echo "  Prometheus Port: ${PROMETHEUS_PORT:-9090}"
echo

print_status "To view logs: docker-compose --env-file .env logs -f"
print_status "To stop services: docker-compose --env-file .env down"
print_status "To restart services: docker-compose --env-file .env restart"

echo
print_status "Production deployment script completed!"


set -e

echo "Starting Production Deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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

# Create necessary directories
print_status "Creating directories..."
mkdir -p grafana/provisioning/datasources
mkdir -p grafana/provisioning/dashboards
mkdir -p grafana/dashboards

# Check if configuration files exist
if [ ! -f "docker-compose.prod.yml" ]; then
    print_error "docker-compose.prod.yml not found!"
    exit 1
fi

if [ ! -f "prometheus.prod.yml" ]; then
    print_error "prometheus.prod.yml not found!"
    exit 1
fi

print_status "Configuration files found!"

# Copy production configs
print_status "Setting up production configuration..."
cp prometheus.prod.yml prometheus.yml

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

# Stop any existing containers
print_status "Stopping existing containers..."
docker-compose -f docker-compose.prod.yml down 2>/dev/null || true

# Pull latest images
print_status "Pulling latest Docker images..."
docker-compose -f docker-compose.prod.yml pull

# Start the services
print_status "Starting monitoring stack..."
docker-compose -f docker-compose.prod.yml up -d

# Wait for services to start
print_status "Waiting for services to start..."
sleep 30

# Check service status
print_status "Checking service status..."
docker-compose -f docker-compose.prod.yml ps

# Check if services are healthy
print_status "Checking service health..."

# Check Prometheus
if curl -s http://localhost:9090/-/healthy > /dev/null; then
    print_status "Prometheus is healthy"
else
    print_warning "Prometheus health check failed"
fi

# Check Grafana
if curl -s http://localhost:3000/api/health > /dev/null; then
    print_status "Grafana is healthy"
else
    print_warning "Grafana health check failed"
fi

print_status "Deployment completed!"

echo
echo "Monitoring Stack URLs:"
echo "  Grafana Dashboard: http://localhost:3000 (admin/YOUR_SECURE_PASSWORD)"
echo "  Prometheus: http://localhost:9090"
echo

print_warning "IMPORTANT: Please update the following in your configuration files:"
echo "  1. Replace 'YOUR_SECURE_PASSWORD' with a strong password in docker-compose.prod.yml"
echo "  2. Replace 'YOUR_WEBSITE_SERVER_IP' with your actual website server IP in prometheus.prod.yml"
echo "  3. Replace 'YOUR_WEBSITE_DOMAIN' with your actual domain in prometheus.prod.yml"
echo

print_status "To view logs: docker-compose -f docker-compose.prod.yml logs -f"
print_status "To stop services: docker-compose -f docker-compose.prod.yml down"
print_status "To restart services: docker-compose -f docker-compose.prod.yml restart"

echo
print_status "Production deployment script completed!"

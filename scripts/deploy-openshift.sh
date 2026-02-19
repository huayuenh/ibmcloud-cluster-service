#!/bin/bash

set -e

# OpenShift-specific deployment logic
# This script handles OpenShift route configuration

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

print_info "Configuring OpenShift-specific resources..."

# Handle OpenShift Route
if [ "$CREATE_ROUTE" = "true" ]; then
    print_info "Creating OpenShift route..."
    
    if [ -n "$ROUTE_HOSTNAME" ]; then
        oc expose service $DEPLOYMENT_NAME -n "$NAMESPACE" --hostname="$ROUTE_HOSTNAME" 2>/dev/null || oc patch route $DEPLOYMENT_NAME -n "$NAMESPACE" -p "{\"spec\":{\"host\":\"$ROUTE_HOSTNAME\"}}"
    else
        oc expose service $DEPLOYMENT_NAME -n "$NAMESPACE" 2>/dev/null || echo "Route already exists"
    fi
    
    # Get route URL
    ROUTE_HOST=$(oc get route $DEPLOYMENT_NAME -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    if [ -n "$ROUTE_HOST" ]; then
        APP_URL="http://${ROUTE_HOST}"
        print_success "Route created: $APP_URL"
        
        # Export APP_URL for parent script
        echo "$APP_URL"
    else
        print_warning "Failed to retrieve route host"
    fi
else
    print_info "Route creation disabled (CREATE_ROUTE != true)"
fi

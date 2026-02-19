#!/bin/bash

set -e

# Kubernetes-specific deployment logic
# This script handles Kubernetes ingress configuration

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Redirect all informational output to stderr so only the URL goes to stdout
exec 3>&1  # Save stdout
exec 1>&2  # Redirect stdout to stderr

print_info "Configuring Kubernetes-specific resources..."

# Auto-detect IBM Cloud Ingress subdomain if requested
if [ "$AUTO_INGRESS" = "true" ]; then
    print_info "Auto-detecting IBM Cloud cluster ingress subdomain..."
    
    if [ -n "$CLUSTER_NAME" ] && command -v ibmcloud &> /dev/null; then
        # Get the ingress subdomain from IBM Cloud
        INGRESS_SUBDOMAIN=$(ibmcloud ks cluster get --cluster "$CLUSTER_NAME" 2>/dev/null | grep "Ingress Subdomain" | awk '{print $NF}' || echo "")
        
        if [ -n "$INGRESS_SUBDOMAIN" ] && [ "$INGRESS_SUBDOMAIN" != "-" ]; then
            print_success "Auto-detected ingress subdomain: $INGRESS_SUBDOMAIN"
            
            # If using a manifest with placeholder, replace it
            if [ -n "$DEPLOYMENT_MANIFEST" ] && [ -f "$DEPLOYMENT_MANIFEST" ]; then
                if grep -q "cluster-ingress-subdomain" "$DEPLOYMENT_MANIFEST"; then
                    print_info "Replacing cluster-ingress-subdomain placeholder in manifest..."
                    
                    # Create a temporary file with replacements
                    sed "s|cluster-ingress-subdomain|${INGRESS_SUBDOMAIN}|g" "$DEPLOYMENT_MANIFEST" > /tmp/deployment-with-ingress.yaml
                    
                    # Apply the updated manifest
                    sed "s|IMAGE_PLACEHOLDER|$IMAGE|g" /tmp/deployment-with-ingress.yaml | kubectl apply -n "$NAMESPACE" -f -
                    handle_error $? "Failed to apply manifest with ingress subdomain"
                    
                    # Extract the actual ingress host that was applied
                    INGRESS_HOST=$(grep -A 20 "kind: Ingress" /tmp/deployment-with-ingress.yaml | grep "host:" | head -1 | awk '{print $2}' | tr -d '"' || echo "")
                    print_info "Ingress host from manifest: $INGRESS_HOST"
                fi
            elif [ -z "$INGRESS_HOST" ]; then
                # No manifest or no placeholder - create hostname using deployment name
                INGRESS_HOST="${DEPLOYMENT_NAME}.${INGRESS_SUBDOMAIN}"
                print_info "Using ingress host: $INGRESS_HOST"
            fi
            
            # Enable TLS by default for IBM Cloud ingress
            if [ -z "$INGRESS_TLS" ] || [ "$INGRESS_TLS" != "false" ]; then
                INGRESS_TLS="true"
                print_info "TLS enabled for IBM Cloud ingress"
            fi
        else
            print_warning "Could not auto-detect ingress subdomain for cluster: $CLUSTER_NAME"
            print_warning "Ingress will not be configured"
        fi
    else
        print_warning "Cannot auto-detect ingress: ibmcloud CLI not available or CLUSTER_NAME not set"
    fi
fi

# Handle Kubernetes Ingress
if [ -n "$INGRESS_HOST" ]; then
    print_info "Creating Kubernetes ingress..."
    
    TLS_CONFIG=""
    if [ "$INGRESS_TLS" = "true" ]; then
        TLS_CONFIG="  tls:
  - hosts:
    - $INGRESS_HOST
    secretName: ${DEPLOYMENT_NAME}-tls"
    fi
    
    cat > /tmp/ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $DEPLOYMENT_NAME
  namespace: $NAMESPACE
  labels:
    app: $DEPLOYMENT_NAME
spec:
$TLS_CONFIG
  rules:
  - host: $INGRESS_HOST
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: $DEPLOYMENT_NAME
            port:
              number: 80
EOF
    
    kubectl apply -f /tmp/ingress.yaml
    handle_error $? "Failed to create ingress"
    
    if [ "$INGRESS_TLS" = "true" ]; then
        APP_URL="https://${INGRESS_HOST}"
    else
        APP_URL="http://${INGRESS_HOST}"
    fi
    
    print_success "Ingress created: $APP_URL"
    
    # Output URL to stdout (fd 3) for parent script to capture
    echo "$APP_URL" >&3
else
    print_info "No ingress host configured, skipping ingress creation"
fi

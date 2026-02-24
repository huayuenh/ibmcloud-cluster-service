#!/bin/bash

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "::group::Deploying application"

# Function to process environment template file
process_env_template() {
    local template_file=$1
    
    if [ ! -f "$template_file" ]; then
        print_warning "Environment template file not found: $template_file"
        return 1
    fi
    
    print_info "Processing environment template: $template_file"
    
    # Read template content
    local template_content=$(cat "$template_file")
    
    # Substitute GitHub context variables
    template_content="${template_content//\{\{GIT_TAG\}\}/${GITHUB_REF_NAME:-${GITHUB_SHA}}}"
    template_content="${template_content//\{\{GIT_SHA\}\}/${GITHUB_SHA}}"
    template_content="${template_content//\{\{BUILD_DATE\}\}/${GITHUB_EVENT_HEAD_COMMIT_TIMESTAMP:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}}"
    template_content="${template_content//\{\{ENVIRONMENT\}\}/${GITHUB_ENVIRONMENT:-production}}"
    template_content="${template_content//\{\{BRANCH\}\}/${GITHUB_REF_NAME}}"
    template_content="${template_content//\{\{REPOSITORY\}\}/${GITHUB_REPOSITORY}}"
    template_content="${template_content//\{\{COMMIT_MESSAGE\}\}/${GITHUB_EVENT_HEAD_COMMIT_MESSAGE}}"
    template_content="${template_content//\{\{WORKFLOW\}\}/${GITHUB_WORKFLOW}}"
    template_content="${template_content//\{\{RUN_ID\}\}/${GITHUB_RUN_ID}}"
    template_content="${template_content//\{\{RUN_NUMBER\}\}/${GITHUB_RUN_NUMBER}}"
    
    # Append to ENV_VARS
    if [ -n "$ENV_VARS" ]; then
        ENV_VARS="$ENV_VARS"$'\n'"$template_content"
    else
        ENV_VARS="$template_content"
    fi
    
    print_success "Environment template processed"
}

# Function to parse YAML config file
parse_config_file() {
    local config_file=$1
    local environment=$2
    
    if [ ! -f "$config_file" ]; then
        print_warning "Config file not found: $config_file"
        return 1
    fi
    
    print_info "Loading configuration from: $config_file"
    
    # Install yq if not available
    if ! command -v yq &> /dev/null; then
        print_info "Installing yq for YAML parsing..."
        wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        chmod +x /usr/local/bin/yq
    fi
    
    # Load defaults
    export PORT="${PORT:-$(yq eval '.defaults.port // ""' "$config_file")}"
    export REPLICAS="${REPLICAS:-$(yq eval '.defaults.replicas // ""' "$config_file")}"
    export SERVICE_TYPE="${SERVICE_TYPE:-$(yq eval '.defaults.service-type // ""' "$config_file")}"
    export MANIFEST_TEMPLATE="${MANIFEST_TEMPLATE:-$(yq eval '.defaults.manifest-template // ""' "$config_file")}"
    export RESOURCE_LIMITS_CPU="${RESOURCE_LIMITS_CPU:-$(yq eval '.defaults.resource-limits-cpu // ""' "$config_file")}"
    export RESOURCE_LIMITS_MEMORY="${RESOURCE_LIMITS_MEMORY:-$(yq eval '.defaults.resource-limits-memory // ""' "$config_file")}"
    export RESOURCE_REQUESTS_CPU="${RESOURCE_REQUESTS_CPU:-$(yq eval '.defaults.resource-requests-cpu // ""' "$config_file")}"
    export RESOURCE_REQUESTS_MEMORY="${RESOURCE_REQUESTS_MEMORY:-$(yq eval '.defaults.resource-requests-memory // ""' "$config_file")}"
    
    # Load environment-specific settings
    if [ -n "$environment" ]; then
        print_info "Loading environment-specific settings for: $environment"
        
        export NAMESPACE="${NAMESPACE:-$(yq eval ".environments.$environment.namespace // \"\"" "$config_file")}"
        export REPLICAS="${REPLICAS:-$(yq eval ".environments.$environment.replicas // \"\"" "$config_file")}"
        export RESOURCE_LIMITS_CPU="${RESOURCE_LIMITS_CPU:-$(yq eval ".environments.$environment.resource-limits-cpu // \"\"" "$config_file")}"
        export RESOURCE_LIMITS_MEMORY="${RESOURCE_LIMITS_MEMORY:-$(yq eval ".environments.$environment.resource-limits-memory // \"\"" "$config_file")}"
        export RESOURCE_REQUESTS_CPU="${RESOURCE_REQUESTS_CPU:-$(yq eval ".environments.$environment.resource-requests-cpu // \"\"" "$config_file")}"
        export RESOURCE_REQUESTS_MEMORY="${RESOURCE_REQUESTS_MEMORY:-$(yq eval ".environments.$environment.resource-requests-memory // \"\"" "$config_file")}"
        
        # Load environment variables from config
        local config_env_vars=$(yq eval ".environments.$environment.env-vars // {} | to_entries | .[] | .key + \"=\" + .value" "$config_file" 2>/dev/null || echo "")
        if [ -n "$config_env_vars" ]; then
            if [ -n "$ENV_VARS" ]; then
                ENV_VARS="$ENV_VARS"$'\n'"$config_env_vars"
            else
                ENV_VARS="$config_env_vars"
            fi
        fi
    fi
    
    print_success "Configuration loaded successfully"
}

# Load configuration file if provided
if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
    ENVIRONMENT="${GITHUB_ENVIRONMENT:-}"
    if [ -z "$ENVIRONMENT" ] && [ -n "$NAMESPACE" ]; then
        ENVIRONMENT="$NAMESPACE"
    fi
    parse_config_file "$CONFIG_FILE" "$ENVIRONMENT"
fi

# Process environment template if provided
if [ -n "$ENV_TEMPLATE" ] && [ -f "$ENV_TEMPLATE" ]; then
    process_env_template "$ENV_TEMPLATE"
fi

# Auto-detect deployment name from repository
if [ -z "$DEPLOYMENT_NAME" ] && [ -n "$GITHUB_REPOSITORY_NAME" ]; then
    DEPLOYMENT_NAME="$GITHUB_REPOSITORY_NAME"
    print_info "Auto-detected deployment name: $DEPLOYMENT_NAME"
fi

# Validate required parameters
if [ -z "$DEPLOYMENT_NAME" ]; then
    print_error "DEPLOYMENT_NAME is required"
    exit 1
fi

if [ -z "$NAMESPACE" ]; then
    print_warning "NAMESPACE not set, using default"
    NAMESPACE="default"
fi

# Set kubectl or oc command
CMD="${CLUSTER_TYPE:+oc}"
CMD="${CMD:-kubectl}"

print_info "Using command: $CMD"
print_info "Image: $IMAGE"
print_info "Namespace: $NAMESPACE"
print_info "Deployment: $DEPLOYMENT_NAME"

# Create namespace if it doesn't exist
print_info "Ensuring namespace exists..."
$CMD get namespace "$NAMESPACE" &>/dev/null || $CMD create namespace "$NAMESPACE"
print_success "Namespace ready: $NAMESPACE"

# Create image pull secret for IBM Cloud Container Registry
if [[ "$IMAGE" =~ \.icr\.io/ ]] && [ -n "$IBM_CLOUD_API_KEY" ]; then
    print_info "Creating image pull secret for ICR..."
    REGISTRY=$(echo "$IMAGE" | cut -d'/' -f1)
    
    $CMD create secret docker-registry icr-secret \
        --docker-server="$REGISTRY" \
        --docker-username=iamapikey \
        --docker-password="$IBM_CLOUD_API_KEY" \
        --docker-email=iamapikey@ibm.com \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | $CMD apply -f -
    
    handle_error $? "Failed to create image pull secret"
    print_success "Image pull secret created: icr-secret"
    IMAGE_PULL_SECRET="icr-secret"
fi

# Auto-extract version from image tag
if [ -z "$VERSION" ] && [ -n "$IMAGE" ]; then
    VERSION=$(echo "$IMAGE" | grep -oP ':[^:]+$' | sed 's/^://' || echo "latest")
    print_info "Auto-extracted version: $VERSION"
fi
VERSION="${VERSION:-latest}"

# Auto-detect image pull secret
if [ -z "$IMAGE_PULL_SECRET" ]; then
    if $CMD get secret all-icr-io -n "$NAMESPACE" &>/dev/null; then
        IMAGE_PULL_SECRET="all-icr-io"
        print_info "Auto-detected image pull secret: $IMAGE_PULL_SECRET"
    fi
fi

# Set container name
CONTAINER_NAME_ACTUAL="${CONTAINER_NAME:-$DEPLOYMENT_NAME}"

# Function to substitute variables in template
substitute_template_vars() {
    local template_file=$1
    local output_file=$2
    
    local content=$(cat "$template_file")
    
    # Auto-configure ingress if needed
    local ingress_host=""
    local ingress_secret=""
    local ingress_annotations=""
    
    if [[ "$content" == *"{{INGRESS_HOST}}"* ]]; then
        if [ "$AUTO_INGRESS" = "true" ]; then
            print_info "Auto-detecting IBM Cloud cluster ingress subdomain..."
            INGRESS_SUBDOMAIN=$(ibmcloud ks cluster get --cluster "$CLUSTER_NAME" --output json 2>/dev/null | jq -r '.ingressHostname // .ingress.hostname // empty' || echo "")
            
            if [ -n "$INGRESS_SUBDOMAIN" ]; then
                ingress_host="${DEPLOYMENT_NAME}-${NAMESPACE}.${INGRESS_SUBDOMAIN}"
                ingress_secret=$(ibmcloud ks cluster get --cluster "$CLUSTER_NAME" --output json 2>/dev/null | jq -r '.ingressSecretName // .ingress.secretName // empty' || echo "")
                print_success "Auto-detected ingress host: $ingress_host"
            fi
        elif [ -n "$INGRESS_HOST" ]; then
            ingress_host="$INGRESS_HOST"
        fi
        
        if [ -z "$ingress_secret" ]; then
            ingress_secret="${DEPLOYMENT_NAME}-tls"
        fi
        
        if [ "$INGRESS_TLS" = "true" ]; then
            ingress_annotations="nginx.ingress.kubernetes.io/ssl-redirect: \"true\""
        fi
    fi
    
    # Substitute all variables
    content="${content//\{\{IMAGE\}\}/$IMAGE}"
    content="${content//\{\{DEPLOYMENT_NAME\}\}/$DEPLOYMENT_NAME}"
    content="${content//\{\{NAMESPACE\}\}/$NAMESPACE}"
    content="${content//\{\{CONTAINER_NAME\}\}/$CONTAINER_NAME_ACTUAL}"
    content="${content//\{\{PORT\}\}/$PORT}"
    content="${content//\{\{REPLICAS\}\}/$REPLICAS}"
    content="${content//\{\{SERVICE_TYPE\}\}/$SERVICE_TYPE}"
    content="${content//\{\{RESOURCE_LIMITS_CPU\}\}/$RESOURCE_LIMITS_CPU}"
    content="${content//\{\{RESOURCE_LIMITS_MEMORY\}\}/$RESOURCE_LIMITS_MEMORY}"
    content="${content//\{\{RESOURCE_REQUESTS_CPU\}\}/$RESOURCE_REQUESTS_CPU}"
    content="${content//\{\{RESOURCE_REQUESTS_MEMORY\}\}/$RESOURCE_REQUESTS_MEMORY}"
    content="${content//\{\{IMAGE_PULL_SECRET\}\}/${IMAGE_PULL_SECRET:-}}"
    content="${content//\{\{VERSION\}\}/${VERSION}}"
    content="${content//\{\{INGRESS_HOST\}\}/$ingress_host}"
    content="${content//\{\{INGRESS_SECRET\}\}/$ingress_secret}"
    content="${content//\{\{INGRESS_ANNOTATIONS\}\}/$ingress_annotations}"
    
    # Handle environment variables
    if [ -n "$ENV_VARS" ]; then
        local env_yaml=""
        while IFS= read -r env_var; do
            if [ -n "$env_var" ] && [[ "$env_var" != \#* ]]; then
                KEY=$(echo "$env_var" | cut -d'=' -f1)
                VALUE=$(echo "$env_var" | cut -d'=' -f2-)
                if [ -z "$env_yaml" ]; then
                    env_yaml="        - name: $KEY"$'\n'"          value: \"$VALUE\""
                else
                    env_yaml="$env_yaml"$'\n'"        - name: $KEY"$'\n'"          value: \"$VALUE\""
                fi
            fi
        done <<< "$ENV_VARS"
        content="${content//        \{\{ENV_VARS\}\}/$env_yaml}"
    else
        content=$(echo "$content" | sed '/{{ENV_VARS}}/d' | sed '/^[[:space:]]*env:[[:space:]]*$/d')
    fi
    
    printf '%s\n' "$content" > "$output_file"
}

# Deploy using manifest template
if [ -z "$MANIFEST_TEMPLATE" ] || [ ! -f "$MANIFEST_TEMPLATE" ]; then
    print_error "Manifest template not found: $MANIFEST_TEMPLATE"
    print_error "Please provide a valid manifest template file"
    exit 1
fi

print_info "Using manifest template: $MANIFEST_TEMPLATE"

# Substitute variables and create temporary manifest
TEMP_MANIFEST="/tmp/deployment-$(date +%s).yaml"
substitute_template_vars "$MANIFEST_TEMPLATE" "$TEMP_MANIFEST"

print_info "Applying manifest..."
$CMD apply -f "$TEMP_MANIFEST"
handle_error $? "Failed to apply manifest"

# Get application URL from ingress if configured
APP_URL=""
if grep -q "kind: Ingress" "$TEMP_MANIFEST" 2>/dev/null; then
    print_info "Waiting for ingress to be ready..."
    sleep 5
    
    INGRESS_HOST_ACTUAL=$($CMD get ingress "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
    
    if [ -n "$INGRESS_HOST_ACTUAL" ]; then
        TLS_ENABLED=$($CMD get ingress "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.tls[0].hosts[0]}' 2>/dev/null || echo "")
        
        if [ -n "$TLS_ENABLED" ]; then
            APP_URL="https://${INGRESS_HOST_ACTUAL}"
        else
            APP_URL="http://${INGRESS_HOST_ACTUAL}"
        fi
        
        print_success "Ingress configured: $APP_URL"
    fi
fi

# Clean up
rm -f "$TEMP_MANIFEST"

print_success "Deployment created/updated"

# Wait for deployment to be ready
print_info "Waiting for deployment to be ready..."
$CMD rollout status deployment/$DEPLOYMENT_NAME -n "$NAMESPACE" --timeout=5m
handle_error $? "Deployment failed to become ready"

print_success "Deployment is ready"

# Handle OpenShift Route if on OpenShift cluster
if [ "$CLUSTER_TYPE" = "openshift" ] && [ "$CREATE_ROUTE" = "true" ]; then
    print_info "Creating OpenShift route..."
    
    if [ -n "$ROUTE_HOSTNAME" ]; then
        oc expose service $DEPLOYMENT_NAME -n "$NAMESPACE" --hostname="$ROUTE_HOSTNAME" 2>/dev/null || oc patch route $DEPLOYMENT_NAME -n "$NAMESPACE" -p "{\"spec\":{\"host\":\"$ROUTE_HOSTNAME\"}}"
    else
        oc expose service $DEPLOYMENT_NAME -n "$NAMESPACE" 2>/dev/null || print_info "Route already exists"
    fi
    
    # Get route URL
    ROUTE_HOST=$(oc get route $DEPLOYMENT_NAME -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
    if [ -n "$ROUTE_HOST" ]; then
        APP_URL="http://${ROUTE_HOST}"
        print_success "OpenShift Route created: $APP_URL"
    fi
fi

# Get service information
SERVICE_IP=""
CLUSTER_IP=$($CMD get service $DEPLOYMENT_NAME -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

if [ "$SERVICE_TYPE" = "LoadBalancer" ]; then
    print_info "Waiting for LoadBalancer external IP..."
    for i in {1..60}; do
        SERVICE_IP=$($CMD get service $DEPLOYMENT_NAME -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        [ -z "$SERVICE_IP" ] && SERVICE_IP=$($CMD get service $DEPLOYMENT_NAME -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
        
        [ -n "$SERVICE_IP" ] && break
        echo -n "."
        sleep 5
    done
    echo ""
    
    if [ -n "$SERVICE_IP" ]; then
        APP_URL="${APP_URL:-http://${SERVICE_IP}}"
        print_success "LoadBalancer IP: $SERVICE_IP"
    else
        print_warning "LoadBalancer IP not yet assigned"
    fi
    
elif [ "$SERVICE_TYPE" = "NodePort" ]; then
    NODE_PORT=$($CMD get service $DEPLOYMENT_NAME -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')
    
    # Get node IP (try multiple methods)
    NODE_IP=""
    
    # Method 1: IBM Cloud CLI
    if [ -n "$IBM_CLOUD_API_KEY" ] && command -v ibmcloud &> /dev/null && [ -n "$CLUSTER_NAME" ]; then
        NODE_IP=$(ibmcloud ks workers --cluster "$CLUSTER_NAME" --output json 2>/dev/null | grep -o '"publicIP":"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
    fi
    
    # Method 2: External IP from nodes
    [ -z "$NODE_IP" ] && NODE_IP=$($CMD get nodes -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null | awk '{print $1}')
    
    # Method 3: IBM Cloud node labels
    [ -z "$NODE_IP" ] && NODE_IP=$($CMD get nodes -o jsonpath='{.items[0].metadata.labels.ibm-cloud\.kubernetes\.io/external-ip}' 2>/dev/null || echo "")
    
    # Method 4: Hostname
    [ -z "$NODE_IP" ] && NODE_IP=$($CMD get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="Hostname")].address}' 2>/dev/null || echo "")
    
    # Method 5: Internal IP (last resort)
    if [ -z "$NODE_IP" ]; then
        NODE_IP=$($CMD get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        print_warning "Using internal node IP (may not be accessible externally)"
    fi
    
    if [ -n "$NODE_IP" ] && [ -n "$NODE_PORT" ]; then
        SERVICE_IP="${NODE_IP}:${NODE_PORT}"
        APP_URL="${APP_URL:-http://${SERVICE_IP}}"
        print_success "NodePort: $NODE_PORT on $NODE_IP"
    fi
    
elif [ "$SERVICE_TYPE" = "ClusterIP" ]; then
    print_info "Service type is ClusterIP - accessible only within cluster"
    if [ -n "$CLUSTER_IP" ]; then
        SERVICE_IP="${CLUSTER_IP}:80"
        print_info "Cluster IP: $CLUSTER_IP"
        print_info "Service DNS: ${DEPLOYMENT_NAME}.${NAMESPACE}.svc.cluster.local"
        APP_URL="${APP_URL:-http://${DEPLOYMENT_NAME}.${NAMESPACE}.svc.cluster.local}"
    fi
fi

# Set outputs
echo "status=success" >> $GITHUB_OUTPUT

if [ -n "$APP_URL" ]; then
    echo "app-url=$APP_URL" >> $GITHUB_OUTPUT
    print_success "Application URL: $APP_URL"
fi

if [ -n "$SERVICE_IP" ]; then
    echo "service-ip=$SERVICE_IP" >> $GITHUB_OUTPUT
fi

# Get deployment info
DEPLOYMENT_INFO=$($CMD get deployment $DEPLOYMENT_NAME -n "$NAMESPACE" -o json 2>/dev/null || echo "{}")
echo "info<<EOF" >> $GITHUB_OUTPUT
echo "$DEPLOYMENT_INFO" >> $GITHUB_OUTPUT
echo "EOF" >> $GITHUB_OUTPUT

print_success "Deployment completed successfully"

# Generate GitHub Step Summary
if [ -n "$GITHUB_STEP_SUMMARY" ]; then
    print_info "Generating deployment summary..."
    
    echo "### Deployment Summary :rocket:" >> $GITHUB_STEP_SUMMARY
    echo "" >> $GITHUB_STEP_SUMMARY
    echo "#### Deployment Information" >> $GITHUB_STEP_SUMMARY
    echo "**Status:** ✅ Success" >> $GITHUB_STEP_SUMMARY
    echo "**Deployment Name:** \`$DEPLOYMENT_NAME\`" >> $GITHUB_STEP_SUMMARY
    echo "**Namespace:** \`$NAMESPACE\`" >> $GITHUB_STEP_SUMMARY
    echo "**Image:** \`$IMAGE\`" >> $GITHUB_STEP_SUMMARY
    echo "**Replicas:** $REPLICAS" >> $GITHUB_STEP_SUMMARY
    echo "" >> $GITHUB_STEP_SUMMARY
    
    if [ -n "$APP_URL" ]; then
        echo "#### Access Information" >> $GITHUB_STEP_SUMMARY
        echo "**Application URL:** $APP_URL" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "🌐 **[Access your application]($APP_URL)**" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
    fi
    
    if [ -n "$SERVICE_IP" ]; then
        echo "**Service IP:** \`$SERVICE_IP\`" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
    fi
    
    echo "#### Resource Configuration" >> $GITHUB_STEP_SUMMARY
    echo "**CPU Limits:** $RESOURCE_LIMITS_CPU" >> $GITHUB_STEP_SUMMARY
    echo "**Memory Limits:** $RESOURCE_LIMITS_MEMORY" >> $GITHUB_STEP_SUMMARY
    echo "**CPU Requests:** $RESOURCE_REQUESTS_CPU" >> $GITHUB_STEP_SUMMARY
    echo "**Memory Requests:** $RESOURCE_REQUESTS_MEMORY" >> $GITHUB_STEP_SUMMARY
fi

echo "::endgroup::"

# Made with Bob

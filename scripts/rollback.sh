#!/bin/bash

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "::group::Performing Kubernetes rollback"

# Set kubectl or oc command based on cluster type
if [ "$CLUSTER_TYPE" = "openshift" ]; then
    CMD="oc"
else
    CMD="kubectl"
fi

print_info "Using command: $CMD"
print_info "Namespace: $NAMESPACE"
print_info "Deployment: $DEPLOYMENT_NAME"

# Check if deployment exists
if ! $CMD get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" &>/dev/null; then
    print_error "Deployment $DEPLOYMENT_NAME not found in namespace $NAMESPACE"
    echo "::error::Deployment $DEPLOYMENT_NAME not found in namespace $NAMESPACE"
    echo "status=failed" >> $GITHUB_OUTPUT
    echo "error=Deployment not found" >> $GITHUB_OUTPUT
    exit 1
fi

# Check revision history
print_info "Checking deployment revision history..."
REVISION_COUNT=$($CMD rollout history deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" 2>/dev/null | grep -c "^[0-9]" || echo "0")

if [ "$REVISION_COUNT" -le 1 ]; then
    print_error "No previous revision available for rollback"
    print_error "Revision count: $REVISION_COUNT"
    echo "::error::No previous revision available for rollback (found $REVISION_COUNT revisions)"
    echo "status=failed" >> $GITHUB_OUTPUT
    echo "error=No previous revision available" >> $GITHUB_OUTPUT
    exit 1
fi

print_success "Found $REVISION_COUNT revisions in history"

# Show current deployment status
print_info "Current deployment status:"
$CMD get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE"

# Get current revision before rollback
CURRENT_REVISION=$($CMD get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')
print_info "Current revision: $CURRENT_REVISION"

# Get current image before rollback
CURRENT_IMAGE=$($CMD get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
print_info "Current image: $CURRENT_IMAGE"

# Perform rollback to previous revision
print_info "Initiating rollback to previous revision..."
$CMD rollout undo deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE"
handle_error $? "Failed to initiate rollback"

print_success "Rollback initiated"

# Wait for rollback to complete
print_info "Waiting for rollback to complete (timeout: 5 minutes)..."
if $CMD rollout status deployment/"$DEPLOYMENT_NAME" -n "$NAMESPACE" --timeout=5m; then
    print_success "Rollback completed successfully"
    
    # Get the rolled back revision info
    NEW_REVISION=$($CMD get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')
    print_info "Rolled back to revision: $NEW_REVISION"
    
    # Get rolled back image
    ROLLED_BACK_IMAGE=$($CMD get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')
    print_success "Rolled back image: $ROLLED_BACK_IMAGE"
    
    # Get ready replicas
    READY_REPLICAS=$($CMD get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    DESIRED_REPLICAS=$($CMD get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
    
    print_info "Ready replicas: $READY_REPLICAS/$DESIRED_REPLICAS"
    
    # Set outputs
    echo "status=success" >> $GITHUB_OUTPUT
    echo "previous-revision=$CURRENT_REVISION" >> $GITHUB_OUTPUT
    echo "previous-image=$CURRENT_IMAGE" >> $GITHUB_OUTPUT
    echo "current-revision=$NEW_REVISION" >> $GITHUB_OUTPUT
    echo "current-image=$ROLLED_BACK_IMAGE" >> $GITHUB_OUTPUT
    echo "ready-replicas=$READY_REPLICAS" >> $GITHUB_OUTPUT
    echo "desired-replicas=$DESIRED_REPLICAS" >> $GITHUB_OUTPUT
    
    print_success "Rollback verification complete"
    
    # Generate GitHub Step Summary
    if [ -n "$GITHUB_STEP_SUMMARY" ]; then
        print_info "Generating rollback summary..."
        
        echo "### Rollback Summary :leftwards_arrow_with_hook:" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "#### Rollback Information" >> $GITHUB_STEP_SUMMARY
        echo "**Status:** ✅ Success" >> $GITHUB_STEP_SUMMARY
        echo "**Deployment Name:** \`$DEPLOYMENT_NAME\`" >> $GITHUB_STEP_SUMMARY
        echo "**Namespace:** \`$NAMESPACE\`" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "#### Revision Details" >> $GITHUB_STEP_SUMMARY
        echo "**Previous Revision:** $CURRENT_REVISION" >> $GITHUB_STEP_SUMMARY
        echo "**Previous Image:** \`$CURRENT_IMAGE\`" >> $GITHUB_STEP_SUMMARY
        echo "**Current Revision:** $NEW_REVISION (rolled back)" >> $GITHUB_STEP_SUMMARY
        echo "**Current Image:** \`$ROLLED_BACK_IMAGE\`" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "#### Pod Status" >> $GITHUB_STEP_SUMMARY
        echo "**Ready Replicas:** $READY_REPLICAS/$DESIRED_REPLICAS" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "⚠️ **Rollback was triggered due to deployment failure**" >> $GITHUB_STEP_SUMMARY
    fi
else
    print_error "Rollback failed or timed out"
    echo "::error::Rollback failed or timed out"
    echo "status=failed" >> $GITHUB_OUTPUT
    echo "error=Rollback timeout" >> $GITHUB_OUTPUT
    
    # Generate failure summary
    if [ -n "$GITHUB_STEP_SUMMARY" ]; then
        echo "### Rollback Failed :x:" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "**Deployment Name:** \`$DEPLOYMENT_NAME\`" >> $GITHUB_STEP_SUMMARY
        echo "**Namespace:** \`$NAMESPACE\`" >> $GITHUB_STEP_SUMMARY
        echo "" >> $GITHUB_STEP_SUMMARY
        echo "❌ **Rollback failed or timed out - manual intervention required**" >> $GITHUB_STEP_SUMMARY
    fi
    
    exit 1
fi

echo "::endgroup::"

# Made with Bob

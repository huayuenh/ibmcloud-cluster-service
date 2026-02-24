# Deploy to Kubernetes/OpenShift Action

A comprehensive GitHub Action for deploying container images to Kubernetes or Red Hat OpenShift clusters with health checks, status verification, automatic URL generation, and native Kubernetes rollback support.

## Features

- 🚀 **Deploy to Kubernetes or OpenShift** clusters
- 🔄 **Native Kubernetes Rollback** using ReplicaSets for fast, reliable rollbacks
- 🔐 **Multiple authentication methods** (kubeconfig or IBM Cloud API key)
- 🔑 **Automatic image pull secrets** for IBM Cloud Container Registry
- 🏥 **Health checks** with configurable timeout and path
- 🌐 **Automatic URL generation** for LoadBalancer, NodePort, Routes, and Ingress
- 📊 **Status verification** with pod and deployment monitoring
- ⚙️ **Resource management** with configurable CPU and memory limits
- 🔄 **Rolling updates** with automatic rollout status checking
- 📝 **Environment variables** support
- 🎯 **Service types** support (ClusterIP, NodePort, LoadBalancer)
- 🛣️ **OpenShift Routes** and Kubernetes Ingress support

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `action` | ❌ | `deploy` | Action to perform: `deploy` or `rollback` |
| `image` | ❌ * | - | Container image to deploy (e.g., `us.icr.io/namespace/app:tag`). Required for deploy action |
| `cluster-type` | ❌ | `kubernetes` | Cluster type: `kubernetes` or `openshift` |
| `kubeconfig` | ❌ * | - | Kubeconfig content (base64 encoded or plain text) |
| `ibmcloud-apikey` | ❌ * | - | IBM Cloud API key (for IBM Cloud clusters) |
| `cluster-name` | ❌ * | - | IBM Cloud cluster name (required with `ibmcloud-apikey`) |
| `cluster-region` | ❌ | `us-south` | IBM Cloud cluster region |
| `namespace` | ❌ | `default` | Kubernetes namespace for deployment |
| `deployment-name` | ✅ | - | Name of the deployment |
| `deployment-manifest` | ❌ | - | Path to custom deployment manifest |
| `container-name` | ❌ | deployment-name | Container name in the deployment |
| `port` | ❌ | `8080` | Container port to expose |
| `service-type` | ❌ | `ClusterIP` | Service type: ClusterIP, NodePort, LoadBalancer |
| `replicas` | ❌ | `1` | Number of replicas |
| `health-check-path` | ❌ | `/` | HTTP path for health check. Use `/` for root endpoint or specify custom path like `/health` |
| `health-check-timeout` | ❌ | `300` | Health check timeout in seconds |
| `enable-probes` | ❌ | `false` | Enable liveness and readiness probes (true/false) |
| `readiness-probe-path` | ❌ | health-check-path | HTTP path for readiness probe |
| `liveness-probe-path` | ❌ | health-check-path | HTTP path for liveness probe |
| `resource-limits-cpu` | ❌ | `500m` | CPU resource limit |
| `resource-limits-memory` | ❌ | `512Mi` | Memory resource limit |
| `resource-requests-cpu` | ❌ | `250m` | CPU resource request |
| `resource-requests-memory` | ❌ | `256Mi` | Memory resource request |
| `env-vars` | ❌ | - | Environment variables (KEY=VALUE format, one per line) |
| `create-route` | ❌ | `true` | Create OpenShift route (OpenShift only) |
| `route-hostname` | ❌ | - | Custom hostname for OpenShift route |
| `ingress-host` | ❌ | - | Ingress hostname (Kubernetes only) |
| `ingress-tls` | ❌ | `false` | Enable TLS for ingress |
| `auto-ingress` | ❌ | `false` | Automatically detect and configure IBM Cloud cluster ingress subdomain |

**Note:** ❌ * indicates conditionally required:
- Either `kubeconfig` OR (`ibmcloud-apikey` + `cluster-name`) must be provided
- `image` is required for `deploy` action, not required for `rollback` action

## Outputs

| Output | Description |
|--------|-------------|
| `deployment-status` | Status of the deployment/rollback (success/failure) |
| `application-url` | URL to access the deployed application |
| `service-ip` | Service external IP or hostname |
| `health-check-result` | Health check result |
| `deployment-info` | Deployment information in JSON format |
| `previous-image` | Previously deployed image (rollback action only) |
| `rollback-revision` | Revision number rolled back to (rollback action only) |
| `rollback-image` | Image rolled back to (rollback action only) |

## Usage Examples

### Deploy to IBM Cloud Kubernetes

Deploy an image from IBM Cloud Container Registry to an IBM Cloud Kubernetes cluster:

```yaml
- name: Deploy to Kubernetes
  uses: ./deploy-action
  with:
    image: us.icr.io/my-namespace/myapp:v1.0.0
    cluster-type: kubernetes
    ibmcloud-apikey: ${{ secrets.IBM_CLOUD_API_KEY }}
    cluster-name: my-k8s-cluster
    cluster-region: us-south
    deployment-name: myapp
    namespace: production
    port: 8080
    replicas: 3
```

### Deploy to IBM Cloud OpenShift

Deploy to a Red Hat OpenShift cluster on IBM Cloud:

```yaml
- name: Deploy to OpenShift
  uses: ./deploy-action
  with:
    image: us.icr.io/my-namespace/myapp:v1.0.0
    cluster-type: openshift
    ibmcloud-apikey: ${{ secrets.IBM_CLOUD_API_KEY }}
    cluster-name: my-openshift-cluster
    cluster-region: us-south
    deployment-name: myapp
    namespace: production
    create-route: true
    route-hostname: myapp.example.com
```

### Deploy with Custom Kubeconfig

Deploy using a custom kubeconfig:

```yaml
- name: Deploy with kubeconfig
  uses: ./deploy-action
  with:
    image: myregistry.io/myapp:latest
    cluster-type: kubernetes
    kubeconfig: ${{ secrets.KUBECONFIG }}
    deployment-name: myapp
    namespace: default
```

### Deploy with Environment Variables

Deploy with custom environment variables:

```yaml
- name: Deploy with env vars
  uses: ./deploy-action
  with:
    image: us.icr.io/my-namespace/myapp:v1.0.0
    ibmcloud-apikey: ${{ secrets.IBM_CLOUD_API_KEY }}
    cluster-name: my-cluster
    deployment-name: myapp
    env-vars: |
      DATABASE_URL=postgresql://db.example.com:5432/mydb
      REDIS_URL=redis://redis.example.com:6379
      LOG_LEVEL=info
      NODE_ENV=production
```

### Deploy with Resource Limits

Deploy with custom resource limits and requests:

```yaml
- name: Deploy with resources
  uses: ./deploy-action
  with:
    image: us.icr.io/my-namespace/myapp:v1.0.0
    ibmcloud-apikey: ${{ secrets.IBM_CLOUD_API_KEY }}
    cluster-name: my-cluster
    deployment-name: myapp
    replicas: 5
    resource-limits-cpu: 1
    resource-limits-memory: 1Gi
    resource-requests-cpu: 500m
    resource-requests-memory: 512Mi
```

### Deploy with Ingress

Deploy with Kubernetes Ingress:

```yaml
- name: Deploy with Ingress
  uses: ./deploy-action
  with:
    image: us.icr.io/my-namespace/myapp:v1.0.0
    ibmcloud-apikey: ${{ secrets.IBM_CLOUD_API_KEY }}
    cluster-name: my-cluster
    deployment-name: myapp
    service-type: ClusterIP
    ingress-host: myapp.example.com
    ingress-tls: true
```

### Deploy with Custom Health Check

Deploy with custom health check configuration:

```yaml
- name: Deploy with health check
  uses: ./deploy-action
  with:
    image: us.icr.io/my-namespace/myapp:v1.0.0
    ibmcloud-apikey: ${{ secrets.IBM_CLOUD_API_KEY }}
    cluster-name: my-cluster
    deployment-name: myapp
    health-check-path: /api/health
    health-check-timeout: 600
```

### Deploy Without Health Probes

For applications that don't have health endpoints, disable probes:

```yaml
- name: Deploy without probes
  uses: ./deploy-action
  with:
    image: us.icr.io/my-namespace/myapp:v1.0.0
    ibmcloud-apikey: ${{ secrets.IBM_CLOUD_API_KEY }}
    cluster-name: my-cluster
    deployment-name: myapp
    enable-probes: false
```

### Deploy with Separate Liveness and Readiness Probes

Configure different paths for liveness and readiness:

```yaml
- name: Deploy with separate probes
  uses: ./deploy-action
  with:
    image: us.icr.io/my-namespace/myapp:v1.0.0
    ibmcloud-apikey: ${{ secrets.IBM_CLOUD_API_KEY }}
    cluster-name: my-cluster
    deployment-name: myapp
    enable-probes: true
    readiness-probe-path: /ready
    liveness-probe-path: /alive
```

### Rollback Deployment

Rollback a deployment to its previous revision using Kubernetes native rollback:

```yaml
- name: Rollback deployment
  uses: ./deploy-action
  with:
    action: rollback
    cluster-type: kubernetes
    ibmcloud-apikey: ${{ secrets.IBM_CLOUD_API_KEY }}
    cluster-name: my-k8s-cluster
    cluster-region: us-south
    deployment-name: myapp
    namespace: production
```

**Rollback Features:**
- Uses `kubectl rollout undo` for native Kubernetes rollback
- Leverages ReplicaSet revision history
- Fast and atomic operation
- Validates revision history exists before attempting rollback
- Returns previous and current revision information
- Waits for rollback completion with timeout

**Rollback Outputs:**
```yaml
- name: Verify rollback
  run: |
    echo "Rolled back to revision: ${{ steps.rollback.outputs.rollback-revision }}"
    echo "Current image: ${{ steps.rollback.outputs.rollback-image }}"
    echo "Previous image: ${{ steps.rollback.outputs.previous-image }}"
```

## Complete Workflow Examples

### Deploy with Automatic Rollback on Failure

Here's a complete workflow that builds, pushes, deploys, and automatically rolls back on failure:

```yaml
name: Build, Push, Deploy with Rollback

on:
  push:
    branches: [main]

env:
  IBM_CLOUD_REGION: us-south
  IBM_CLOUD_NAMESPACE: my-namespace
  CLUSTER_NAME: my-k8s-cluster

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Run tests
        run: npm test
      
      - name: Build Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: false
          load: true
          tags: myapp:${{ github.sha }}
      
      - name: Push to IBM Cloud Container Registry
        uses: huayuenh/container-registry-service-action@main
        with:
          apikey: ${{ secrets.IBM_CLOUD_API_KEY }}
          image: ${{ env.IBM_CLOUD_REGION }}.icr.io/${{ env.IBM_CLOUD_NAMESPACE }}/myapp:${{ github.sha }}
          local-image: myapp:${{ github.sha }}
          action: push
          scan: true
      
      - name: Deploy to Kubernetes
        id: deploy
        uses: huayuenh/cluster-service-action@main
        with:
          action: deploy
          image: ${{ env.IBM_CLOUD_REGION }}.icr.io/${{ env.IBM_CLOUD_NAMESPACE }}/myapp:${{ github.sha }}
          cluster-type: kubernetes
          ibmcloud-apikey: ${{ secrets.IBM_CLOUD_API_KEY }}
          cluster-name: ${{ env.CLUSTER_NAME }}
          cluster-region: ${{ env.IBM_CLOUD_REGION }}
          deployment-name: myapp
          namespace: production
          replicas: 3
      
      - name: Run acceptance tests
        id: acceptance-tests
        continue-on-error: true
        run: |
          # Test the deployed application
          curl -f ${{ steps.deploy.outputs.application-url }}/health
      
      - name: Rollback on failure
        if: steps.acceptance-tests.outcome == 'failure'
        uses: huayuenh/cluster-service-action@main
        with:
          action: rollback
          cluster-type: kubernetes
          ibmcloud-apikey: ${{ secrets.IBM_CLOUD_API_KEY }}
          cluster-name: ${{ env.CLUSTER_NAME }}
          cluster-region: ${{ env.IBM_CLOUD_REGION }}
          deployment-name: myapp
          namespace: production
      
      - name: Display deployment info
        if: steps.acceptance-tests.outcome == 'success'
        run: |
          echo "### Deployment Summary :rocket:" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          echo "**Status:** ${{ steps.deploy.outputs.deployment-status }}" >> $GITHUB_STEP_SUMMARY
          echo "**Application URL:** ${{ steps.deploy.outputs.application-url }}" >> $GITHUB_STEP_SUMMARY
          echo "**Health Check:** ${{ steps.deploy.outputs.health-check-result }}" >> $GITHUB_STEP_SUMMARY
```

## Authentication Methods

### Using Kubeconfig

Provide your kubeconfig as a secret (base64 encoded recommended):

```bash
# Encode kubeconfig
cat ~/.kube/config | base64 > kubeconfig.b64

# Add to GitHub Secrets as KUBECONFIG
```

### Using IBM Cloud API Key

For IBM Cloud Kubernetes or OpenShift clusters, use an IBM Cloud API key:

1. Create an API key in IBM Cloud
2. Add it to GitHub Secrets as `IBM_CLOUD_API_KEY`
3. Provide the cluster name and region

**Important:** When using an IBM Cloud API key, the action automatically creates an image pull secret for IBM Cloud Container Registry. This allows your cluster to pull private images from ICR without additional configuration.

## Image Pull Secrets

### Automatic Creation for IBM Cloud Container Registry

When deploying images from IBM Cloud Container Registry (*.icr.io), the action automatically:

1. Detects the registry from the image path
2. Creates a Kubernetes secret named `icr-secret` using the IBM Cloud API key
3. Configures the deployment to use this secret for pulling images

This happens automatically when you provide an `ibmcloud-apikey` input.

### Manual Image Pull Secrets

For other registries, you can create image pull secrets manually:

```bash
kubectl create secret docker-registry my-registry-secret \
  --docker-server=myregistry.io \
  --docker-username=myuser \
  --docker-password=mypassword \
  --docker-email=myemail@example.com \
  -n my-namespace
```

Then reference it in your deployment manifest.

## Health Checks

The action performs comprehensive health checks:

1. **Deployment Status**: Verifies deployment rollout is complete
2. **Pod Status**: Checks all pods are running
3. **HTTP Health Check**: Tests the application endpoint (if URL is available)

Health check results are available in the `health-check-result` output.

## Service Types

The action supports three Kubernetes service types, with **ClusterIP as the default** for maximum compatibility with VPC clusters.

### ClusterIP (Default - Recommended for VPC Clusters)

Internal cluster IP - accessible only within the cluster. Best for VPC Kubernetes clusters without load balancers.

```yaml
service-type: ClusterIP  # This is the default
```

**URL Output:** Returns internal DNS name: `http://myapp.namespace.svc.cluster.local`

**Use Cases:**
- VPC Kubernetes clusters without load balancer support
- Internal services not exposed externally
- Services accessed through Ingress or API Gateway
- Microservices communication within cluster

### NodePort

Exposes the service on each node's IP at a static port (30000-32767):

```yaml
service-type: NodePort
```

**URL Output:** Returns `http://<node-ip>:<node-port>`

**Use Cases:**
- Development and testing
- Direct access to services without load balancer
- Clusters with accessible node IPs

### LoadBalancer

Automatically provisions an external IP/hostname (requires cloud provider support):

```yaml
service-type: LoadBalancer
```

**URL Output:** Returns `http://<external-ip>` (if load balancer is provisioned)

**Use Cases:**
- Classic Kubernetes clusters with load balancer support
- Production deployments requiring external access
- Cloud providers with load balancer integration

**Note:** VPC clusters may not support LoadBalancer type. Use ClusterIP with Ingress instead.

## OpenShift Routes

For OpenShift clusters, routes are automatically created:

```yaml
cluster-type: openshift
create-route: true
route-hostname: myapp.apps.cluster.example.com  # Optional
```

## Troubleshooting

### Readiness/Liveness Probe Failures

If pods are failing readiness or liveness probes:

1. **Check if your application has health endpoints:**
   ```bash
   # Test the endpoint locally
   curl http://localhost:8080/health
   ```

2. **Disable probes if your app doesn't have health endpoints:**
   ```yaml
   enable-probes: false
   ```

3. **Configure correct probe paths:**
   ```yaml
   enable-probes: true
   readiness-probe-path: /ready  # Your actual readiness endpoint
   liveness-probe-path: /health  # Your actual liveness endpoint
   ```

4. **Check pod logs for errors:**
   ```bash
   kubectl logs <pod-name> -n <namespace>
   kubectl describe pod <pod-name> -n <namespace>
   ```

5. **Common probe issues:**
   - Application takes too long to start (increase `initialDelaySeconds`)
   - Health endpoint returns non-200 status code
   - Application is listening on wrong port
   - Health endpoint path is incorrect (404 errors)

### Image Pull Errors (ImagePullBackOff)

If pods fail to start with `ImagePullBackOff` or `ErrImagePull`:

1. **For IBM Cloud Container Registry images:**
   - Ensure you're providing `ibmcloud-apikey` input
   - Verify the API key has Container Registry Reader permissions
   - Check that the image exists in the registry
   - Verify the image path is correct (e.g., `us.icr.io/namespace/image:tag`)

2. **Check the image pull secret:**
   ```bash
   kubectl get secret icr-secret -n <namespace>
   kubectl describe pod <pod-name> -n <namespace>
   ```

3. **Manually test image pull:**
   ```bash
   kubectl run test --image=<your-image> -n <namespace> --rm -it --restart=Never
   ```

### Deployment fails to become ready

- Check pod logs: `kubectl logs <pod-name> -n <namespace>`
- Check pod events: `kubectl describe pod <pod-name> -n <namespace>`
- Verify image exists and is accessible
- Check resource limits are sufficient
- Verify image pull secret is created: `kubectl get secret icr-secret -n <namespace>`

### Health check timeout

- Verify the health check path is correct
- Increase `health-check-timeout`
- Check application logs for startup issues
- Verify the application is listening on the correct port

### Authentication failures

- For kubeconfig: Ensure it's properly base64 encoded
- For IBM Cloud: Verify API key has correct permissions
- Check cluster name and region are correct
- Verify API key has Container Registry access for image pulls

### No application URL

- For LoadBalancer: Wait for external IP assignment (can take several minutes)
- For NodePort: Ensure nodes have external IPs
- For OpenShift: Verify route creation succeeded
- For Ingress: Check ingress controller is installed

## Best Practices

1. **Use specific image tags**: Avoid `latest` in production
2. **Set resource limits**: Prevent resource exhaustion
3. **Configure health checks**: Ensure proper application monitoring
4. **Use namespaces**: Isolate environments (dev, staging, prod)
5. **Enable TLS**: For production ingress/routes
6. **Monitor deployments**: Check outputs and logs

## License

This project is licensed under the MIT License.

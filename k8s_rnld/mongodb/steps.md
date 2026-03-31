# Detailed Deployment Steps 🚀

Follow these steps exactly in order. Do not skip any steps!

## Step 1: Add Required Helm Repositories
We need to tell Helm where to download the charts for MongoDB, OpenTelemetry, and Sealed Secrets. Run these commands:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
```

## Step 2: Install Sealed Secrets Controller
*If you already have Sealed Secrets installed on your cluster, you can skip this step.*

```bash
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set-string fullnameOverride=sealed-secrets-controller
```
Verify it's running (wait until the pod says `Running`):
```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=sealed-secrets
```

## Step 3: Create the Namespace
We will deploy everything into the `fit-forge` namespace.

```bash
kubectl apply -f k8s/mongo/namespace.yaml
```

## Step 4: Note Down Your Passwords
The `k8s/mongo/mongodb-secret.yaml` file has already automatically been updated with secure, randomly generated passwords for you!

You MUST save the following two passwords somewhere safe (like a password manager), because you will need them to connect your microservices to the database later:
- **Root Password** (for admin access)
- **App Password** (for your microservices)

You can view them by looking inside `k8s/mongo/mongodb-secret.yaml` right now.

## Step 5: Seal the Secret
Now we encrypt the secret so it's safe. Run `kubeseal`:

## Install kubeseal using chatgpt.

```bash
kubeseal --format yaml \
  --controller-name sealed-secrets-controller \
  --controller-namespace kube-system \
  < k8s/mongo/mongodb-secret.yaml \
  > k8s/mongo/mongodb-sealed-secret.yaml
```

**Immediately delete the plaintext secret file so you don't accidentally commit it:**
```bash
rm k8s/mongo/mongodb-secret.yaml
```

## Step 6: Apply the Sealed Secret
Send the encrypted secret to Kubernetes. The controller will decrypt it in the background.

```bash
kubectl apply -f k8s/mongo/mongodb-sealed-secret.yaml
```

Verify it worked (you should see a secret named `mongodb-secret`):
```bash
kubectl get secret mongodb-secret -n fit-forge
```

## Step 7: Deploy MongoDB
Now we deploy the 3-node MongoDB ReplicaSet using our custom values file.

```bash
helm install mongodb bitnami/mongodb \
  --namespace fit-forge \
  --values k8s/mongo/mongodb-values.yaml
```

**Wait for MongoDB to start.** This can take 3-5 minutes. You can watch the progress with:
```bash
kubectl get pods -n fit-forge -w
```
Wait until `mongodb-0`, `mongodb-1`, and `mongodb-2` all show `2/2` in the READY column. Press `Ctrl+C` to stop watching.

## Step 8: Deploy OpenTelemetry Collector
Deploy the OTel Collector to start scraping metrics from MongoDB.

```bash
helm install otel-collector open-telemetry/opentelemetry-collector \
  --namespace fit-forge \
  --values k8s/otel/otel-collector-values.yaml
```

## Step 9: Final Verification
Run these commands to verify your deployment is healthy:

1. **Check the Replica Set Status:**
   ```bash
   kubectl exec -it mongodb-0 -n fit-forge -- mongosh --eval "rs.status()"
   ```
   *(Look for members being PRIMARY or SECONDARY without errors)*

2. **Check the OTel Collector Logs:**
   ```bash
   kubectl logs -l app.kubernetes.io/name=opentelemetry-collector -n fit-forge --tail=20
   ```
   *(You should see metric logs being printed out)*

You are done! Your microservices can now connect using the `mongodb.fit-forge.svc.cluster.local` address.
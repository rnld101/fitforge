# 🏋️ FitForge — Kubernetes Deployment Guide

Production-ready Kubernetes manifests for the FitForge microservices fitness platform.

---

## 📐 Architecture Overview

```
                                    ┌─────────────────────────────────────────────────────────┐
                                    │                    Namespace: fitforge                   │
                                    │                                                         │
  Users ──► NodePort ──►┌───────────┤                                                         │
                        │ Frontend  │   nginx (React SPA + API proxy)                         │
                        │ :3000     │     │                                                   │
                        └───────────┤     │  /api/auth/      → auth-service:5001              │
                                    │     │  /api/users/     → user-service:5002              │
                                    │     │  /api/workout/   → workout-service:5003           │
                                    │     │  /api/nutrition/ → nutrition-service:5004          │
                                    │     │  /api/progress/  → progress-service:5005          │
                                    │     │  /api/ai/        → ai-agent-service:5006          │
                                    │     │                                                   │
                                    │     ▼                                                   │
                                    │  ┌──────────────────┐  ┌───────────────────┐            │
                                    │  │  auth-service     │  │  user-service     │            │
                                    │  │  :5001 (Node.js)  │  │  :5002 (Node.js)  │            │
                                    │  └────────┬─────────┘  └────────┬──────────┘            │
                                    │           │                     │                       │
                                    │  ┌────────┴─────────┐  ┌───────┴──────────┐             │
                                    │  │ workout-service   │  │ nutrition-service│             │
                                    │  │ :5003 (Node.js)   │  │ :5004 (Node.js)  │             │
                                    │  └────────┬─────────┘  └────────┬──────────┘            │
                                    │           │                     │                       │
                                    │  ┌────────┴─────────┐  ┌───────┴──────────┐             │
                                    │  │ progress-service  │  │ ai-agent-service │             │
                                    │  │ :5005 (Node.js)   │  │ :5006 (Python)   │             │
                                    │  └──┬─────┬─────────┘  └──────────────────┘             │
                                    │     │     │                                             │
                                    │     │     ▼                                             │
                                    │     │  ┌──────────┐                                     │
                                    │     │  │  Redis    │  (cache, Deployment)                │
                                    │     │  │  :6379    │                                     │
                                    │     │  └──────────┘                                     │
                                    │     │                                                   │
                                    │     ▼                                                   │
                                    │  ┌──────────────────────────────────────────┐            │
                                    │  │       MongoDB Replica Set (rs0)          │            │
                                    │  │       StatefulSet — 3 replicas           │            │
                                    │  │                                          │            │
                                    │  │   mongo-0 (PRIMARY)                      │            │
                                    │  │   mongo-1 (SECONDARY)                    │            │
                                    │  │   mongo-2 (SECONDARY)                    │            │
                                    │  │                                          │            │
                                    │  │   PVC: mongo-data-mongo-0  (5Gi)         │            │
                                    │  │   PVC: mongo-data-mongo-1  (5Gi)         │            │
                                    │  │   PVC: mongo-data-mongo-2  (5Gi)         │            │
                                    │  └──────────────────────────────────────────┘            │
                                    │                                                         │
                                    └─────────────────────────────────────────────────────────┘
```

---

## 📁 Folder Structure

```
k8s_rnld/
├── namespace/
│   └── namespace.yaml                 # Namespace: fitforge
│
├── storage/
│   └── storageclass.yaml              # local-path provisioner (+ NFS comments)
│
├── secrets/
│   └── app-secrets.yaml               # ⚠️ JWT_SECRET, GOOGLE_API_KEY, LLM_MODEL
│
├── mongodb/
│   ├── configmap.yaml                 # Replica set init script (rs-init.sh)
│   ├── service-headless.yaml          # Headless service (stable pod DNS)
│   ├── service.yaml                   # ClusterIP for general access
│   ├── statefulset.yaml               # 3-replica StatefulSet with PVCs
│   └── init-job.yaml                  # Job: auto-initializes rs.initiate()
│
├── redis/
│   ├── deployment.yaml                # Single-replica cache
│   └── service.yaml                   # ClusterIP :6379
│
├── microservices/
│   ├── auth-service/                  # JWT signup/login/verify
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── user-service/                  # User profiles
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── workout-service/               # Workout plans
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── nutrition-service/             # Diet/nutrition logs
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   ├── progress-service/              # Progress tracking (+ Redis)
│   │   ├── configmap.yaml
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   └── ai-agent-service/             # LangChain chatbot (Python/FastAPI)
│       ├── configmap.yaml
│       ├── deployment.yaml
│       └── service.yaml
│
├── frontend/
│   ├── deployment.yaml                # React SPA + nginx proxy
│   └── service.yaml                   # NodePort (external access)
│
├── deploy.sh                          # One-command ordered deployment
└── README.md                          # This file
```

---

## ⚠️ Prerequisites

Before deploying, ensure you have:

1. **Kubernetes cluster** running (kubeadm, k3s, minikube, etc.)
2. **kubectl** configured and pointing to your cluster
3. **local-path-provisioner** installed (deploy.sh installs it automatically)
4. **Docker images** built and pushed to a registry

---

## 🔑 IMPORTANT: Update Secrets Before Deploying

Edit `secrets/app-secrets.yaml` and replace the placeholder values:

```yaml
stringData:
  JWT_SECRET: "YOUR-REAL-JWT-SECRET-HERE"         # Generate: openssl rand -base64 48
  GOOGLE_API_KEY: "YOUR-REAL-GOOGLE-API-KEY"      # Get from: https://ai.google.dev/
  LLM_MODEL: "gemini-2.5-flash-lite"              # Or your preferred Gemini model
```

> **⚠️ Do NOT deploy with the default placeholder values!**
> - `JWT_SECRET` is required by: auth-service, user-service, workout-service
> - `GOOGLE_API_KEY` is required by: ai-agent-service (LangChain chatbot)

---

## 🐳 Build & Push Docker Images

Build and push all service images before deploying to Kubernetes:

```bash
# Set your registry prefix (replace with your Docker Hub username or private registry)
REGISTRY="fitforge"

# Build and push each service
docker build -t ${REGISTRY}/auth-service:latest      ./services/auth-service
docker build -t ${REGISTRY}/user-service:latest      ./services/user-service
docker build -t ${REGISTRY}/workout-service:latest   ./services/workout-service
docker build -t ${REGISTRY}/nutrition-service:latest  ./services/nutrition-service
docker build -t ${REGISTRY}/progress-service:latest  ./services/progress-service
docker build -t ${REGISTRY}/ai-agent-service:latest  ./services/ai-agent-service
docker build -t ${REGISTRY}/frontend:latest          ./frontend

# Push all images
for svc in auth-service user-service workout-service nutrition-service progress-service ai-agent-service frontend; do
  docker push ${REGISTRY}/${svc}:latest
done
```

> If using a private registry, update the `image:` field in each deployment YAML accordingly.

---

## 🚀 Deployment

### Option A: Automated Script (Recommended)

```bash
cd k8s_rnld/
chmod +x deploy.sh
./deploy.sh
```

The script:
1. Checks prerequisites (kubectl, cluster connectivity)
2. Installs local-path-provisioner if missing
3. Creates namespace
4. Applies StorageClass and Secrets
5. Deploys MongoDB StatefulSet and waits for pods
6. Runs the replica set init Job and waits for completion
7. Deploys Redis, all microservices, and frontend
8. Prints verification summary

### Option B: Manual Step-by-Step

```bash
cd k8s_rnld/

# 1. Create namespace
kubectl apply -f namespace/

# 2. Apply StorageClass
kubectl apply -f storage/

# 3. Apply secrets (update values first!)
kubectl apply -f secrets/

# 4. Deploy MongoDB
kubectl apply -f mongodb/configmap.yaml
kubectl apply -f mongodb/service-headless.yaml
kubectl apply -f mongodb/service.yaml
kubectl apply -f mongodb/statefulset.yaml

# 5. Wait for all MongoDB pods
kubectl rollout status statefulset/mongo -n fitforge --timeout=300s

# 6. Initialize replica set
kubectl apply -f mongodb/init-job.yaml
kubectl wait --for=condition=complete job/mongo-rs-init -n fitforge --timeout=180s

# 7. Deploy Redis
kubectl apply -f redis/

# 8. Deploy microservices
kubectl apply -f microservices/auth-service/
kubectl apply -f microservices/user-service/
kubectl apply -f microservices/workout-service/
kubectl apply -f microservices/nutrition-service/
kubectl apply -f microservices/progress-service/
kubectl apply -f microservices/ai-agent-service/

# 9. Deploy frontend
kubectl apply -f frontend/
```

### Option C: One-liner (kubectl recursive)

```bash
cd k8s_rnld/
kubectl apply -R -f .
```

> **Note:** With this approach, all resources are applied simultaneously. kubectl sorts by
> resource kind (Namespace → Secret → ConfigMap → Service → Deployment → StatefulSet → Job),
> so ordering is mostly correct. Microservices may restart once while waiting for MongoDB
> to form the replica set — they self-heal automatically.

---

## ✅ Verification

### 1. Check all pods are running

```bash
kubectl get pods -n fitforge
```

**Expected output:**
```
NAME                                READY   STATUS      RESTARTS   AGE
mongo-0                             1/1     Running     0          2m
mongo-1                             1/1     Running     0          2m
mongo-2                             1/1     Running     0          2m
mongo-rs-init-xxxxx                 0/1     Completed   0          1m
redis-xxxxxxxxxx-xxxxx              1/1     Running     0          1m
auth-service-xxxxxxxxxx-xxxxx       1/1     Running     0          1m
user-service-xxxxxxxxxx-xxxxx       1/1     Running     0          1m
workout-service-xxxxxxxxxx-xxxxx    1/1     Running     0          1m
nutrition-service-xxxxxxxxxx-xxxxx  1/1     Running     0          1m
progress-service-xxxxxxxxxx-xxxxx   1/1     Running     0          1m
ai-agent-service-xxxxxxxxxx-xxxxx   1/1     Running     0          1m
frontend-xxxxxxxxxx-xxxxx           1/1     Running     0          1m
```

### 2. Check PVCs are bound

```bash
kubectl get pvc -n fitforge
```

**Expected output:**
```
NAME                  STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
mongo-data-mongo-0    Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   5Gi        RWO            fitforge-storage
mongo-data-mongo-1    Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   5Gi        RWO            fitforge-storage
mongo-data-mongo-2    Bound    pvc-xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx   5Gi        RWO            fitforge-storage
```

### 3. Verify MongoDB Replica Set

```bash
# Check replica set status
kubectl exec -n fitforge mongo-0 -- mongosh --eval "rs.status().members.forEach(m => print(m.name + ' → ' + m.stateStr))" --quiet
```

**Expected output:**
```
mongo-0.mongo-headless.fitforge.svc.cluster.local:27017 → PRIMARY
mongo-1.mongo-headless.fitforge.svc.cluster.local:27017 → SECONDARY
mongo-2.mongo-headless.fitforge.svc.cluster.local:27017 → SECONDARY
```

### 4. Test data replication

```bash
# Insert test data on PRIMARY
kubectl exec -n fitforge mongo-0 -- mongosh --eval '
  use test_replication;
  db.verify.insertOne({ msg: "hello from mongo-0", ts: new Date() });
  print("Inserted on PRIMARY");
' --quiet

# Read from SECONDARY (mongo-1)
kubectl exec -n fitforge mongo-1 -- mongosh --eval '
  db.getMongo().setReadPref("secondary");
  use test_replication;
  printjson(db.verify.find().toArray());
' --quiet

# Read from SECONDARY (mongo-2)
kubectl exec -n fitforge mongo-2 -- mongosh --eval '
  db.getMongo().setReadPref("secondary");
  use test_replication;
  printjson(db.verify.find().toArray());
' --quiet
```

### 5. Check services

```bash
kubectl get svc -n fitforge
```

### 6. Access the application

```bash
# Get the NodePort
kubectl get svc frontend -n fitforge -o jsonpath='{.spec.ports[0].nodePort}'

# Access at: http://<NODE_IP>:<NODE_PORT>
```

---

## 🔧 Troubleshooting

### Pod stuck in `Pending`

```bash
kubectl describe pod <pod-name> -n fitforge
```

Common causes:
- **PVC not binding**: Check if local-path-provisioner is running: `kubectl get pods -n local-path-storage`
- **Insufficient resources**: Check node capacity: `kubectl describe node`

### Pod in `CrashLoopBackOff`

```bash
kubectl logs <pod-name> -n fitforge
kubectl logs <pod-name> -n fitforge --previous   # Previous crash logs
```

Common causes:
- **MongoDB not ready**: Microservices crash if MongoDB replica set isn't formed yet. Wait for the init Job to complete.
- **Wrong secrets**: Check `JWT_SECRET` or `GOOGLE_API_KEY` values.
- **Image not found**: Make sure images are pushed to the registry.

### MongoDB replica set not initializing

```bash
# Check init job logs
kubectl logs -n fitforge -l app.kubernetes.io/name=mongo-rs-init

# Manual initialization (if Job failed)
kubectl exec -n fitforge mongo-0 -- mongosh --eval '
  rs.initiate({
    _id: "rs0",
    members: [
      { _id: 0, host: "mongo-0.mongo-headless.fitforge.svc.cluster.local:27017" },
      { _id: 1, host: "mongo-1.mongo-headless.fitforge.svc.cluster.local:27017" },
      { _id: 2, host: "mongo-2.mongo-headless.fitforge.svc.cluster.local:27017" }
    ]
  })
'
```

### Frontend can't reach backend services

```bash
# Test DNS resolution inside the cluster
kubectl exec -n fitforge <frontend-pod> -- nslookup auth-service.fitforge.svc.cluster.local

# Test service connectivity
kubectl exec -n fitforge <frontend-pod> -- wget -qO- http://auth-service:5001/auth/health
```

### Re-deploying after changes

```bash
# Delete the old init Job (Jobs are immutable)
kubectl delete job mongo-rs-init -n fitforge --ignore-not-found

# Re-run the deploy script
./deploy.sh
```

---

## 🔄 Storage Migration: local-path → NFS

### Why migrate?

| Feature | local-path | NFS |
|---------|-----------|-----|
| Data locality | Node-bound | Network-shared |
| Pod rescheduling | Data lost if pod moves to different node | Data accessible from any node |
| Multi-node clusters | ⚠️ Risky | ✅ Recommended |
| Setup complexity | Simple | Requires NFS server |

### Migration Steps

#### 1. Install NFS CSI Driver

```bash
# Install NFS CSI driver
kubectl apply -f https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/install-driver.sh
# Or via Helm:
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs --namespace kube-system
```

#### 2. Update StorageClass

Replace the contents of `storage/storageclass.yaml`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fitforge-storage
  labels:
    app.kubernetes.io/part-of: fitforge
provisioner: nfs.csi.k8s.io
reclaimPolicy: Retain                    # ← Change to Retain for production!
volumeBindingMode: Immediate
parameters:
  server: <NFS_SERVER_IP>               # Your NFS server IP
  share: /srv/nfs/fitforge              # NFS export path
mountOptions:
  - nfsvers=4.1
```

#### 3. Migrate MongoDB Data

```bash
# 1. Scale down MongoDB
kubectl scale statefulset mongo -n fitforge --replicas=0

# 2. Delete old PVCs (data on local-path will be lost!)
kubectl delete pvc mongo-data-mongo-0 mongo-data-mongo-1 mongo-data-mongo-2 -n fitforge

# 3. Delete and re-apply the StorageClass
kubectl delete storageclass fitforge-storage
kubectl apply -f storage/storageclass.yaml

# 4. Scale MongoDB back up (new PVCs will use NFS)
kubectl scale statefulset mongo -n fitforge --replicas=3

# 5. Wait for pods and re-initialize replica set
kubectl rollout status statefulset/mongo -n fitforge --timeout=300s
kubectl delete job mongo-rs-init -n fitforge --ignore-not-found
kubectl apply -f mongodb/init-job.yaml
kubectl wait --for=condition=complete job/mongo-rs-init -n fitforge --timeout=180s
```

> **⚠️ Data loss warning**: This migration discards existing local-path data.
> For zero-downtime migration with data preservation, use `mongodump`/`mongorestore`
> to backup and restore data.

#### 4. Verify

```bash
kubectl get pvc -n fitforge    # Should show new PVCs with fitforge-storage (NFS)
kubectl exec -n fitforge mongo-0 -- mongosh --eval "rs.status()" --quiet
```

---

## ⚠️ Production Checklist

Before going to production, update these settings:

- [ ] **Secrets**: Replace all placeholder values in `secrets/app-secrets.yaml`
- [ ] **StorageClass**: Change `reclaimPolicy` from `Delete` to `Retain`
- [ ] **MongoDB auth**: Add keyFile authentication for replica set security
- [ ] **Resource limits**: Tune CPU/memory based on actual load testing
- [ ] **Replicas**: Scale microservices beyond 1 replica for HA
- [ ] **Ingress**: Replace NodePort with Ingress controller for proper domain routing
- [ ] **TLS**: Add TLS termination at Ingress level
- [ ] **Monitoring**: Add Prometheus + Grafana for observability
- [ ] **Backups**: Set up automated MongoDB backups (mongodump CronJob)

---

## 📊 Resource Summary

| Component | Replicas | CPU (req/lim) | Memory (req/lim) | Storage |
|-----------|----------|---------------|-------------------|---------|
| MongoDB | 3 | 200m/500m | 256Mi/512Mi | 5Gi × 3 |
| Redis | 1 | 50m/100m | 64Mi/128Mi | — |
| auth-service | 1 | 100m/200m | 128Mi/256Mi | — |
| user-service | 1 | 100m/200m | 128Mi/256Mi | — |
| workout-service | 1 | 100m/200m | 128Mi/256Mi | — |
| nutrition-service | 1 | 100m/200m | 128Mi/256Mi | — |
| progress-service | 1 | 100m/200m | 128Mi/256Mi | — |
| ai-agent-service | 1 | 200m/500m | 256Mi/512Mi | — |
| frontend | 1 | 50m/100m | 64Mi/128Mi | — |
| **Total** | **12** | **1.1/2.1 cores** | **1.4/2.8 GiB** | **15 GiB** |

---

## 🧹 Teardown

```bash
# Delete everything in the namespace
kubectl delete namespace fitforge

# Delete StorageClass (optional)
kubectl delete storageclass fitforge-storage

# PVCs and PVs are deleted automatically (reclaimPolicy: Delete)
```

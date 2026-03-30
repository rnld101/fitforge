#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# FitForge — Kubernetes Deployment Script
#
# Deploys all resources in the correct order:
#   1. Namespace → 2. Storage → 3. Secrets → 4. MongoDB → 5. Redis
#   6. Microservices → 7. Frontend
#
# Usage:
#   chmod +x deploy.sh
#   ./deploy.sh
#
# Prerequisites:
#   - kubectl configured and pointing to your cluster
#   - local-path-provisioner installed (or install via this script)
#   - Docker images built and pushed (see README.md)
#   - Secrets updated in secrets/app-secrets.yaml
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

NAMESPACE="fitforge"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

log()   { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          FitForge — Kubernetes Deployment                   ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ── Pre-flight checks ─────────────────────────────────────────────────────
if ! command -v kubectl &> /dev/null; then
  error "kubectl not found. Please install kubectl first."
  exit 1
fi

if ! kubectl cluster-info &> /dev/null; then
  error "Cannot connect to Kubernetes cluster. Check your kubeconfig."
  exit 1
fi

log "Connected to Kubernetes cluster"

# ── Check if local-path-provisioner is installed ───────────────────────────
if ! kubectl get storageclass local-path &> /dev/null 2>&1; then
  warn "local-path StorageClass not found."
  warn "Installing Rancher local-path-provisioner..."
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.26/deploy/local-path-storage.yaml
  echo "   Waiting 10s for provisioner to start..."
  sleep 10
  log "local-path-provisioner installed"
else
  log "local-path-provisioner already installed"
fi

# ── Step 1: Namespace ──────────────────────────────────────────────────────
echo ""
echo "── Step 1/7: Creating Namespace ──────────────────────────────"
kubectl apply -f namespace/
log "Namespace '${NAMESPACE}' created"

# ── Step 2: StorageClass ──────────────────────────────────────────────────
echo ""
echo "── Step 2/7: Applying StorageClass ───────────────────────────"
kubectl apply -f storage/
log "StorageClass 'fitforge-storage' applied"

# ── Step 3: Secrets ───────────────────────────────────────────────────────
echo ""
echo "── Step 3/7: Applying Secrets ────────────────────────────────"
kubectl apply -f secrets/
log "Application secrets applied"
warn "REMINDER: Update secrets/app-secrets.yaml with real values!"
warn "  → JWT_SECRET: openssl rand -base64 48"
warn "  → GOOGLE_API_KEY: https://ai.google.dev/"

# ── Step 4: MongoDB ──────────────────────────────────────────────────────
echo ""
echo "── Step 4/7: Deploying MongoDB StatefulSet ───────────────────"
kubectl apply -f mongodb/configmap.yaml
kubectl apply -f mongodb/service-headless.yaml
kubectl apply -f mongodb/service.yaml
kubectl apply -f mongodb/statefulset.yaml
log "MongoDB StatefulSet applied (3 replicas)"

echo "   Waiting for MongoDB pods to be ready..."
kubectl rollout status statefulset/mongo -n ${NAMESPACE} --timeout=300s
log "All MongoDB pods are running"

# ── Step 4b: Initialize Replica Set ──────────────────────────────────────
echo ""
echo "   Initializing MongoDB Replica Set..."
# Delete old init job if it exists (Jobs are immutable)
kubectl delete job mongo-rs-init -n ${NAMESPACE} --ignore-not-found 2>/dev/null
kubectl apply -f mongodb/init-job.yaml

echo "   Waiting for replica set initialization..."
kubectl wait --for=condition=complete job/mongo-rs-init -n ${NAMESPACE} --timeout=180s
log "MongoDB Replica Set initialized successfully"

# ── Step 5: Redis ────────────────────────────────────────────────────────
echo ""
echo "── Step 5/7: Deploying Redis ─────────────────────────────────"
kubectl apply -f redis/
log "Redis deployed"

# ── Step 6: Microservices ────────────────────────────────────────────────
echo ""
echo "── Step 6/7: Deploying Microservices ─────────────────────────"
for svc in auth-service user-service workout-service nutrition-service progress-service ai-agent-service; do
  kubectl apply -f microservices/${svc}/
  log "  ${svc} deployed"
done

# ── Step 7: Frontend ─────────────────────────────────────────────────────
echo ""
echo "── Step 7/7: Deploying Frontend ──────────────────────────────"
kubectl apply -f frontend/
log "Frontend deployed"

# ── Verification ─────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                   Deployment Complete!                      ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

echo "── Pod Status ────────────────────────────────────────────────"
sleep 5
kubectl get pods -n ${NAMESPACE} -o wide
echo ""

echo "── Services ──────────────────────────────────────────────────"
kubectl get svc -n ${NAMESPACE}
echo ""

echo "── PVCs ──────────────────────────────────────────────────────"
kubectl get pvc -n ${NAMESPACE}
echo ""

echo "── MongoDB Replica Set Status ────────────────────────────────"
kubectl exec -n ${NAMESPACE} mongo-0 -- mongosh --eval "rs.status().members.forEach(m => print('  ' + m.name + ' → ' + m.stateStr))" --quiet 2>/dev/null || warn "MongoDB RS status check will be available once pods stabilize"
echo ""

NODEPORT=$(kubectl get svc frontend -n ${NAMESPACE} -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "pending")
log "Frontend accessible at: http://<NODE_IP>:${NODEPORT}"
echo ""
warn "If pods are still starting, wait 30-60 seconds and run:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo ""

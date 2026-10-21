#!/bin/bash

# ============================================
# Setup Traefik + OAuth2 Proxy + Apache
# Namespace: progetto
# Host: localhost
# ============================================

set -e

echo "🚀 Inizio setup del sistema..."
echo ""

# Colori per output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# ============================================
# 1. APPLICA I MANIFESTI TRAEFIK
# ============================================
echo -e "${YELLOW}📦 Step 1: Applicazione manifesti Traefik...${NC}"

kubectl apply -f - <<'YAML'
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: oauth2-forwardauth
  namespace: progetto
spec:
  forwardAuth:
    address: http://mio-oauth2-oauth2-proxy.progetto.svc.cluster.local/oauth2/auth
    trustForwardHeader: true
    authResponseHeaders:
      - X-Auth-Request-User
      - X-Auth-Request-Email
---
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: oauth2-errors
  namespace: progetto
spec:
  errors:
    status:
      - "401"
    service:
      name: mio-oauth2-oauth2-proxy
      port: 80
    query: "/oauth2/sign_in?rd={url}"
    statusRewrites:
      "401": 302
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: oauth2-endpoints
  namespace: progetto
spec:
  entryPoints:
    - web
  routes:
    - match: "Host(`localhost`) && PathPrefix(`/oauth2/`)"
      kind: Rule
      priority: 100
      services:
        - name: mio-oauth2-oauth2-proxy
          port: 80
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: apache-protetto
  namespace: progetto
spec:
  entryPoints:
    - web
  routes:
    - match: "Host(`localhost`)"
      kind: Rule
      priority: 10
      middlewares:
        - name: oauth2-errors
        - name: oauth2-forwardauth
      services:
        - name: mio-apache
          port: 80
YAML

echo -e "${GREEN}✅ Manifesti Traefik applicati${NC}"
echo ""

# ============================================
# 2. VERIFICA STATO RISORSE
# ============================================
echo -e "${YELLOW}🔍 Step 2: Verifica stato risorse...${NC}"
echo ""

# 2.1 Verifica Namespace
echo -e "${YELLOW}📋 Namespace:${NC}"
kubectl get namespace progetto 2>/dev/null && echo -e "${GREEN}✅ Namespace 'progetto' esiste${NC}" || echo -e "${RED}❌ Namespace 'progetto' NON trovato${NC}"
echo ""

# 2.2 Verifica Middleware
echo -e "${YELLOW}🔧 Middleware:${NC}"
kubectl get middleware -n progetto 2>/dev/null || echo -e "${YELLOW}⚠️  Nessun middleware trovato${NC}"
echo ""

# 2.3 Verifica IngressRoute
echo -e "${YELLOW}📡 IngressRoute:${NC}"
kubectl get ingressroute -n progetto 2>/dev/null || echo -e "${YELLOW}⚠️  Nessun IngressRoute trovato${NC}"
echo ""

# 2.4 Verifica Pods
echo -e "${YELLOW}🐳 Pods:${NC}"
kubectl get pods -n progetto 2>/dev/null || echo -e "${YELLOW}⚠️  Nessun pod trovato${NC}"
echo ""

# 2.5 Verifica Servizi
echo -e "${YELLOW}🌐 Servizi:${NC}"
kubectl get svc -n progetto 2>/dev/null || echo -e "${YELLOW}⚠️  Nessun servizio trovato${NC}"
echo ""

# ============================================
# 3. VERIFICA DETTAGLIATA COMPONENTI
# ============================================
echo -e "${YELLOW}🔍 Step 3: Verifica dettagliata componenti...${NC}"
echo ""

# 3.1 Verifica Apache
echo -e "${YELLOW}📦 Apache:${NC}"
if kubectl get pod -l app.kubernetes.io/name=apache -n progetto 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✅ Apache è in esecuzione${NC}"
else
    echo -e "${RED}❌ Apache NON è in esecuzione${NC}"
    echo -e "${YELLOW}💡 Installa con:${NC}"
    echo "   helm install mio-apache oci://registry-1.docker.io/bitnamicharts/apache -n progetto --set image.repository=bitnamilegacy/apache --set image.tag=latest"
fi
echo ""

# 3.2 Verifica MariaDB
echo -e "${YELLOW}📦 MariaDB:${NC}"
if kubectl get pod -l app.kubernetes.io/name=mariadb -n progetto 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✅ MariaDB è in esecuzione${NC}"
else
    echo -e "${RED}❌ MariaDB NON è in esecuzione${NC}"
    echo -e "${YELLOW}💡 Installa con:${NC}"
    echo "   helm install mio-mariadb bitnami/mariadb -n progetto --set auth.rootPassword=Admin1234! --set image.repository=bitnamilegacy/mariadb --set global.security.allowInsecureImages=true --set auth.database=miodb --set auth.username=adim --set auth.password=Admin1234!"
fi
echo ""

# 3.3 Verifica OAuth2 Proxy
echo -e "${YELLOW}📦 OAuth2 Proxy:${NC}"
if kubectl get pod -l app.kubernetes.io/name=oauth2-proxy -n progetto 2>/dev/null | grep -q "Running"; then
    echo -e "${GREEN}✅ OAuth2 Proxy è in esecuzione${NC}"
else
    echo -e "${RED}❌ OAuth2 Proxy NON è in esecuzione${NC}"
    echo -e "${YELLOW}💡 Installa con:${NC}"
    echo "   helm install mio-oauth2 oauth2-proxy/oauth2-proxy -n progetto --set config.clientID=<CLIENT_ID> --set config.clientSecret=<CLIENT_SECRET> --set config.cookieSecret=<COOKIE_SECRET>"
fi
echo ""

# ============================================
# 4. TEST CONNESSIONE
# ============================================
echo -e "${YELLOW}🧪 Step 4: Test connessione...${NC}"
echo ""

# Test Apache
echo -e "${YELLOW}🌐 Test Apache (localhost:80):${NC}"
if curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null | grep -q "200\|302"; then
    echo -e "${GREEN}✅ Apache risponde${NC}"
else
    echo -e "${YELLOW}⚠️  Apache non risponde (potrebbe essere dietro OAuth2)${NC}"
fi
echo ""

# Test OAuth2 Proxy
echo -e "${YELLOW}🔐 Test OAuth2 Proxy (/oauth2/auth):${NC}"
if curl -s -o /dev/null -w "%{http_code}" http://localhost/oauth2/auth 2>/dev/null | grep -q "200\|401"; then
    echo -e "${GREEN}✅ OAuth2 Proxy risponde${NC}"
else
    echo -e "${YELLOW}⚠️  OAuth2 Proxy non raggiungibile${NC}"
fi
echo ""

# ============================================
# 5. LOG UTILI
# ============================================
echo -e "${YELLOW}📝 Step 5: Comandi per log...${NC}"
echo ""
echo -e "Per vedere i log di Traefik:"
echo "   kubectl logs -l app.kubernetes.io/name=traefik -f"
echo ""
echo -e "Per vedere i log di OAuth2 Proxy:"
echo "   kubectl logs -l app.kubernetes.io/name=oauth2-proxy -n progetto -f"
echo ""
echo -e "Per vedere i log di Apache:"
echo "   kubectl logs -l app.kubernetes.io/name=apache -n progetto -f"
echo ""

# ============================================
# 6. RIEPILOGO FINALE
# ============================================
echo "=========================================="
echo -e "${GREEN}🎉 Setup completato!${NC}"
echo "=========================================="
echo ""
echo -e "📍 Namespace: ${GREEN}progetto${NC}"
echo -e "🌐 Host: ${GREEN}localhost${NC}"
echo ""
echo -e "🔗 URL utili:"
echo "   • Apache (protetto): http://localhost"
echo "   • Login OAuth2: http://localhost/oauth2/sign_in"
echo "   • Logout: http://localhost/oauth2/sign_out"
echo ""
echo -e "📋 Comandi utili:"
echo "   • Verifica pod: kubectl get pods -n progetto"
echo "   • Verifica servizi: kubectl get svc -n progetto"
echo "   • Verifica middleware: kubectl get middleware -n progetto"
echo "   • Verifica rotte: kubectl get ingressroute -n progetto"
echo ""
echo -e "${YELLOW}⚠️  Nota: Se OAuth2 Proxy non è configurato,Apache non sarà accessibile!${NC}"
echo ""
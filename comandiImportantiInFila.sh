helm upgrade mio-apache   oci://registry-1.docker.io/bitnamicharts/apache   --version 11.4.29   -n progetto --reuse-values   --set image.repository=bitnamilegacy/apache   --set image.tag=2.4.65-debian-12-r2   --set global.security.allowInsecureImages=true

helm upgrade mio-keycloak   oci://registry-1.docker.io/bitnamicharts/keycloak   --version 25.2.0   -n progetto   --reuse-values   --set image.repository=bitnamilegacy/keycloak   --set image.tag=26.3.3-debian-12-r0   --set postgresql.image.repository=bitnamilegacy/postgresql   --set postgresql.image.tag=17.6.0-debian-12-r0   --set global.security.allowInsecureImages=true

helm upgrade mio-keycloak   oci://registry-1.docker.io/bitnamicharts/keycloak   --version 25.2.0   -n progetto   --reuse-values   --set image.repository=bitnamilegacy/keycloak   --set image.tag=26.3.3-debian-12-r0   --set postgresql.image.repository=bitnamilegacy/postgresql   --set postgresql.image.tag=17.6.0-debian-12-r0   --set global.security.allowInsecureImages=true

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
    - match: "Host(`<HOST_APP>`) && PathPrefix(`/oauth2/`)"
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
    - match: "Host(`<HOST_APP>`)"
      kind: Rule
      priority: 10
      middlewares:
        - name: oauth2-errors
        - name: oauth2-forwardauth
      services:
        - name: mio-apache
          port: 80
YAML

# Setting LINKERD2_VERSION sets the version to install.
# If unset, you'll get the latest available edge version.
export LINKERD2_VERSION=edge-26.10.1
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install-edge | sh
export PATH=$PATH:/home/fra/.linkerd2/bin
linkerd check --pre
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -
linkerd install --set proxyInit.runAsRoot=true | kubectl apply -f -
kubectl get ns
linkerd install | kubectl apply -f -
linkerd check
linkerd version
linkerd check --pre
kubectl get crds/httproutes.gateway.networking.k8s.io -o "jsonpath={.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}"
kubectl config current-context
linkerd version

kubectl patch ingressroute apache-protetto -n progetto --type='json'   -p='[{"op":"replace","path":"/spec/routes/0/match","value":"Host(`localhost`)"}]'
kubectl patch ingressroute oauth2-endpoints -n progetto --type='json'   -p='[{"op":"replace","path":"/spec/routes/0/match","value":"Host(`localhost`) && PathPrefix(`/oauth2/`)"}]'

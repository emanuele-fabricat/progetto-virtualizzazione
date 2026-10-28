#!/bin/bash

#Modifica YAML treafik per il redirectory delle rotte
	
set -e

minikube kubectl -- apply -f - <<'YAML'
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
---
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: keycloak-public
  namespace: progetto
spec:
  entryPoints:
    - web
  routes:
    - match: Host(`keycloak.localhost`)
      kind: Rule
      services:
        - name: mio-keycloak
          port: 80
YAML

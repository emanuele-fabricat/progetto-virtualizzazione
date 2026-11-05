# Comparazione YAML: Ubuntu e Debian

Sono stati confrontati i file nelle cartelle [YamlUbuntu](./YamlUbuntu) e
[YamlDebian](./YamlDebian). Entrambe contengono gli stessi 15 nomi di file.

I manifest includono anche valori generati dal cluster, come `creationTimestamp`,
`resourceVersion`, `uid`, `clusterIP` e `status`. Questi possono differire tra
gli ambienti senza rappresentare una differenza nella configurazione applicativa.

## Differenze file per file

| File | Differenze tra Ubuntu e Debian |
|---|---|
| [`deployments-mio-apache.yaml`](./YamlUbuntu/deployments-mio-apache.yaml) | **Immagine diversa:** Ubuntu usa `bitnamilegacy/apache:latest`; Debian usa la versione fissata `bitnamilegacy/apache:2.4.65-debian-12-r2`. |
| [`deployments-mio-oauth2-oauth2-proxy.yaml`](./YamlUbuntu/deployments-mio-oauth2-oauth2-proxy.yaml) | Cambiano l'URL dell'issuer Keycloak (`192.168.49.2:31119` su Ubuntu, `192.168.49.2:32622` su Debian) e le opzioni: Ubuntu include `--set-xauthrequest=true`, Debian no. Debian ha inoltre l'annotazione `kubectl.kubernetes.io/restartedAt`. |
| [`deployments-traefik.yaml`](./YamlUbuntu/deployments-traefik.yaml) | **Versioni diverse:** immagine Traefik `v3.7.17` e chart `42.3.0` su Ubuntu; immagine `v3.7.13` e chart `41.6.1` su Debian. |
| [`services-mio-apache.yaml`](./YamlUbuntu/services-mio-apache.yaml) | Stessa configurazione di porte e selettori. Cambiano i metadati generati e il `clusterIP`. |
| [`services-mio-keycloak-headless.yaml`](./YamlUbuntu/services-mio-keycloak-headless.yaml) | Configurazione effettiva uguale; cambiano solo i metadati generati dal cluster. |
| [`services-mio-keycloak-postgresql-hl.yaml`](./YamlUbuntu/services-mio-keycloak-postgresql-hl.yaml) | Configurazione effettiva uguale; cambiano solo i metadati generati dal cluster. |
| [`services-mio-keycloak-postgresql.yaml`](./YamlUbuntu/services-mio-keycloak-postgresql.yaml) | Stesse porte e selettori; differiscono il `clusterIP` e i metadati generati. |
| [`services-mio-keycloak.yaml`](./YamlUbuntu/services-mio-keycloak.yaml) | **Tipo di servizio diverso:** Ubuntu usa `NodePort` con porta `31119`; Debian usa `ClusterIP` senza `nodePort`. Cambia anche `externalTrafficPolicy`, presente solo su Ubuntu. Questo si collega alla diversa porta dell'issuer configurata nei manifest OAuth2. |
| [`services-mio-mariadb-headless.yaml`](./YamlUbuntu/services-mio-mariadb-headless.yaml) | Chart MariaDB `28.1.6` su Ubuntu e `28.1.1` su Debian; il resto della configurazione del Service coincide. Cambiano anche i metadati generati. |
| [`services-mio-mariadb.yaml`](./YamlUbuntu/services-mio-mariadb.yaml) | Chart MariaDB `28.1.6` su Ubuntu e `28.1.1` su Debian. Porte e selettori coincidono; `clusterIP` e altri metadati sono specifici del cluster. |
| [`services-mio-oauth2-oauth2-proxy.yaml`](./YamlUbuntu/services-mio-oauth2-oauth2-proxy.yaml) | Stesse porte e selettori; cambiano il `clusterIP` e i metadati generati. |
| [`services-traefik.yaml`](./YamlUbuntu/services-traefik.yaml) | Chart `42.3.0` su Ubuntu e `41.6.1` su Debian. Cambiano anche i `nodePort` per HTTP e HTTPS, oltre al `clusterIP`. |
| [`statefulsets-mio-keycloak-postgresql.yaml`](./YamlUbuntu/statefulsets-mio-keycloak-postgresql.yaml) | Configurazione effettiva e immagine PostgreSQL coincidono; differiscono i metadati, le generazioni e i nomi delle revisioni generate dal cluster. |
| [`statefulsets-mio-keycloak.yaml`](./YamlUbuntu/statefulsets-mio-keycloak.yaml) | Configurazione effettiva uguale, inclusa l'immagine Keycloak; cambiano metadati e revisioni generate dal cluster. |
| [`statefulsets-mio-mariadb.yaml`](./YamlUbuntu/statefulsets-mio-mariadb.yaml) | **Differenze sostanziali:** Ubuntu usa chart `28.1.6`, immagine `bitnamilegacy/mariadb:latest`, database `miodb` e utente `admin`, con secret per la password dell'utente. Debian usa chart `28.1.1`, immagine `bitnami/mariadb:latest`, database `my_database` e non definisce l'utente/password applicativi nel manifest. Cambiano anche il checksum di configurazione e i secret montati. |

## In sintesi

Le differenze operative principali sono nei Deployment di Apache, OAuth2 e
Traefik, nel Service di Keycloak e nello StatefulSet MariaDB. Gli altri file
sono uguali nella configurazione effettiva oppure differiscono per versione
chart e valori generati dal rispettivo cluster.

# Architecture de la plateforme CR465

> **Règle d'équipe :** ce fichier décrit ce qui est **réellement déployé** par
> `compose/docker-compose.yml`. Toute modification du Compose (service, réseau, port,
> middleware) doit être reportée ici dans la même pull request.
> Dernière mise à jour : 3 octobre 2026 — phases 1 et 2 terminées, Keycloak déployé.

## 1. Architecture déployée (état réel)

Seul Traefik est joignable depuis l'extérieur. Les autres services vivent sur des
réseaux Docker internes (`internal: true`), sans accès Internet.

```mermaid
flowchart LR
    user["Poste Windows<br/>navigateur + client SSH"]

    subgraph VM["VM Ubuntu 24.04 · cloud-init · UFW : 22, 80, 443"]
        sshd["sshd (hôte)<br/>clé uniquement · fail2ban"]
        dsock{{"/var/run/docker.sock"}}

        subgraph EXPO["réseau exposition"]
            traefik["Traefik v3.7.13<br/>non-root · lecture seule<br/>80 → redirection 443"]
        end

        subgraph SOCK["réseau socket (interne)"]
            sproxy["socket-proxy v0.5.0<br/>CONTAINERS=1 · POST=0"]
        end

        subgraph APP["réseau applicatif (interne)"]
            portainer["Portainer CE 2.39.5"]
            keycloak["Keycloak 26.7.4<br/>realm cr465"]
        end

        subgraph DATA["réseau donnees (interne)"]
            postgres[("PostgreSQL 17.10<br/>bases : drupal · moodle · keycloak · n8n")]
        end
    end

    user -- "HTTPS 443" --> traefik
    user -- "SSH 2222 → 22" --> sshd
    traefik -- "portainer.cr465.test<br/>IP admin" --> portainer
    traefik -- "auth.cr465.test<br/>/admin : IP admin" --> keycloak
    traefik -- "API Docker en lecture" --> sproxy
    sproxy -- "lecture seule" --> dsock
    portainer -- "API Docker complète<br/>(risque assumé)" --> dsock
    keycloak -- "SQL 5432" --> postgres

    classDef entree fill:#dbe8f7,stroke:#1d4e89,stroke-width:2px;
    classDef donnees fill:#eef3e9,stroke:#4a7a3a;
    class traefik entree;
    class postgres donnees;
```

Le tableau de bord Traefik (`traefik.cr465.test`) est un service interne à Traefik
(`api@internal`), protégé par liste d'IP et mot de passe.

## 2. Architecture cible (fin de projet)

Les éléments en pointillés ne sont pas encore déployés.

```mermaid
flowchart TB
    user["Utilisateur<br/>navigateur"]

    subgraph EXPO["réseau exposition"]
        waf["OpenAppSec<br/>(bonus, mode local)"]
        traefik["Traefik"]
    end

    subgraph APP["réseau applicatif (interne)"]
        drupal["Drupal Commerce<br/>shop.cr465.test"]
        n8n["n8n<br/>n8n.cr465.test"]
        moodle["Moodle<br/>moodle.cr465.test"]
        keycloak["Keycloak<br/>auth.cr465.test"]
        portainer["Portainer CE"]
        grafana["Grafana + Loki"]
    end

    subgraph DATA["réseau donnees (interne)"]
        postgres[("PostgreSQL")]
        redis[("Redis (bonus)")]
    end

    user -- "HTTPS 443" --> traefik
    user -.-> waf
    waf -.-> traefik
    traefik --> drupal & n8n & moodle & keycloak & portainer & grafana
    n8n -- "2 · lit les commandes<br/>JSON:API" --> drupal
    n8n -- "3 · crée + inscrit<br/>web services REST" --> moodle
    moodle -- "4 · SSO OIDC" --> keycloak
    drupal & n8n & moodle & keycloak --> postgres
    moodle -.-> redis

    classDef futur stroke-dasharray: 5 5;
    class waf,drupal,n8n,moodle,grafana,redis futur;
```

## 3. Parcours métier (cible)

```mermaid
sequenceDiagram
    actor U as Utilisateur
    participant D as Drupal Commerce
    participant N as n8n
    participant M as Moodle
    participant K as Keycloak

    U->>D: Consulte l'offre de formation
    U->>D: Paiement fictif (passerelle Manual)
    Note over D: Commande à l'état « completed »
    loop Toutes les minutes
        N->>D: GET JSON:API commandes « completed »
    end
    N->>M: core_user_get_users (l'utilisateur existe ?)
    N->>M: core_user_create_users (si absent)
    N->>M: enrol_manual_enrol_users (cours du produit)
    M-->>N: Inscription confirmée
    U->>M: Accède au cours
    M->>K: Redirection OIDC
    U->>K: Authentification
    K-->>M: Jeton (correspondance par courriel)
    M-->>U: Session ouverte, cours accessible
```

## 4. Flux réseau autorisés (état réel)

| Source | Destination | Port / protocole | Réseau | Justification |
| --- | --- | --- | --- | --- |
| Poste client | Traefik | 80 → 8000 (redirigé), 443 → 8443 HTTPS | exposition | Seul point d'entrée web |
| Poste client | sshd (hôte) | 2222 → 22 SSH | hôte | Administration, clé uniquement |
| Traefik | Portainer | 9000 HTTP | applicatif | Routage `portainer.cr465.test` |
| Traefik | Keycloak | 8080 HTTP | applicatif | Routage `auth.cr465.test` |
| Traefik | socket-proxy | 2375 HTTP | socket | Découverte des conteneurs (lecture) |
| socket-proxy | socket Docker | Unix | hôte | Lecture seule, `POST=0` |
| Portainer | socket Docker | Unix | hôte | Gestion des conteneurs (risque assumé) |
| Keycloak | PostgreSQL | 5432 | donnees | Base `keycloak` |

## 5. Flux volontairement interdits

| Flux interdit | Mécanisme qui l'empêche |
| --- | --- |
| Internet → PostgreSQL | Aucun port publié, réseau `donnees` interne |
| Internet → Portainer / Keycloak en direct | Aucun port publié, réseau `applicatif` interne |
| Traefik → PostgreSQL | Traefik n'est pas sur le réseau `donnees` |
| Traefik → socket Docker brut | Passage obligatoire par socket-proxy (lecture seule) |
| Conteneurs → Internet | Réseaux `applicatif`, `donnees`, `socket` en `internal: true` |
| Console Keycloak `/admin` depuis une IP non autorisée | Middleware `admin-allowlist` |

## 6. Routeurs et middlewares Traefik

| Nom d'hôte | Service | Middlewares |
| --- | --- | --- |
| `traefik.cr465.test` | `api@internal` | `admin-allowlist`, `dashboard-auth`, `secure-headers` |
| `portainer.cr465.test` | Portainer :9000 | `admin-allowlist`, `secure-headers` |
| `auth.cr465.test` | Keycloak :8080 | `hsts` |
| `auth.cr465.test` + `/admin`, `/realms/master` | Keycloak :8080 | `admin-allowlist`, `hsts` |

Keycloak utilise `hsts` plutôt que `secure-headers`, car `frameDeny` bloquerait les
iframes de sa console d'administration.

## 7. Vérifier que le schéma correspond au réel

```bash
cd /opt/platform/repo/compose
docker compose ps --format 'table {{.Service}}\t{{.Image}}\t{{.Ports}}'
docker network inspect cr465_applicatif cr465_donnees cr465_socket cr465_exposition \
  --format '{{.Name}} internal={{.Internal}}: {{range .Containers}}{{.Name}} {{end}}'
```

La première commande ne doit montrer des ports publiés que pour Traefik. La seconde
liste les membres de chaque réseau : ils doivent correspondre aux sous-graphes du schéma 1.

# SCHÉMA D'ARCHITECTURE CONSOLIDÉ — CR465 (fusion, aligné sur le réel)

> Fusion du schéma de l'équipe (flux, sous-domaines, WAF) et du socle réel
> (`cr465.test`, segmentation 4 réseaux, bases logiques PostgreSQL).
> **Trait plein = déployé/vérifié · Pointillé = à construire ou bonus.**
> Conforme à la grille : zones de confiance, flux justifiés, exposition minimale.

```mermaid
flowchart TB
    %% ================= ZONES DE CONFIANCE =================
    subgraph Z1["🌐 RÉSEAU D'EXPOSITION (seul réseau publié)"]
        INTERNET["Utilisateurs / Internet"]
        WAF["OpenAppSec WAF<br/>bonus · mode local<br/>(+2 pts, non engagé)"]
        TRAEFIK["Traefik v3.7.13<br/>point d'entrée unique · TLS ≥1.2<br/>dashboard protégé (allowlist IP + basic auth)"]
    end

    subgraph Z2["🔒 RÉSEAU APPLICATIF (internal:true · aucun accès Internet)"]
        DRUPAL["Drupal Commerce<br/>shop.cr465.test<br/>catalogue + paiement sandbox"]
        MOODLE["Moodle<br/>lms.cr465.test<br/>LMS · consommation"]
        KEYCLOAK["Keycloak 26.7.4<br/>auth.cr465.test<br/>IAM / SSO OIDC<br/>console /admin : IP restreintes"]
        N8N["n8n<br/>flow.cr465.test<br/>orchestration no-code"]
        PORTAINER["Portainer CE 2.39.5<br/>admin.cr465.test<br/>allowlist IP + mot de passe"]
    end

    subgraph Z3["🗄️ RÉSEAU DE DONNÉES (internal:true · JAMAIS exposé)"]
        PG["PostgreSQL 17.10-alpine<br/>1 instance · 4 bases logiques<br/>drupal | moodle | keycloak | n8n<br/>1 user dédié par service"]
    end

    subgraph Z4["⚙️ RÉSEAU SOCKET (internal:true)"]
        SOCK["docker-socket-proxy v0.5.0<br/>filtre l'API Docker<br/>lecture seule · POST=0"]
    end

    %% ================= FLUX D'ENTRÉE =================
    INTERNET -->|"HTTPS 443"| TRAEFIK
    WAF -.->|"bonus : filtrage applicatif"| TRAEFIK

    %% ================= TRAEFIK → SERVICES =================
    TRAEFIK -->|"web"| DRUPAL
    TRAEFIK -->|"web"| MOODLE
    TRAEFIK -->|"web"| KEYCLOAK
    TRAEFIK -->|"admin (allowlist IP)"| N8N
    TRAEFIK -->|"admin (allowlist IP)"| PORTAINER
    TRAEFIK -.->|"socket Docker RO"| SOCK

    %% ================= FLUX BASES DE DONNÉES =================
    DRUPAL -->|"base drupal"| PG
    MOODLE -->|"base moodle"| PG
    KEYCLOAK -->|"base keycloak"| PG
    N8N -->|"base n8n"| PG

    %% ================= FLUX MÉTIER (à construire) =================
    DRUPAL -.->|"① webhook « commande confirmée »<br/>après paiement simulé"| N8N
    N8N -.->|"② API REST Moodle<br/>attribution / inscription"| MOODLE
    KEYCLOAK -.->|"③ SSO OIDC (à brancher)"| MOODLE
    KEYCLOAK -.->|"bonification : SSO Drupal"| DRUPAL

    %% ================= STYLES =================
    classDef done fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px,color:#1b5e20
    classDef planned fill:#fff8e1,stroke:#f9a825,stroke-width:1.5px,stroke-dasharray:5 5,color:#7b5800
    classDef bonus fill:#ede7f6,stroke:#5e35b1,stroke-width:1.5px,stroke-dasharray:5 5,color:#4527a0
    class INTERNET,TRAEFIK,KEYCLOAK,PORTAINER,PG,SOCK done
    class DRUPAL,MOODLE,N8N planned
    class WAF bonus
```

---

## 2. Segmentation réseau — le critère /3 explicite

```mermaid
flowchart LR
    subgraph EXP["exposition (bridge · seul réseau avec ports publiés 80/443)"]
        TRAEFIK["Traefik"]
    end
    subgraph APP["applicatif (internal:true)"]
        DRUPAL["Drupal"]
        MOODLE["Moodle"]
        KC["Keycloak"]
        N8N["n8n"]
        PT["Portainer"]
    end
    subgraph DAT["donnees (internal:true)"]
        PG["PostgreSQL"]
    end
    subgraph SKT["socket (internal:true)"]
        SP["socket-proxy"]
    end

    NET["Internet"] -->|80/443| TRAEFIK
    TRAEFIK -->|routing| APP
    APP -->|accès SQL| PG
    TRAEFIK -.->|"lecture seule"| SP

    classDef zexp fill:#e3f2fd,stroke:#1565c0,color:#0d47a1
    classDef zapp fill:#e8f5e9,stroke:#2e7d32,color:#1b5e20
    classDef zdat fill:#fce4ec,stroke:#c62828,color:#b71c1c
    classDef zskt fill:#f3e5f5,stroke:#6a1b9a,color:#4a148c
    class TRAEFIK zexp
    class DRUPAL,MOODLE,KC,N8N,PT zapp
    class PG zdat
    class SP zskt
```

**Flux volontairement INTERDITS (à citer à la correction) :**
- Internet → PostgreSQL (aucun port publié)
- Traefik → PostgreSQL (le proxy ne voit jamais la base)
- Tout service → Internet (réseaux `internal:true`)
- Traefik → socket Docker brut (passage obligé par le filtre RO)

---

## 3. Flux métier attendu (critère Intégration /3)

```mermaid
sequenceDiagram
    autonumber
    participant U as Utilisateur
    participant D as Drupal Commerce
    participant N as n8n
    participant M as Moodle
    participant K as Keycloak
    U->>D: consulte l'offre de formation
    U->>D: paiement simulé / sandbox
    D->>N: webhook « commande confirmée »
    N->>M: API REST · attribution / inscription
    M-->>N: confirmation d'accès
    N-->>D: mise à jour du statut (optionnel)
    U->>M: consomme le contenu
    Note over U,K: Identité : U s'authentifie via Keycloak (SSO OIDC)
```

---

## Points gagnés par cette version consolidée

| Critère grille | Ce que ce schéma démontre |
|---|---|
| Architecture /5 | Zones de confiance explicites, sous-domaines réels, flux légendés |
| Segmentation /3 | 4 réseaux nommés comme dans le `docker-compose.yml` réel + flux interdits |
| IAM/SSO /3 | Keycloak central, OIDC Moodle, console admin restreinte |
| Intégration /3 | Séquence numérotée ① ② ③ du parcours métier |
| Reverse proxy /3 | Traefik point d'entrée unique, protections détaillées |
| Honnêteté | Pointillé = ce qui n'existe pas encore → schéma aligné sur le réel (non pénalisable) |

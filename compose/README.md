# Socle Docker Compose — phase 2

Ce socle déploie les services d'infrastructure sur lesquels viendront se brancher
Drupal Commerce, Moodle, Keycloak et n8n.

## Services

| Service | Image (version épinglée) | Rôle | Réseaux |
| --- | --- | --- | --- |
| socket-proxy | `tecnativa/docker-socket-proxy:v0.5.0` | Filtre l'API Docker : lecture seule pour Traefik | socket |
| traefik | `traefik:v3.7.13` | Seul point d'entrée HTTP/HTTPS | exposition, applicatif, socket |
| postgres | `postgres:17.10-alpine` | Base unique, une base par service | donnees |
| portainer | `portainer/portainer-ce:2.39.5` (LTS) | Exploitation graphique des conteneurs | applicatif |
| keycloak | `quay.io/keycloak/keycloak:26.7.4` | Fournisseur d'identité et SSO (OIDC) | applicatif, donnees |

## Segmentation réseau

| Réseau | Type | Qui y est | Pourquoi |
| --- | --- | --- | --- |
| `exposition` | bridge | Traefik | Seul réseau qui publie des ports (80, 443) |
| `applicatif` | interne | Traefik, services web | Traefik joint les services ; aucun accès Internet |
| `donnees` | interne | PostgreSQL, services qui ont besoin d'une base | La base n'est jamais joignable par Traefik ni par l'extérieur |
| `socket` | interne | Traefik, socket-proxy | Isole l'accès à l'API Docker |

Flux volontairement interdits : Internet → PostgreSQL, Internet → Portainer sans passer
par Traefik, Traefik → PostgreSQL, Traefik → socket Docker brut.

## Mesures de sécurité visibles dans le code

- Versions d'images explicites (jamais `latest`).
- `no-new-privileges` et `cap_drop: ALL` sur tous les conteneurs ; PostgreSQL ne récupère
  que les 5 capacités nécessaires à la bascule root → postgres.
- Traefik en utilisateur non-root (`1000:1000`) et système de fichiers en lecture seule.
- Limites CPU et mémoire sur chaque service ; healthchecks sur Traefik et PostgreSQL.
- Un seul conteneur publie des ports ; Docker contournant UFW, c'est la vraie protection.
- Redirection HTTP → HTTPS, TLS 1.2 minimum, en-têtes de sécurité (HSTS, nosniff, frameDeny).
- Tableau de bord Traefik et Portainer : liste d'IP autorisées + authentification.
- Secrets générés sur la VM (`scripts/gen-secrets.sh`), jamais commités.
- Une base et un utilisateur PostgreSQL par service, `CONNECT` retiré à `PUBLIC`.

## Keycloak

- Realm `cr465` importé au démarrage depuis `keycloak/import/realm-cr465.json` (Identity as Code) :
  inscription libre désactivée, protection anti-bruteforce (5 échecs), mots de passe de 12 caractères
  minimum, rôles `etudiant` et `enseignant`.
- Console d'administration (`/admin`) et realm `master` accessibles uniquement depuis les IP
  d'administration ; les pages de connexion du realm `cr465` restent publiques.
- Utilisateur non-root, TLS terminé par Traefik, endpoint de santé sur le port 9000 jamais routé.
- Traefik porte les alias réseau `auth.cr465.test`, `moodle.cr465.test`, etc. : les conteneurs
  joignent les URL publiques sans quitter le réseau interne (nécessaire pour le SSO Moodle).

## Risques résiduels assumés

- **Portainer monte le socket Docker complet** : il en a besoin pour gérer les conteneurs.
  Compensation : accès uniquement via Traefik, IP autorisées, mot de passe fort.
- **Certificat auto-signé par une CA locale** : il faut importer `ca.crt` sur le poste
  client pour éviter l'avertissement du navigateur.
- **Keycloak sans système de fichiers en lecture seule** : il recompile sa configuration
  au démarrage dans son propre dossier. Une image pré-construite (`kc.sh build`) le permettrait.
- **Pas de healthcheck sur Portainer et socket-proxy** : leurs images ne contiennent pas
  d'outil de test (pas de shell ni de curl), ce qui réduit aussi leur surface d'attaque.

## Déploiement (sur la VM)

```bash
cd /opt/platform/repo
bash scripts/gen-certs.sh
bash scripts/gen-secrets.sh
cd compose
docker compose config --quiet && docker compose up -d
docker compose ps
```

## Vérifications

```bash
docker compose ps                         # tous "running", traefik et postgres "healthy"
sudo ss -tlnp | grep -E ':80 |:443 '      # seuls 80 et 443 publiés
docker compose exec postgres psql -U pgadmin -d postgres -c '\l'   # 4 bases créées
docker network ls | grep cr465            # 4 réseaux
```

Depuis Windows (après avoir ajouté les noms au fichier hosts) :
`https://traefik.cr465.test` et `https://portainer.cr465.test`.

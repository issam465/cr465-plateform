#!/usr/bin/env bash
# Génère, sur la VM uniquement, les secrets de la plateforme :
#   - compose/.env à partir de .env.example (chaque "changeme" -> mot de passe aléatoire)
#   - compose/secrets/ : mot de passe Portainer, htpasswd du tableau de bord Traefik
# Rien de tout cela n'est commité (voir .gitignore).
# Utilisation (depuis la racine du dépôt) :  bash scripts/gen-secrets.sh
set -euo pipefail

COMPOSE="$(cd "$(dirname "$0")/.." && pwd)/compose"
rand() { openssl rand -hex 20; }

# 1. Fichier .env
if [ -f "$COMPOSE/.env" ]; then
  echo ".env existe deja : conserve (supprimez-le pour le regenerer)"
else
  while IFS= read -r line; do
    if [[ "$line" == *=changeme ]]; then
      echo "${line%=changeme}=$(rand)"
    else
      echo "$line"
    fi
  done < "$COMPOSE/.env.example" > "$COMPOSE/.env"
  chmod 600 "$COMPOSE/.env"
  echo ".env cree avec des mots de passe aleatoires"
fi

# 2. Secrets des interfaces d'administration
mkdir -p "$COMPOSE/secrets"
chmod 700 "$COMPOSE/secrets"
cd "$COMPOSE/secrets"

if [ ! -f portainer_admin_password ]; then
  PORTAINER_PW="$(rand)"
  DASHBOARD_PW="$(rand)"
  printf '%s' "$PORTAINER_PW" > portainer_admin_password
  printf 'admin:%s\n' "$(openssl passwd -apr1 "$DASHBOARD_PW")" > traefik_dashboard.htpasswd
  {
    echo "Portainer          -> utilisateur: admin  mot de passe: $PORTAINER_PW"
    echo "Tableau Traefik    -> utilisateur: admin  mot de passe: $DASHBOARD_PW"
  } > ADMIN_PASSWORDS.txt
  # Le dossier secrets/ est en 700 : seuls cr465admin et Docker y accèdent sur l'hôte.
  # Les fichiers montés sont en 644 pour que les conteneurs (sans capacité DAC_OVERRIDE)
  # puissent les lire ; le récapitulatif reste en 600.
  chmod 644 portainer_admin_password traefik_dashboard.htpasswd
  chmod 600 ADMIN_PASSWORDS.txt
  echo "Secrets crees. Identifiants d'administration :"
  cat ADMIN_PASSWORDS.txt
else
  echo "Secrets deja presents : conserves (voir $COMPOSE/secrets/ADMIN_PASSWORDS.txt)"
fi

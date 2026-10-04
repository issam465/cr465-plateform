#!/bin/bash
# Exécuté UNE SEULE FOIS, à la création du volume postgres_data.
# Crée une base et un utilisateur dédiés par service (principe du moindre privilège) :
# chaque service ne peut se connecter qu'à SA base.

create_db() {
  local db="$1" user="$2" pass="$3"
  echo "CR465 : creation de la base ${db} (proprietaire ${user})"
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres \
       -v db="$db" -v usr="$user" -v pass="$pass" <<'EOSQL'
CREATE ROLE :"usr" LOGIN PASSWORD :'pass';
CREATE DATABASE :"db" OWNER :"usr" ENCODING 'UTF8';
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
EOSQL
}

create_db drupal   drupal   "$DRUPAL_DB_PASSWORD"
create_db moodle   moodle   "$MOODLE_DB_PASSWORD"
create_db keycloak keycloak "$KEYCLOAK_DB_PASSWORD"
create_db n8n      n8n      "$N8N_DB_PASSWORD"

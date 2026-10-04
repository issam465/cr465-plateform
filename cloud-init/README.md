# VM as Code — cloud-init

Ce dossier contient `user-data.yaml`, qui transforme une VM Ubuntu Server 24.04 vierge
en hôte durci prêt à exécuter la stack Docker Compose, sans aucune étape manuelle.

## Ce que cloud-init configure automatiquement

| Domaine | Configuration |
| --- | --- |
| Utilisateur | `cr465admin`, connexion par clé SSH uniquement, mot de passe verrouillé |
| SSH | Root interdit, mots de passe désactivés, 3 essais max, seul `cr465admin` autorisé |
| Mises à jour | Mise à jour complète au premier démarrage + mises à jour de sécurité automatiques |
| Docker | Docker Engine + Compose depuis le dépôt officiel (clé vérifiée par empreinte) |
| Démon Docker | Rotation des logs (3 × 10 Mo), `no-new-privileges` par défaut, `icc` désactivé |
| Pare-feu | UFW : tout refusé en entrée sauf 22 (limité), 80 et 443 |
| Anti-bruteforce | fail2ban sur SSH (5 essais en 10 min → banni 1 h) |
| Noyau | Durcissement réseau (anti-spoofing, pas de redirections ICMP, SYN cookies) |
| Journalisation | journald persistant, plafonné à 500 Mo |
| Scan d'images | Trivy installé localement (aucun service cloud) |
| Répertoires | `/opt/platform/{repo,secrets,backups,scans}` avec permissions restreintes |

## Avant de l'utiliser : mettre votre clé SSH publique

Sous Windows (cmd ou PowerShell) :

```
ssh-keygen -t ed25519 -C "cr465admin"
type %USERPROFILE%\.ssh\id_ed25519.pub
```

Copiez la ligne affichée (elle commence par `ssh-ed25519`) et remplacez la ligne
`ssh-ed25519 AAAA_REMPLACER...` dans `user-data.yaml`.

La clé **publique** (`.pub`) peut être commitée. La clé **privée** (`id_ed25519`, sans extension)
ne doit jamais quitter votre ordinateur.

## Tester avec Multipass (Windows, Mac, Linux)

```
multipass launch 24.04 --name cr465 --cpus 4 --memory 8G --disk 60G --cloud-init cloud-init/user-data.yaml
multipass info cr465
ssh cr465admin@<IP_AFFICHEE>
```

`multipass shell` ne fonctionnera pas : c'est voulu, car seul `cr465admin` est autorisé en SSH.

## Vérifier que tout s'est bien passé (dans la VM)

```
cloud-init status --long          # doit afficher "status: done"
cat /var/log/cr465-init.log       # versions de Docker, Compose et Trivy
docker run --rm hello-world       # Docker fonctionne sans sudo
sudo ufw status verbose           # seuls 22, 80, 443 sont ouverts
sudo sshd -T | grep -E "permitrootlogin|passwordauthentication"
sudo fail2ban-client status sshd
```

Le test de reproductibilité : détruire la VM (`multipass delete --purge cr465`), la recréer
avec la même commande, et obtenir exactement le même résultat.

## Limites et choix assumés

- **Docker contourne UFW** pour les ports publiés (il écrit ses propres règles iptables).
  La parade est dans le Compose : seul Traefik publie des ports (80/443) ; aucun autre
  service n'a de section `ports:`.
- **sudo sans mot de passe** : le compte n'a pas de mot de passe du tout (connexion par clé
  uniquement). C'est un compromis courant pour l'automatisation ; en production, on
  ajouterait un mot de passe sudo ou une élévation via un bastion.
- **Architecture amd64** uniquement (dépôt Docker). Sur un Mac Apple Silicon, remplacer
  `arch=amd64` par `arch=arm64`.
- **Redémarrage** : si la mise à jour initiale installe un nouveau noyau, un redémarrage
  manuel (`sudo reboot`) est conseillé.
- **Restent manuels** : la création de la VM elle-même, la clé SSH, le fichier `.env`
  avec les vrais secrets, et le lancement de la stack (`docker compose up -d`).

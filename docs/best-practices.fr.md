# Bonnes pratiques du lab

Les règles que ce dépôt suit — et pourquoi. À relire avant toute opération.

## Une seule source de vérité

- L'infrastructure est décrite dans `terraform/vms.auto.tfvars.json` (géré par
  `scripts/newvm.sh`) et dans les rôles Ansible. **Jamais de `qm` à la main,
  jamais de clic dans l'interface** pour créer/modifier une VM du lab : toute
  modification manuelle sera écrasée ou créera de la dérive.
- Tout changement passe par un commit git. Petits commits, messages clairs
  (`feat:`, `fix:`, ...), CI verte avant de considérer le travail fini.

## Terraform

- **Toujours lire le plan** avant de taper `yes`. Le résumé
  (`X to add, Y to change, Z to destroy`) doit correspondre à l'intention —
  un `destroy` inattendu est un signal d'arrêt immédiat.
- Reconstruire une VM depuis le template = `terraform apply -replace='...vm["nom"]'`.
  Changer le template dans la config ne remplace PAS les VMs existantes.
- **Jamais de `-replace`/`remove` sur une VM qui porte des données**
  (drive-01 : son disque de 700 Go meurt avec elle) sans sauvegarde préalable.
- Les secrets (`terraform.tfvars` : token API) sont git-ignorés et ne quittent
  jamais mgmt-01.

## Ansible

- Les playbooks sont **idempotents** : les relancer est toujours sûr.
- **Cibler ce qui change** : ajouter une VM =
  `ansible-playbook site.yml --limit "nouvelle-vm,monitoring,proxy"`
  (la VM + la config Prometheus retemplatée + les routes Traefik).
  Le script `newvm.sh` le fait automatiquement.
- **Run complet périodique** : un `ansible-playbook site.yml` sans limit de
  temps en temps corrige la dérive de configuration sur tout le parc.
- Secrets dans `group_vars/all.yml` (mots de passe du drive) : à migrer vers
  **Ansible Vault** (`ansible-vault encrypt_string`) — en l'état, ne jamais
  y mettre un mot de passe réellement sensible.

## Stockage & matériel (leçons apprises)

- Contrôleur RAID P420i : cache d'écriture indispensable (SSD Smart Path
  désactivé sur l'array SSD). Sur ce matériel, préférer les **linked clones**
  et les grosses écritures **une par une** (`terraform apply -parallelism=1`
  si full clones).
- Une tâche Proxmox à 100 % n'est pas finie : attendre le retour du prompt.
  Ne jamais interrompre une écriture en cours (Ctrl+C = état incohérent).

## Exposer un service sur internet

- **Jamais d'ouverture de port directe** sans y avoir réfléchi : préférer un
  tunnel sortant (Cloudflare Tunnel) qui cache l'IP et n'ouvre rien sur la box.
- Toute VM exposée passe en **DMZ** (`dmz: true` dans la définition de la VM,
  proposé par `newvm.sh`) : pare-feu Proxmox sur son interface — entrées
  limitées (web, SSH depuis mgmt-01, métriques vers monitoring), **sorties
  vers le LAN interdites**. Une VM compromise ne peut pas pivoter vers les
  autres machines. Ce pare-feu vit HORS de la VM : il tient même si la VM
  est compromise (contrairement à son UFW interne, qui reste une 2e couche).
- Dans l'application exposée : mots de passe forts, 2FA, mises à jour suivies.

## Sauvegardes (à mettre en place — roadmap)

- Avant toute opération destructive sur drive-01 : snapshot Proxmox a minima,
  Proxmox Backup Server à terme. Une donnée qui n'existe qu'à un endroit
  n'existe pas.

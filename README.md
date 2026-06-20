# Ansible LAMP (Apache + PHP) + MariaDB roles

This repo contains three reusable Ansible roles:
- roles/apache — install + secure Apache
- roles/php — install parameterized PHP from Ondřej Surý PPA (php_version variable)
- roles/mariadb — install MariaDB 12.3 with datadir relocated to /srv/mysql (configurable) and AppArmor adjustments

Features
- Parameterized php_version
- Optional installation of each component (install_apache, install_php, install_mariadb)
- Prompts for mariadb_root_password at runtime (vars_prompt)
- Support for custom config files (set *_custom_* variables)
- Security hardening steps included
- Example inventory and site playbook included

Quick start
1. Install required collection:
   ansible-galaxy collection install -r requirements.yml

2. Edit inventories/hosts.ini to point to your hosts.

3. Run:
   ansible-playbook -i inventories/hosts.ini site.yml

The playbook will prompt for mariadb_root_password.

License: MIT

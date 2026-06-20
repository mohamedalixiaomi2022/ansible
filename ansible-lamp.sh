#!/usr/bin/env bash
set -euo pipefail
ROOT="ansible-lamp-mariadb"
rm -rf "${ROOT}"
mkdir -p "${ROOT}"

# helper to write files with dirs
writefile() {
  local path="$1"; shift
  mkdir -p "$(dirname "${ROOT}/${path}")"
  cat > "${ROOT}/${path}" <<'EOF'
'"$@"'
EOF
}

# Create files
mkdir -p "${ROOT}"

cat > "${ROOT}/README.md" <<'EOF'
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
EOF

cat > "${ROOT}/LICENSE" <<'EOF'
MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction...
EOF

cat > "${ROOT}/requirements.yml" <<'EOF'
collections:
  - name: community.mysql
    version: ">=5.0.0"
EOF

cat > "${ROOT}/.gitignore" <<'EOF'
# OS / editor
.vagrant/
*.retry
*.pyc
__pycache__/

# Ansible
*.retry
.vault-password

# Archives
*.tar.gz
*.b64
EOF

mkdir -p "${ROOT}/inventories"
cat > "${ROOT}/inventories/hosts.ini" <<'EOF'
[webservers]
your-web-host ansible_host=192.0.2.10 ansible_user=ubuntu

[dbservers]
your-db-host ansible_host=192.0.2.11 ansible_user=ubuntu

[all:vars]
ansible_python_interpreter=/usr/bin/python3
EOF

cat > "${ROOT}/site.yml" <<'EOF'
---
- name: Provision LAMP + MariaDB (optional components)
  hosts: all
  become: true

  vars:
    # Control which components to install
    install_apache: true
    install_php: true
    install_mariadb: true

    # Default php version (can override per-inventory)
    php_version: "8.2"
    php_handler: "fpm"   # "fpm" or "mod_php"

    # Default mariadb install options
    mariadb_version: "12.3"
    mariadb_data_dir: "/srv/mysql"
    mariadb_bind_address: "127.0.0.1"
    mariadb_secure_hardening: true
    mariadb_databases: []
    mariadb_users: []

  vars_prompt:
    - name: "mariadb_root_password"
      prompt: "MariaDB root password (leave blank if not installing or using socket auth)"
      private: yes
      default: ""

  roles:
    - role: apache
      when: install_apache
      vars:
        apache_install: "{{ install_apache }}"

    - role: php
      when: install_php
      vars:
        php_install: "{{ install_php }}"
        php_version: "{{ php_version }}"
        php_handler: "{{ php_handler }}"

    - role: mariadb
      when: install_mariadb
      vars:
        mariadb_install: "{{ mariadb_install | default(install_mariadb) }}"
        mariadb_version: "{{ mariadb_version }}"
        mariadb_data_dir: "{{ mariadb_data_dir }}"
        mariadb_root_password: "{{ mariadb_root_password }}"
        mariadb_bind_address: "{{ mariadb_bind_address }}"
        mariadb_secure_hardening: "{{ mariadb_secure_hardening }}"
EOF

# roles/apache
mkdir -p "${ROOT}/roles/apache/{tasks,handlers,defaults,templates,meta,files}"
cat > "${ROOT}/roles/apache/meta/main.yml" <<'EOF'
---
galaxy_info:
  author: "generated"
  description: "Install and secure Apache"
  license: MIT
  min_ansible_version: 2.14
EOF

cat > "${ROOT}/roles/apache/defaults/main.yml" <<'EOF'
---
apache_install: true
apache_pkg: apache2
apache_service_name: apache2
apache_php_handler: "{{ php_handler | default('fpm') }}"
apache_custom_security_conf: ""
EOF

cat > "${ROOT}/roles/apache/handlers/main.yml" <<'EOF'
---
- name: restart apache
  service:
    name: "{{ apache_service_name }}"
    state: restarted
EOF

cat > "${ROOT}/roles/apache/tasks/main.yml" <<'EOF'
---
- name: "Skip apache role when not requested"
  meta: end_play
  when: not apache_install

- name: Install apache package
  apt:
    name: "{{ apache_pkg }}"
    state: present
    update_cache: yes

- name: Ensure required apache modules are enabled
  apt:
    name: "{{ item }}"
    state: present
  loop:
    - apache2-utils
    - ssl
  notify: restart apache

- name: Deploy apache security configuration (use custom if provided)
  block:
    - name: Use custom apache security conf if set
      copy:
        src: "{{ apache_custom_security_conf }}"
        dest: /etc/apache2/conf-available/custom-security.conf
        owner: root
        group: root
        mode: "0644"
      when: apache_custom_security_conf | length > 0

    - name: Deploy standard apache security conf template
      template:
        src: apache-security.conf.j2
        dest: /etc/apache2/conf-available/custom-security.conf
        owner: root
        group: root
        mode: "0644"
      when: apache_custom_security_conf | length == 0
  notify: restart apache

- name: Enable custom security conf
  command: a2enconf custom-security
  args:
    warn: false
  notify: restart apache

- name: Ensure default site is enabled
  command: a2ensite 000-default.conf
  args:
    warn: false
  notify: restart apache

- name: Ensure apache service is running and enabled
  service:
    name: "{{ apache_service_name }}"
    state: started
    enabled: yes
EOF

cat > "${ROOT}/roles/apache/templates/apache-security.conf.j2" <<'EOF'
# Basic Apache security tweaks
ServerSignature Off
ServerTokens Prod

<IfModule mod_headers.c>
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "no-referrer-when-downgrade"
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
</IfModule>

Timeout 60
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5
EOF

# roles/php
mkdir -p "${ROOT}/roles/php/{tasks,handlers,defaults,templates,meta,files}"
cat > "${ROOT}/roles/php/meta/main.yml" <<'EOF'
---
galaxy_info:
  author: "generated"
  description: "Install PHP from Ondřej Surý PPA and secure configuration"
  license: MIT
  min_ansible_version: 2.14
  dependencies: []
EOF

cat > "${ROOT}/roles/php/defaults/main.yml" <<'EOF'
---
php_install: true
php_version: "8.2"
php_handler: "fpm"
php_packages:
  - "php{{ php_version }}"
  - "php{{ php_version }}-cli"
  - "php{{ php_version }}-gd"
  - "php{{ php_version }}-mbstring"
  - "php{{ php_version }}-xml"
  - "php{{ php_version }}-curl"
  - "php{{ php_version }}-zip"
  - "php{{ php_version }}-mysql"
php_modphp_pkg: "libapache2-mod-php{{ php_version }}"
php_custom_ini: ""
php_custom_fpm_conf: ""
php_ini_overrides: {}
EOF

cat > "${ROOT}/roles/php/handlers/main.yml" <<'EOF'
---
- name: restart php-fpm
  service:
    name: "php{{ php_version }}-fpm"
    state: restarted
  when: php_handler == 'fpm'

- name: restart apache (for mod_php)
  service:
    name: apache2
    state: restarted
  when: php_handler != 'fpm'
EOF

cat > "${ROOT}/roles/php/tasks/main.yml" <<'EOF'
---
- name: "Skip php role when not requested"
  meta: end_play
  when: not php_install

- name: Ensure software-properties-common is present (for add-apt-repository)
  apt:
    name: software-properties-common
    state: present
    update_cache: yes

- name: Add Ondrej Sury PHP PPA
  apt_repository:
    repo: ppa:ondrej/php
    state: present
  notify: apt_update_for_php

- name: apt update for PHP
  apt:
    update_cache: yes
  when: false
  listen: apt_update_for_php

- name: Install PHP packages
  apt:
    name: "{{ (php_packages if php_handler == 'fpm' else (php_packages + [php_modphp_pkg])) | unique }}"
    state: present
    update_cache: yes
  notify: restart php-fpm

- name: If using php-fpm, ensure service is enabled and running
  service:
    name: "php{{ php_version }}-fpm"
    state: started
    enabled: yes
  when: php_handler == 'fpm'

- name: Deploy php.ini (use custom if provided)
  block:
    - name: Copy custom php.ini if present
      copy:
        src: "{{ php_custom_ini }}"
        dest: "/etc/php/{{ php_version }}/{{ 'fpm' if php_handler == 'fpm' else 'apache2' }}/php.ini"
        owner: root
        group: root
        mode: "0644"
      when: php_custom_ini | length > 0

    - name: Render php.ini template
      template:
        src: php.ini.j2
        dest: "/etc/php/{{ php_version }}/{{ 'fpm' if php_handler == 'fpm' else 'apache2' }}/php.ini"
        owner: root
        group: root
        mode: "0644"
      when: php_custom_ini | length == 0
  notify: restart php-fpm

- name: Deploy php-fpm www.conf (only for fpm handler; allow custom)
  when: php_handler == 'fpm'
  block:
    - name: Use custom php-fpm conf if set
      copy:
        src: "{{ php_custom_fpm_conf }}"
        dest: "/etc/php/{{ php_version }}/fpm/pool.d/www.conf"
        owner: root
        group: root
        mode: "0644"
      when: php_custom_fpm_conf | length > 0

    - name: Render php-fpm pool config template
      template:
        src: php-fpm.conf.j2
        dest: "/etc/php/{{ php_version }}/fpm/pool.d/www.conf"
        owner: root
        group: root
        mode: "0644"
      when: php_custom_fpm_conf | length == 0
  notify: restart php-fpm
EOF

cat > "${ROOT}/roles/php/templates/php.ini.j2" <<'EOF'
[PHP]
engine = On
short_open_tag = Off
expose_php = Off
display_errors = Off
display_startup_errors = Off
log_errors = On
error_log = /var/log/php_errors.log
max_execution_time = 60
memory_limit = 128M
post_max_size = 32M
upload_max_filesize = 16M

; Sessions
session.use_strict_mode = 1
session.use_cookies = 1
session.cookie_httponly = 1
session.cookie_secure = 1

; Disable dangerous functions
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source

; Additional overrides passed by variable
{% raw %}{% for k, v in php_ini_overrides.items() %}
{{ k }} = {{ v }}
{% endfor %}{% endraw %}
EOF

cat > "${ROOT}/roles/php/templates/php-fpm.conf.j2" <<'EOF'
[www]
user = www-data
group = www-data
listen = /run/php/php{{ php_version }}-fpm.sock
listen.owner = www-data
listen.group = www-data
listen.mode = 0660

pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3

clear_env = no
catch_workers_output = yes
EOF

# roles/mariadb
mkdir -p "${ROOT}/roles/mariadb/{tasks,handlers,defaults,templates,meta,files}"
cat > "${ROOT}/roles/mariadb/meta/main.yml" <<'EOF'
---
galaxy_info:
  author: "generated"
  description: "Install MariaDB and move datadir to /srv/mysql with AppArmor adjustments"
  license: MIT
  min_ansible_version: 2.14
EOF

cat > "${ROOT}/roles/mariadb/defaults/main.yml" <<'EOF'
---
mariadb_install: true
mariadb_version: "12.3"
mariadb_data_dir: "/srv/mysql"
mariadb_apt_codename: "{{ ansible_distribution_release }}"
mariadb_root_password: ""
mariadb_bind_address: "127.0.0.1"
mariadb_custom_cnf: ""
mariadb_secure_hardening: true
mariadb_databases: []
mariadb_users: []
EOF

cat > "${ROOT}/roles/mariadb/handlers/main.yml" <<'EOF'
---
- name: restart mariadb
  service:
    name: mariadb
    state: restarted

- name: reload apparmor
  command: systemctl reload apparmor
  ignore_errors: yes
EOF

cat > "${ROOT}/roles/mariadb/tasks/main.yml" <<'EOF'
---
- name: "Skip mariadb role when not requested"
  meta: end_play
  when: not mariadb_install

- name: Ensure apt-transport-https is present
  apt:
    name: apt-transport-https
    state: present
    update_cache: yes

- name: Add MariaDB APT key
  apt_key:
    url: "https://mariadb.org/mariadb_release_signing_key.asc"
    state: present

- name: Add MariaDB repository
  apt_repository:
    repo: "deb [arch=amd64] http://downloads.mariadb.com/mariadb/{{ mariadb_version }}/repo/ubuntu {{ mariadb_apt_codename }} main"
    state: present
  notify: apt_update_mariadb

- name: apt update for mariadb
  apt:
    update_cache: yes
  when: false
  listen: apt_update_mariadb

- name: Install mariadb-server
  apt:
    name: "mariadb-server-{{ mariadb_version.split('.')[0] }}"
    state: present
    update_cache: yes
  notify: restart mariadb

- name: Stop mariadb before relocating datadir
  service:
    name: mariadb
    state: stopped
  ignore_errors: yes

- name: Ensure mariadb data directory exists
  file:
    path: "{{ mariadb_data_dir }}"
    state: directory
    owner: mysql
    group: mysql
    mode: "0755"

- name: Determine if old datadir exists
  stat:
    path: /var/lib/mysql
  register: old_datadir_stat

- name: Determine if new datadir has content
  find:
    paths: "{{ mariadb_data_dir }}"
    file_type: any
    recurse: yes
  register: new_datadir_find

- name: Rsync existing data to new datadir (if old exists and new is empty)
  command: >
    rsync -aHAX --numeric-ids --delete /var/lib/mysql/ {{ mariadb_data_dir }}/
  when:
    - old_datadir_stat.stat.exists
    - new_datadir_find.matched == 0
  args:
    warn: false
  register: rsync_result
  changed_when: rsync_result.rc == 0 and rsync_result.stdout is defined

- name: Create marker file after move
  file:
    path: "{{ mariadb_data_dir }}/.moved_by_ansible"
    state: touch
    owner: mysql
    group: mysql
  when:
    - old_datadir_stat.stat.exists
    - new_datadir_find.matched == 0

- name: Ensure correct ownership on mariadb data dir
  file:
    path: "{{ mariadb_data_dir }}"
    state: directory
    recurse: yes
    owner: mysql
    group: mysql
    mode: "0755"

- name: Deploy my.cnf (custom override if set)
  block:
    - name: Copy custom my.cnf if provided
      copy:
        src: "{{ mariadb_custom_cnf }}"
        dest: /etc/mysql/my.cnf
        owner: root
        group: root
        mode: "0644"
      when: mariadb_custom_cnf | length > 0

    - name: Render my.cnf template
      template:
        src: my.cnf.j2
        dest: /etc/mysql/my.cnf
        owner: root
        group: root
        mode: "0644"
      when: mariadb_custom_cnf | length == 0
  notify: restart mariadb

- name: Ensure AppArmor local profile directory exists
  file:
    path: /etc/apparmor.d/local
    state: directory
    owner: root
    group: root
    mode: "0755"

- name: Add AppArmor lines to allow new mariadb datadir
  blockinfile:
    path: /etc/apparmor.d/local/usr.sbin.mysqld
    create: yes
    block: |
      # Allow MariaDB data dir managed by Ansible
      {{ mariadb_data_dir }}/ r,
      {{ mariadb_data_dir }}/** rwk,
  notify: reload apparmor
  when: ansible_facts['os_family'] == "Debian"

- name: Start mariadb
  service:
    name: mariadb
    state: started
    enabled: yes

- name: Wait for mariadb socket
  wait_for:
    path: /var/run/mysqld/mysqld.sock
    timeout: 30

- name: Generate SQL to run for secure hardening
  set_fact:
    mariadb_secure_sql: |
      DELETE FROM mysql.user WHERE User='';
      DROP DATABASE IF EXISTS test;
      DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
      FLUSH PRIVILEGES;
      {{ "ALTER USER 'root'@'localhost' IDENTIFIED BY '" + mariadb_root_password + "';" if mariadb_root_password | length > 0 else "" }}

- name: Execute secure SQL
  community.mysql.mysql_query:
    login_unix_socket: /var/run/mysqld/mysqld.sock
    query: "{{ mariadb_secure_sql }}"
  when: mariadb_secure_hardening
  become: true

- name: Create configured MariaDB databases
  community.mysql.mysql_db:
    name: "{{ item.name }}"
    state: present
    login_user: root
    login_password: "{{ mariadb_root_password | default(omit) }}"
  loop: "{{ mariadb_databases }}"
  when: mariadb_databases | length > 0

- name: Create configured MariaDB users
  community.mysql.mysql_user:
    name: "{{ item.name }}"
    password: "{{ item.password }}"
    priv: "{{ item.priv | default('*.*:ALL') }}"
    host: "{{ item.host | default('localhost') }}"
    state: present
    login_user: root
    login_password: "{{ mariadb_root_password | default(omit) }}"
  loop: "{{ mariadb_users }}"
  when: mariadb_users | length > 0
EOF

cat > "${ROOT}/roles/mariadb/templates/my.cnf.j2" <<'EOF'
[client]
port = 3306
socket = /var/run/mysqld/mysqld.sock

[mysqld]
user = mysql
pid-file = /var/run/mysqld/mysqld.pid
socket = /var/run/mysqld/mysqld.sock
port = 3306

datadir = {{ mariadb_data_dir | default('/var/lib/mysql') }}
basedir = /usr
tmpdir = /tmp
skip-external-locking

bind-address = {{ mariadb_bind_address }}

innodb_buffer_pool_size = 128M
innodb_file_per_table = 1
query_cache_type = 0
max_connections = 100

skip-symbolic-links = 1
EOF

# Create empty files dirs for custom files
mkdir -p "${ROOT}/roles/apache/files"
mkdir -p "${ROOT}/roles/php/files"
mkdir -p "${ROOT}/roles/mariadb/files"

# Make the archive
tar -C "$(dirname "${ROOT}")" -czf "${ROOT}.tar.gz" "$(basename "${ROOT}")"

# Also create base64 if desired
base64 "${ROOT}.tar.gz" > "${ROOT}.tar.gz.b64"

echo "Created ${ROOT}.tar.gz and ${ROOT}.tar.gz.b64 in $(pwd)"
echo "To extract: tar xzf ${ROOT}.tar.gz"
#!/usr/bin/env bash
#
# This is a rudimentary deployment script for nginx stable / mysql 8 / php73 / wordpress latest
# 
# Usage: ./main.sh <domain> <wp admin email> <wp admin user> <wp admin password>
#

# Declare Globals
FQDN="$1"
WP_ADMIN_EMAIL="$2"
WP_ADMIN_USER="$3"
WP_ADMIN_PASSWD="$4"
MYSQL_PASSWD="`tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1`"
WP_MYSQL_PASSWD="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)"
WP_MYSQL_USER="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)"
WP_MYSQL_DATABASE="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)"
EFS_ADDR=""

# It's alive!
main() {
  initial_update && \
  install_nginx && \
  install_php73 && \
  install_certbot && \
  setup_nginx_config && \
  setup_site_config && \
  install_mysql8 && \
  setup_database && \
  install_wpcli && \
  install_wordpress && \
  save_credentials && \
  setup_swap
}

#######################################
# Initial system update
# Globals:
#   None
# Arguements:
#   None
# Returns:
#   None
#######################################
initial_update() {
  apt-get -y update && apt-get -y upgrade && apt-get -y autoremove && \

  return 0 || \
  err "Unable to run initial update"
}

#######################################
# Install NginX
# Globals:
#   None
# Arguements:
#   None
# Returns:
#   None
#######################################
install_nginx() {
  add-apt-repository -y ppa:ondrej/nginx && \
  apt-get -y update && \
  apt-get -y install nginx-full && \

  return 0 || \
  err "Unable to install NginX"
}

#######################################
# Install PHP 7.3
# Globals:
#   None
# Arguements:
#   None
# Returns:
#   None
#######################################
install_php73() {
  add-apt-repository -y ppa:ondrej/php && \
  apt-get -y update && \
  apt-get -y install php7.3-cli php7.3-common php7.3-fpm php7.3-mbstring php7.3-opcache php7.3-mysql php7.3-gd  && \

  return 0 || \
  err "Unable to install PHP 7.3"
}

#######################################
# Install Certbot
# Globals:
#   None
# Arguements:
#   None
# Returns:
#   None
#######################################
install_certbot() {
  add-apt-repository -y universe && \
  add-apt-repository -y ppa:certbot/certbot && \
  apt-get -y update && \
  apt-get -y install certbot python-certbot-nginx && \

  return 0 || \
  err "Unable to install Certbot"
}

#######################################
# Setup NginX global configuration
# Globals:
#   None
# Arguements:
#   None
# Returns:
#   None
#######################################
setup_nginx_config() {
  mv /etc/nginx /etc/nginx.bak && \
  git clone https://gitlab.com/optimull/wordpress-nginx.git /etc/nginx && \

  return 0 || \
  err "Could not setup NginX config"
}

#######################################
# Setup site directories and configuration
# Globals:
#   FQDN
# Arguements:
#   None
# Returns:
#   None
#######################################
setup_site_config() {
  # Create initial directories
  mkdir -p /sites/${FQDN}/{logs,public} && \
  chown -R www-data. /sites/${FQDN} && \

  # Copy example site to sites-enabled and replace the domain
  cp /etc/nginx/sites-available/fastcgi-cache.com /etc/nginx/sites-enabled/${FQDN} && \
  sed -i "s/fastcgi-cache.com/${FQDN}/g" /etc/nginx/sites-enabled/${FQDN} && \
  service nginx restart && \

  return 0 || \
  err "Could not setup site config"
}


#######################################
# Install MySQL 8.0
# Globals:
#   MYSQL_PASSWD
# Arguements:
#   None
# Returns:
#   None
#######################################
install_mysql8() {
  # NOTE: might use this to install the key since retreiving the key manually via apt-key is giving inconsistent results
  # wget "https://dev.mysql.com/get/mysql-apt-config_0.8.14-1_all.deb" && \
  # sudo debconf-set-selections <<< "echo mysql-apt-config mysql-apt-config/select-server select mysql-8.0" && \
  # dpkg -i mysql-apt-config_0.8.14-1_all.deb && \
  sudo apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com 5072E1F5 && \
  echo "deb http://repo.mysql.com/apt/ubuntu/ bionic mysql-8.0" | sudo tee /etc/apt/sources.list.d/mysql.list && \
  apt-get update && \
  sudo debconf-set-selections <<< "mysql-community-server mysql-community-server/root-pass password ${MYSQL_PASSWD}" && \
  sudo debconf-set-selections <<< "mysql-community-server mysql-community-server/re-root-pass password ${MYSQL_PASSWD}" && \
  sudo DEBIAN_FRONTEND=noninteractive apt-get -y install mysql-server && \
  echo -e "[client]\nuser=root\npassword=\"${MYSQL_PASSWD}\"" | tee ~/.my.cnf && \
  echo -e "[mysqld]\ndefault-authentication-plugin = mysql_native_password" | sudo tee /etc/mysql/mysql.conf.d/default-auth-override.cnf && \
  service mysql restart && \

  return 0 || \
  err "Could not setup MySQL 8"
}


#######################################
# Setup database for WordPress
# Globals:
#   MYSQL_PASSWD
#   WP_MYSQL_DATABASE
#   WP_MYSQL_USER
#   WP_MYSQL_PASSWD
# Arguements:
#   None
# Returns:
#   None
#######################################
setup_database() {
  mysql -u root -p${MYSQL_PASSWD} -e "
FLUSH PRIVILEGES;
CREATE DATABASE ${WP_MYSQL_DATABASE};
CREATE USER '${WP_MYSQL_USER}'@'localhost' IDENTIFIED BY '${WP_MYSQL_PASSWD}';
GRANT ALL PRIVILEGES ON ${WP_MYSQL_DATABASE}.* TO '${WP_MYSQL_USER}'@'localhost';
FLUSH PRIVILEGES;" && \

  return 0 || \
  err "Could not setup MySQL database"
}


#######################################
# Install WP-CLI
# Globals:
#   None
# Arguements:
#   None
# Returns:
#   None
#######################################
install_wpcli() {
  curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
  mv wp-cli.phar /usr/local/bin/wp && \
  ln -s /usr/local/bin/wp /usr/bin/wp && \
  chmod 755 /usr/local/bin/wp && \

  return 0 || \
  err "Could not install WP-CLI"
}

#######################################
# Install WordPress Core
# Globals:
#   WP_MYSQL_DATABASE
#   WP_MYSQL_USER
#   WP_MYSQL_PASSWD
# Arguements:
#   None
# Returns:
#   None
#######################################
install_wordpress() {
  sudo -u www-data wp --path=/sites/${FQDN}/public core download && \
  sudo -u www-data wp --path=/sites/${FQDN}/public config create --dbname="${WP_MYSQL_DATABASE}" --dbuser="${WP_MYSQL_USER}" --dbhost="127.0.0.1" --dbpass="${WP_MYSQL_PASSWD}" && \
  sudo -u www-data wp --path=/sites/${FQDN}/public core install --url="${FQDN}" --title="Wordpress Site" --admin_user="${WP_ADMIN_USER}" --admin_password="${WP_ADMIN_PASSWD}" --admin_email="${WP_ADMIN_EMAIL}" && \

  return 0 || \
  err "Could not install WordPress"
}

#######################################
# Install cachesfilesd and mount EFS
# Globals:
#   EFS_ADDR
#   FQDN
# Arguements:
#   None
# Returns:
#   None
# Note: Only ran if EFS_ADDR is set
#######################################
setup_efs() {
  if [ ! -z "${EFS_ADDR}" ]; then
    # Install cachefilesd and nfs-common
    apt-get -y install cachefilesd nfs-common && \

    # Create efs mount directory and mount efs
    mkdir -p /efs && \
    echo "${EFS_ADDR}:/ /efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,_netdev 0 0" | tee -a /etc/fstab && \
    mount -a

    # Copy uploads content, remove original dir, and create symlink to efs
    rsync -avzh /sites/${FQDN}/public/wp-content/uploads/ /efs && \
    rm -r /sites/${FQDN}/public/wp-content/uploads/ && \
    ln -fs /efs /sites/${FQDN}/public/wp-content/uploads && \
    chown -h www-data. /sites/${FQDN}/public/wp-content/uploads && \
    
    return 0 || \
    err "Could not setup EFS"
  fi
}

#######################################
# Install cachesfilesd and mount EFS
# Globals:
#   EFS_ADDR
#   FQDN
# Arguements:
#   None
# Returns:
#   None
# Note: Only ran if EFS_ADDR is set
#######################################
setup_swap() {
  sudo fallocate -l 1G /swapfile && \
  sudo chmod 600 /swapfile && \
  sudo mkswap /swapfile && \
  sudo swapon /swapfile && \
  echo "/swapfile swap swap defaults 0 0" | tee -a /etc/fstab && \

  return 0 || \
  err "Could not setup swap"

}

#######################################
# Save auto-generated credentials to file
# Globals:
#   MYSQL_PASSWD
#   WP_MYSQL_DATABASE
#   WP_MYSQL_USER
#   WP_MYSQL_PASSWD
# Arguements:
#   None
# Returns:
#   None
#######################################
save_credentials() {
  echo -e "MySQL Root Password\n${MYSQL_PASSWD}\n\nWordPress Database Info\nDatabase: ${WP_MYSQL_DABATABSE}\nUser: ${WP_MYSQL_USER}\nPass: ${WP_MYSQL_PASSWD}\n\nWordPress\nUser: ${WP_ADMIN_USER}\nPass: ${WP_ADMIN_PASSWD}" \
    | tee -a ~/credentials && \
  
  return 0 || \
  err "Could not save credentials"
}


err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
  exit 1
}

main "$@"
#!/usr/bin/env bash

FQDN="$1"
CERTBOT_EMAIL="$2"
MYSQL_PASSWD="`tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1`"
WP_MYSQL_PASSWD="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)"
WP_MYSQL_USER="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)"
WP_MYSQL_DATABASE="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)"
WP_ADMIN_USER="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)"
WP_ADMIN_PASSWD="$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)"
EFS_ADDR=""

# Intial update
apt-get -y update && apt-get -y upgrade && apt-get -y autoremove && \

if [ ! -z "${EFS_ADDR}" ]; then
# Install cachefilesd and nfs-common
apt-get -y install cachefilesd nfs-common && \

# Create efs mount directory and mount efs
mkdir -p /efs && \
echo "${EFS_ADDR}:/ /efs nfs4 nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,fsc,_netdev 0 0" | tee -a /etc/fstab && \
mount -a
fi && \

# Add nginx repo and install
add-apt-repository -y ppa:ondrej/nginx && \
apt-get -y update && \
apt-get -y install nginx-full && \

# Add php repo and install
add-apt-repository -y ppa:ondrej/php && \
apt-get -y update && \
apt-get -y install php7.3-cli php7.3-common php7.3-fpm php7.3-mbstring php7.3-opcache php7.3-mysql && \

# Add certbot repo and install
add-apt-repository -y universe && \
add-apt-repository -y ppa:certbot/certbot && \
apt-get -y update && \
apt-get -y install certbot python-certbot-nginx && \

# Setup site directories
mkdir -p /sites/${FQDN}/{logs,public} && \
chown -R www-data. /sites/${FQDN} && \

# Grab NginX config from repo
mv /etc/nginx /etc/nginx.bak && \
git clone https://gitlab.com/optimull/wordpress-nginx.git /etc/nginx && \

# Copy example site to sites-enabled and replace the domain
cp /etc/nginx/sites-available/fastcgi-cache.com /etc/nginx/sites-enabled/${FQDN} && \
sed -i "s/fastcgi-cache.com/${FQDN}/g" /etc/nginx/sites-enabled/${FQDN} && \
service nginx restart && \

# Install MySQL 8.0
sudo apt-key adv --keyserver pgp.mit.edu --recv-keys 5072E1F5 && \
echo "deb http://repo.mysql.com/apt/ubuntu/ bionic mysql-8.0" | sudo tee /etc/apt/sources.list.d/mysql.list && \
apt-get update && \
sudo debconf-set-selections <<< "mysql-community-server mysql-community-server/root-pass password ${MYSQL_PASSWD}" && \
sudo debconf-set-selections <<< "mysql-community-server mysql-community-server/re-root-pass password ${MYSQL_PASSWD}" && \
sudo DEBIAN_FRONTEND=noninteractive apt-get -y install mysql-server && \
echo -e "[client]\nuser=root\npassword=\"${MYSQL_PASSWD}\"" | tee ~/.my.cnf && \
echo -e "[mysqld]\ndefault-authentication-plugin = mysql_native_password" | sudo tee /etc/mysql/mysql.conf.d/default-auth-override.cnf && \
service mysql restart && \

# Setup WordPress database
mysql -e "
FLUSH PRIVILEGES;
CREATE DATABASE ${WP_MYSQL_DATABASE};
CREATE USER '${WP_MYSQL_USER}'@'localhost' IDENTIFIED BY '${WP_MYSQL_PASSWD}';
GRANT ALL PRIVILEGES ON ${WP_MYSQL_DATABASE}.* TO '${WP_MYSQL_USER}'@'localhost';
FLUSH PRIVILEGES;" && \

# Install WP-CLI
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
mv wp-cli.phar /usr/local/bin/wp && \
ln -s /usr/local/bin/wp /usr/bin/wp && \
chmod 755 /usr/local/bin/wp && \

# Install WordPress
sudo -u www-data wp --path=/sites/${FQDN}/public core download && \
sudo -u www-data wp --path=/sites/${FQDN}/public config create --dbname="${WP_MYSQL_DATABASE}" --dbuser="${WP_MYSQL_USER}" --dbhost="127.0.0.1" --dbpass="${WP_MYSQL_PASSWD}" && \
sudo -u www-data wp --path=/sites/${FQDN}/public core install --url="${FQDN}" --title="Wordpress Site" --admin_user="${WP_ADMIN_USER}" --admin_password="${WP_ADMIN_PASSWD}" --admin_email="${CERTBOT_EMAIL}" && \

# Copy uploads content, remove original dir, and create symlink to efs
#rsync -avzh /sites/${FQDN}/public/wp-content/uploads/ /efs && \
#rm -r /sites/${FQDN}/public/wp-content/uploads/ && \
#ln -fs /efs /sites/${FQDN}/public/wp-content/uploads && \
#chown -h www-data. /sites/${FQDN}/public/wp-content/uploads

echo -e "MySQL Root Password\n${MYSQL_PASSWD}\n\nWordPress Database Info\n${WP_MYSQL_DABATABSE}\n${WP_MYSQL_USER}\n${WP_MYSQL_PASSWD}\n\nWordPress ${WP_ADMIN_USER}\n${WP_ADMIN_PASSWD}" | tee -a ~/credentials
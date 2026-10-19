#!/bin/bash
set -e
shell_quote() {
  local value="$1"
  value=${value//\'/\'\\\'\'}
  printf "'%s'" "$value"
}
/usr/local/bin/docker-entrypoint.sh "$@" &
server_pid=$!
db_ready() {
  php -r '$db = @new mysqli(getenv("WORDPRESS_DB_HOST"), getenv("WORDPRESS_DB_USER"), getenv("WORDPRESS_DB_PASSWORD"), getenv("WORDPRESS_DB_NAME")); if ($db->connect_errno) { exit(1); } $db->close();' >/dev/null 2>&1
}
for i in $(seq 1 60); do
  if db_ready; then break; fi
  sleep 3
done
if ! db_ready; then echo 'WordPress database did not become available'; exit 1; fi
if ! su -s /bin/sh www-data -c 'wp --path=/var/www/html core is-installed' >/dev/null 2>&1; then
  install_command="wp --path=/var/www/html core install --url=$(shell_quote "$WP_HOME") --title=$(shell_quote 'Urumi Demo Store') --admin_user=$(shell_quote "$WP_ADMIN_USER") --admin_password=$(shell_quote "$WP_ADMIN_PASSWORD") --admin_email=$(shell_quote "$WP_ADMIN_EMAIL") --skip-email"
  su -s /bin/sh www-data -c "$install_command"
fi
su -s /bin/sh www-data -c 'wp --path=/var/www/html plugin is-active woocommerce' >/dev/null 2>&1 || su -s /bin/sh www-data -c 'wp --path=/var/www/html plugin activate woocommerce'
if ! su -s /bin/sh www-data -c 'wp --path=/var/www/html option get urumi_bootstrapped' >/dev/null 2>&1; then
  su -s /bin/sh www-data -c 'wp --path=/var/www/html option update woocommerce_store_address "Demo Street"'
  su -s /bin/sh www-data -c 'wp --path=/var/www/html option update woocommerce_store_city "Bengaluru"'
  su -s /bin/sh www-data -c 'wp --path=/var/www/html option update woocommerce_default_country "IN:KA"'
  su -s /bin/sh www-data -c 'wp --path=/var/www/html option update woocommerce_currency "INR"'
  su -s /bin/sh www-data -c 'wp --path=/var/www/html option update timezone_string "Asia/Kolkata"'
  su -s /bin/sh www-data -c 'wp --path=/var/www/html option update gmt_offset "5.5"'
  su -s /bin/sh www-data -c 'wp --path=/var/www/html option update woocommerce_enable_guest_checkout "yes"'
  su -s /bin/sh www-data -c 'wp --path=/var/www/html option update woocommerce_cod_settings "{\"enabled\":\"yes\",\"title\":\"Cash on delivery\",\"description\":\"Demo checkout\",\"instructions\":\"Pay when delivered\",\"enable_for_methods\":\"\",\"enable_for_virtual\":\"yes\"}" --format=json'
  su -s /bin/sh www-data -c 'wp --path=/var/www/html option update urumi_bootstrapped 1'
fi
wait "$server_pid"

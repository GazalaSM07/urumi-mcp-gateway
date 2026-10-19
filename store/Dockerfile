FROM wordpress:6.8.1-php8.2-apache
RUN apt-get update && apt-get install -y --no-install-recommends curl unzip && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar -o /usr/local/bin/wp \
 && chmod +x /usr/local/bin/wp \
 && curl -fsSL https://downloads.wordpress.org/plugin/woocommerce.9.8.5.zip -o /tmp/woo.zip \
 && unzip -q /tmp/woo.zip -d /usr/src/wordpress/wp-content/plugins && rm /tmp/woo.zip
COPY start.sh /usr/local/bin/urumi-start
RUN chmod +x /usr/local/bin/urumi-start
ENTRYPOINT ["/usr/local/bin/urumi-start"]
CMD ["apache2-foreground"]

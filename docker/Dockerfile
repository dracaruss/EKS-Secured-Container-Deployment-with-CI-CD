FROM php:8.1-apache
 
# Install dependencies osTicket needs
RUN apt-get update && apt-get install -y \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libxml2-dev \
    libzip-dev \
    libicu-dev \
    unzip \
    wget \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install gd mysqli xml zip intl opcache \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
 
# Enable Apache mod_rewrite
RUN a2enmod rewrite
 
# Download and extract osTicket
RUN wget https://github.com/osTicket/osTicket/releases/download/v1.18.1/osTicket-v1.18.1.zip -O /tmp/osticket.zip \
    && unzip /tmp/osticket.zip -d /tmp/osticket \
    && cp -r /tmp/osticket/upload/* /var/www/html/ \
    && cp /var/www/html/include/ost-sampleconfig.php /var/www/html/include/ost-config.php \
    && chown -R www-data:www-data /var/www/html \
    && chmod 0644 /var/www/html/include/ost-config.php \
    && rm -rf /tmp/osticket /tmp/osticket.zip


# Disable Deprecated notices so the UI doesn't break
RUN echo "error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT" > /usr/local/etc/php/conf.d/error-logging.ini
RUN echo "display_errors = Off" >> /usr/local/etc/php/conf.d/error-logging.ini
 
EXPOSE 80
CMD ["apache2-foreground"]

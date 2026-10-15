# This default matches the server version currently installed on Server 1.
# Override it only after confirming the version stored on the application PVC.
ARG NEXTCLOUD_BASE_IMAGE=nextcloud:35.0.1-apache
FROM ${NEXTCLOUD_BASE_IMAGE}

LABEL org.opencontainers.image.title="MyEduDrive Server" \
      org.opencontainers.image.description="MyEduDrive branded file workspace server" \
      org.opencontainers.image.vendor="MyEduDrive"

# Keep branding assets outside /var/www/html: the deployment mounts its PVC
# over that directory, which would hide files baked into it.
COPY landing/assets/myedudrive-logo-transparent-v2.png /usr/local/share/myedudrive/logo.png
COPY landing/assets/myedudrive-symbol-transparent.png /usr/local/share/myedudrive/logo-header.png
COPY images/nextcloud/theme/ /usr/local/share/myedudrive/theme/
COPY landing/ /usr/local/share/myedudrive/landing/
COPY images/nextcloud/config/myedudrive-skeleton.config.php /usr/src/nextcloud/config/myedudrive-skeleton.config.php
COPY images/nextcloud/apply-branding.sh /usr/local/bin/myedudrive-apply-branding
COPY images/nextcloud/99-myedudrive-branding.sh /docker-entrypoint-hooks.d/post-installation/99-myedudrive-branding.sh
COPY images/nextcloud/apache-myedudrive-landing.conf /etc/apache2/conf-available/myedudrive-landing.conf

RUN chmod 0755 /usr/local/bin/myedudrive-apply-branding \
    /docker-entrypoint-hooks.d/post-installation/99-myedudrive-branding.sh \
 && a2enconf myedudrive-landing

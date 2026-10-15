#!/bin/sh
set -eu

OCC="/var/www/html/occ"
LOGO="/usr/local/share/myedudrive/logo.png"
HEADER_LOGO="/usr/local/share/myedudrive/logo-header.png"
THEME_SOURCE="/usr/local/share/myedudrive/theme"
THEME_DEST="/var/www/html/themes/myedudrive"

if [ ! -f "$OCC" ]; then
  echo "MyEduDrive server is not initialized at /var/www/html yet." >&2
  exit 1
fi

if [ ! -r "$LOGO" ]; then
  echo "MyEduDrive logo is missing from this image: $LOGO" >&2
  exit 1
fi

if [ ! -r "$HEADER_LOGO" ] || [ ! -r "$THEME_SOURCE/defaults.php" ]; then
  echo "MyEduDrive theme assets are incomplete in this image." >&2
  exit 1
fi

mkdir -p "$THEME_DEST"
cp -R "$THEME_SOURCE/." "$THEME_DEST/"
if [ "$(id -u)" -eq 0 ]; then
  chown -R www-data:www-data "$THEME_DEST"
fi

run_occ() {
  if [ "$(id -u)" -eq 0 ]; then
    su -s /bin/sh -c 'php /var/www/html/occ "$@"' -- www-data myedudrive-apply-branding "$@"
  else
    php "$OCC" "$@"
  fi
}

# Nextcloud's supported theme mechanism overrides the product name and other
# built-in labels which the Theming app's instance name alone does not change.
run_occ config:system:set theme --value=myedudrive

# Nextcloud 35 copies core/skeleton (sample documents, images and templates)
# into a user's files on first login. An empty skeletondirectory disables this
# provisioning without touching any files already stored in user accounts.
run_occ config:system:set skeletondirectory --value='' --type=string

# Suppress both the welcome modal and the release carousel for every account.
run_occ app:disable firstrunwizard

run_occ theming:config name "MyEduDrive"
run_occ theming:config slogan "Store. Access. Learn. Anywhere."
run_occ theming:config primary_color "#1769e0"
run_occ theming:config logo "$LOGO"
run_occ theming:config logoheader "$HEADER_LOGO"
run_occ theming:config favicon "$HEADER_LOGO"

echo "MyEduDrive branding applied."

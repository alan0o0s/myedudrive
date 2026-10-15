#!/bin/sh
set -eu

# The official Nextcloud image invokes this hook only after first installation.
# That is when its database-backed global branding and first-run settings can
# safely be initialized, before the first account signs in.
exec /usr/local/bin/myedudrive-apply-branding

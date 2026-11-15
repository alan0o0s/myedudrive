# MyEduDrive Branding Audit

## Scope and findings

The available source consists of deployment files and the landing page; the upstream server application source is not included in this project. The branding shown to users is therefore treated separately from the application identifiers required by Kubernetes and the server.

- The `landing/` page uses the MyEduDrive brand and contains no textual references to the old brand.
- The unified MyEduDrive image uses the official Theme mechanism to set the product name, titles, organization, and default identity. A post-installation hook applies the branding after a new Nextcloud installation, and `scripts/deploy.sh` reapplies it to an existing PVC.
- `firstrunwizard` is disabled globally after installation. This app displays the welcome dialog and release news for a new user; its setting is stored in the database and does not touch user files.
- The login page and templates that use defaults inherit the Theme identity. Core files were not modified, and no global JavaScript or CSS was injected.
- Other text embedded in application pages or translations is not available in this repository. We cannot claim that all such text has changed until the image is published and the interface is inspected. We do not replace it in core files or with global JavaScript/CSS; further customization requires a separate app or Theme and a compatibility review for version 35.
- The references listed below are the expected remaining matches after a search; they are technical identifiers or administrative documentation describing the engine and its commands.

## Reference inventory and classification

| File / location | Text or context | Classification | Action and reason |
|---|---|---|---|
| `images/nextcloud/Dockerfile` | `FROM nextcloud:35.0.1-apache` and `NEXTCLOUD_BASE_IMAGE` build argument | Technical | Keep to inherit the version compatible with existing data. The published distribution image is named `myedudrive-server`. |
| `images/nextcloud/theme/defaults.php` | Product name, title, organization, logo, and color values | Official Theme / UI | Displays MyEduDrive without changing core files; the system activates the Theme under the name `myedudrive`. |
| `images/nextcloud/theme/core/img/logo.*` | Default Theme logos | User interface | Replaces the engine logos with MyEduDrive assets using the supported Theme structure. |
| `k8s/base/nextcloud.yaml` | PVC, Service, Deployment, container, and `nextcloud` selector names; `NEXTCLOUD_*` keys; base image | Protected technical identifiers | Keep because these names are used for references, selectors, and configuration. The overlay changes **only the image value** to the MyEduDrive account image. |
| `k8s/base/nextcloud-cron.yaml` | CronJob name, selectors, volume, `occ`, `cron.php`, and base image | Protected technical identifiers | Keep identifiers and commands. Only the administrator-facing failure message was changed from the engine name to MyEduDrive. The overlay changes the CronJob image to the same server image. |
| `k8s/base/kustomization.yaml` | Resource filenames for the server and CronJob | Protected technical identifiers | Keep because it includes the manifest paths in the bundle. |
| `k8s/base/myedudrive-web.yaml` | Historical NodePort name `myedudrive-nginx` | Technical name retained for compatibility | The Service keeps port `30080` but selects Nextcloud directly; there is no longer an NGINX Deployment or application container in the request path. |
| `k8s/overlays/dockerhub/kustomization.yaml` | `name: nextcloud` as the Kustomize image replacement target | Protected technical identifier | Keep the source image name targeted by Kustomize; the replacement value is `alan0o0s/myedudrive-server:v1.1.2`. |
| `k8s/overlays/scaling/hpa.yaml` | HPA name and `nextcloud` Deployment target | Protected technical identifiers | Keep so the HPA remains attached to the correct Deployment. |
| `scripts/deploy.sh`, `scripts/verify.sh` | `kubectl` resource names and `php occ status` | Technical | These are Kubernetes/runtime commands, not product UI text, and should not be changed arbitrarily. Deployment now uses the Docker Hub overlay and then configures the Theme. |
| `scripts/enable-scaling.sh`, `scripts/hpa-smoke.sh` | PVC/HPA/Deployment names and label selector | Protected technical identifiers | Keep the matching identifiers so the scaling check continues to work. The terminal PASS message now says MyEduDrive. |
| `scripts/build-images.sh` | `NEXTCLOUD_VERSION`, Docker Hub base image name, Dockerfile path | Protected technical identifiers | Keep build variable names and source image; the resulting image is named `myedudrive-server`. |
| `secrets.env.example` | `MARIADB_DATABASE`, `MARIADB_USER`, and `NEXTCLOUD_*` keys | Protected technical identifiers | These values and keys are tied to initialization and the database. Do not rename them after creating the PVC/database. |
| `secrets.env` | Local credentials, database/user names, and configuration keys | Secret and protected technical data | Not changed or copied into the images. Credential values are not shown in this audit; the file is excluded from Git. |
| `README.md`, `FILES_EXPLAINED_AND_TESTS_EN.md`, `DOCKER_HUB_AND_BRANDING_EN.md` | Engine references in architecture descriptions, release instructions, commands, and PVC guidance | Administrative/technical documentation | Use MyEduDrive as the product name, keeping the original engine name only when explaining the engine or its commands. This clarifies the image base for developers and is not shown to application users. |
| Server 1 guide PDF (not included in this repository) | Deployment, HPA, `NEXTCLOUD_*`, and Kubernetes command descriptions | Administrative/technical documentation | Does not change the product UI; these references describe the runtime engine and actual resource names. |
| `landing/index.html`, `landing/styles.css`, `landing/script.js`, `landing/assets/` | Brand and logos shown to landing-page visitors | User interface | The page uses MyEduDrive branding. Arabic/English language support is being removed as part of the English-only documentation/site update; light and dark themes remain. |
| `images/nextcloud/apply-branding.sh` | Identity configuration and Theme activation | Official UI/configuration | Copies Theme files from the image to the PVC, activates the Theme with the official system setting, then applies Theming settings. Error messages say MyEduDrive; `occ` commands remain technical identifiers. |
| `images/nextcloud/apply-branding.sh`, `99-myedudrive-branding.sh` | Disabling `firstrunwizard` | New-user interface | After a new installation, disables the app globally so new users do not see the welcome dialog or “What's new” panel. For an existing installation, `scripts/deploy.sh` reapplies the setting. |

## Verification limits

The changed YAML and script strings are descriptive text only; resource names, selectors, and paths were not changed. Building the image confirms that an artifact can be created, but does not by itself prove that every browser view displays the logo. Final UI verification requires publishing the image to Docker Hub and inspecting the landing page, `/login`, the signed-in interface, the favicon, and a test email. Report any remaining branding before deciding on further customization.

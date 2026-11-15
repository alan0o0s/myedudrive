# Unified MyEduDrive Image

## Design

The `alan0o0s/myedudrive-server:v1.1.2` repository contains a single image based on Nextcloud `35.0.1-apache`. Apache serves the landing page and its static assets at `/`, while continuing to serve Nextcloud at `/login`, WebDAV, and application endpoints. The deployment needs **one application container** alongside the external MariaDB and Redis services; there is no separate landing-page container.

The image does not contain database data, user files, or passwords. PVCs, Secrets, MariaDB, and Redis remain separate resources. Nextcloud data persists when the image is replaced because `/var/www/html` remains on a PVC.

The image keeps the welcome dialog and “What's new” panel hidden for new users in either installation state:

- New installation: a hook in the official Nextcloud image applies the branding settings and disables `firstrunwizard` after installation succeeds and before the first sign-in.
- Existing installation/PVC: `scripts/deploy.sh` applies the settings after the application is ready. It does not reinstall the database.

The official Nextcloud `skeletondirectory` setting is also set to an empty string. The sample files shown in Files come from `core/skeleton`, which Nextcloud copies into a user's files at first sign-in. The setting is included in an additional configuration file before first installation and is reapplied by the branding script for an existing PVC. This leaves the original skeleton in the application files and deletes no user files; existing users keep their previous copies, while new accounts start empty.

The official Nextcloud image documents a `post-installation` hook that runs after installation is complete and only executes files ending in `.sh` from the hook directory. [Official hook reference](https://github.com/nextcloud/docker#auto-configuration-via-hook-folders)

## Build a version matching the installed release

Check the Nextcloud version in the PVC before building:

```bash
kubectl -n myedudrive exec deployment/nextcloud -- php occ status
```

Then, from the project directory:

```bash
export DOCKERHUB_USERNAME='alan0o0s'
export NEXTCLOUD_VERSION='35.0.1'
export IMAGE_TAG='v1.1.2'
./scripts/build-images.sh
```

Do not use an image newer than the version stored in the PVC. A Nextcloud upgrade requires a separate backup and migration plan.

## Isolated local preview

Start a new stack on port 8081, isolated from Minikube and previous preview data:

```bash
PREVIEW_HTTP_PORT=8081 docker compose -p myedudrive-unified -f compose.preview.yaml up -d
```

Open `http://127.0.0.1:8081`. Confirm the landing page appears, try its sign-in button to `/login`, and verify that the interface shows MyEduDrive and `firstrunwizard` is disabled:

```bash
docker compose -p myedudrive-unified -f compose.preview.yaml exec nextcloud \
  su -s /bin/sh www-data -c 'php /var/www/html/occ app:list --disabled'
```

On first startup, the hook applies the branding after installation completes. If a PVC already exists, run this once:

```bash
docker compose -p myedudrive-unified -f compose.preview.yaml exec nextcloud \
  /usr/local/bin/myedudrive-apply-branding
```

Stop only the test containers while keeping the test data:

```bash
docker compose -p myedudrive-unified -f compose.preview.yaml stop
```

## Publish to Docker Hub

After the image passes local checks, sign in with a Docker Access Token at the prompt. Do not put the token in the project files:

```bash
docker login --username alan0o0s
docker push alan0o0s/myedudrive-server:v1.1.2
```

Use a fixed version tag for each build. Do not use `latest` as the deployment reference.

## Kubernetes on Server 1

The `k8s/overlays/dockerhub` overlay switches the Deployment and CronJob images to the MyEduDrive repository. The NodePort remains `30080` and the access address remains unchanged: the historical external `myedudrive-nginx` Service now routes directly to the application Pods, while the internal `nextcloud` Service handles connections inside the namespace. After rollout, as described by the manifest, `deploy.sh` removes only the old NGINX Deployment and ConfigMap; it does not delete PVCs, the database, or Redis.

Review what will be applied before deployment:

```bash
kubectl kustomize k8s/overlays/dockerhub
```

Then deploy after reviewing the output:

```bash
minikube start
kubectl config use-context minikube
./scripts/deploy.sh
```

The Server 1 URL remains:

```text
http://<MINIKUBE-IP>:30080/
```

`/` opens the landing page, and its sign-in links open `/login`. MariaDB, Redis, PVC references, and Secrets remain outside the application image. This image is for the current Server 1/Minikube setup and is not multi-node Kubernetes HA.

## Private Docker Hub repository

If you make the repository private, create a Kubernetes `imagePullSecret` with an Access Token and add it to the Deployment and CronJob Pod specs. Do not store Docker credentials in Git or YAML files.

## Branding limits

The supported Nextcloud Theme mechanism is used without modifying core files. `nextcloud`, the `NEXTCLOUD_*` variable names, and `php occ` remain technical identifiers required for operation. Any remaining text embedded in core files or translations requires a separately compatible Theme/app and is not replaced automatically.

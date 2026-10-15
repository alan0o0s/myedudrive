# MyEduDrive — Server 1 Setup Guide

This guide prepares **MyEduDrive on Server 1 only** using Minikube, MariaDB, and Redis. A single application image combines the landing page and the MyEduDrive server (based on Nextcloud) in **one container**. Apache serves the landing page at `/` and routes `/login`, WebDAV, and application endpoints to MyEduDrive. All Kubernetes resources are placed in the `myedudrive` namespace, and application data is stored in PVCs.

## Scope of This Stage

- The current Minikube environment is a single-node test environment. It is not a Kubernetes cluster spanning both servers and does not provide real high availability (HA).
- The base deployment starts one MyEduDrive server replica, one MariaDB replica, and one Redis replica.
- The HPA configuration for scaling from 2 to 10 Pods is in a separate overlay and is not enabled automatically by the base configuration.
- `ReadWriteOnce` is suitable for testing on one node. Before distributing Nextcloud across multiple nodes, you need a StorageClass that supports `ReadWriteMany` and a safe migration to a new PVC. Changing the access mode alone does not turn local storage into shared storage.
- MariaDB and Redis each run as a single instance in this stage. The project files do not claim database or Redis HA or replication.
- The unified application image is branded as MyEduDrive and published on Docker Hub. The current image is based on Nextcloud `35.0.1`; the database and user files are not included in the image.

## Requirements

- Minikube is running, and `kubectl` has access to its Kubernetes context.
- A default StorageClass and its provisioner are working.
- `kubectl`, `minikube`, and Bash are installed.
- Enough storage is available for the PVCs: MariaDB 10 GiB, Redis 2 GiB, and Nextcloud 20 GiB. Actual capacity depends on the provisioner.

## 1. Prepare Secrets

From this directory:

```bash
cp secrets.env.example secrets.env
openssl rand -hex 24
```

Set different randomly generated passwords in `secrets.env`, and keep the file on the machine. `.gitignore` excludes it from Git. Keep these values so you can recover database and admin access. Changing the passwords in a Kubernetes Secret does not change passwords inside MariaDB after its first initialization.

## 2. Start Minikube and Deploy the Services

Build and test the unified image locally, then publish it to Docker Hub using the [Docker Hub and Branding Guide](DOCKER_HUB_AND_BRANDING_AR.md). The current tag is `v1.1.2` in the `alan0o0s/myedudrive-server` repository. Make the repository public or configure an `imagePullSecret`.

```bash
minikube start
kubectl config use-context minikube
./scripts/deploy.sh
```

The script creates the namespace and Secret, deploys the Docker Hub image, and waits for MariaDB, Redis, and Nextcloud to become ready. It repoints the existing NodePort to the unified application and then removes only the old NGINX Deployment and ConfigMap. It applies the MyEduDrive branding and disables `firstrunwizard`. It does not delete PVCs or the database.

To run the unified image locally in a Docker stack isolated from Minikube:

```bash
PREVIEW_HTTP_PORT=8081 docker compose -p myedudrive-unified -f compose.preview.yaml up -d
```

Open `http://127.0.0.1:8081`. This command uses separate preview database and application data.

## 3. Open MyEduDrive Locally

```bash
minikube ip
```

After deployment and before opening the site, add the displayed IP address as a trusted domain in Nextcloud:

```bash
kubectl -n myedudrive exec deployment/nextcloud -- php occ config:system:set trusted_domains 1 --value="$(minikube ip)"
```

Then open:

```text
http://<MINIKUBE-IP>:30080
```

The root path displays the landing page. The sign-in button opens `/login` and keeps `:30080` in the URL. The NodePort Service retains the historical Kubernetes name `myedudrive-nginx` for compatibility, but it routes directly to the application Pod; the unified design does not include an NGINX application container.

The admin credentials are `NEXTCLOUD_ADMIN_USER` and `NEXTCLOUD_ADMIN_PASSWORD` from `secrets.env`. This configuration initializes Nextcloud with MariaDB and Redis. If the database or Nextcloud is already initialized, the initial setup variables will not recreate or reset it. Configure trusted proxy settings and external TLS/domain settings only after determining the actual proxy address in the final cluster.

## 4. Deployment Checks

```bash
./scripts/verify.sh
```

The checks cover resource and PVC status, the MariaDB health check, Redis `PING`, and `php occ status`. They do not delete data. To verify Nextcloud persistence manually, upload a small file through the web interface, restart the Nextcloud Pod, and confirm that the file is still there.

## 5. Enable the Optional HPA

Requirements: Metrics Server must be working (`kubectl top pods -n myedudrive` displays metrics), Nextcloud must pass its deployment checks, and the machine must have enough capacity for additional Pods. On Minikube, enable Metrics Server as follows:

```bash
minikube addons enable metrics-server
kubectl top pods -n myedudrive
./scripts/enable-scaling.sh
./scripts/hpa-smoke.sh
kubectl -n myedudrive get hpa nextcloud --watch
```

The HPA minimum is 2 replicas and the maximum is 10. Its CPU target is 70% of the 250m CPU request. The `hpa-smoke.sh` script temporarily adds CPU load inside each Nextcloud Pod, waits for 10 Pods to become ready, and automatically stops the load afterward—even if interrupted with Ctrl+C. After the load stops, the HPA can remain at the current replica count until its 300-second scale-down window expires. Ten replicas are a maximum, not a guarantee; scaling requires real CPU pressure and enough machine resources. Monitor CPU and memory on Server 1 during the test. `ReadWriteOnce` allows multiple Pods on **the same node**, but does not share data across different nodes.

## Project Files

- `k8s/base/`: Core resources, one replica of each service, and RWO storage.
- `k8s/overlays/scaling/`: Optional HPA configuration for 2–10 replicas.
- `k8s/overlays/dockerhub/`: Selects the MyEduDrive images published in the Docker Hub account.
- `images/nextcloud/`: Dockerfile for the unified image, Apache configuration, first-install hook, theme, and branding script.
- `landing/`: Landing page and assets included in the application image.
- `scripts/build-images.sh`: Builds one MyEduDrive image using the engine version compatible with the PVC data.
- `DOCKER_HUB_AND_BRANDING_AR.md`: Existing guide for building, publishing, and applying branding.
- `BRANDING_AUDIT_AR.md`: Existing audit of remaining brand names and technical identifiers.
- `scripts/deploy.sh`: Creates the Secret, deploys the account's images, and applies the official theme.
- `scripts/verify.sh`: Non-destructive deployment checks.
- `scripts/enable-scaling.sh`: Adds the HPA after the base deployment.
- `scripts/hpa-smoke.sh`: Tests HPA scaling up to 10 while automatically stopping CPU load.
- `secrets.env.example`: Contains only the names of the required values.

## Stop the Lab

```bash
minikube stop
```

Do not delete PVCs if their data matters. Do not use `kubectl delete -k k8s/base` as routine cleanup; deleting a PVC or StatefulSet may cause data loss, depending on the storage policy.

## Preparing for Server 2 Later

The next step is not to run a separate Minikube on Server 2 and call that HA. When Server 2 is available, choose a suitable single cluster (such as k3s or kubeadm), select shared or distributed storage, plan backups, and then migrate the data. After that, add Pod distribution across nodes and properly designed HA for the database and Redis, and review external access and TLS. The files in this stage provide an organized starting point; they do not automatically convert the deployment into a multi-node cluster.

# Kubernetes Files Explained and Tested Individually

This guide explains the files in `k8s/base`: what each section does, why the settings are used, and how to test each resource independently on Minikube.

> Commands assume that the terminal is open in the project directory `outputs/myedudrive` and that `kubectl` uses the Minikube context. `apply` commands create real resources. Start with a dry run, and do not delete PVCs or the Namespace because they may contain project data.

## Prepare the environment

```bash
minikube status
kubectl config current-context
kubectl get nodes
```

Minikube should report `Running`, and the context should be `minikube`. Prepare the Namespace and Secret before MariaDB and Nextcloud:

```bash
kubectl apply -f k8s/base/namespace.yaml
kubectl -n myedudrive create secret generic myedudrive-secrets \
  --from-env-file=secrets.env --dry-run=client -o yaml | kubectl apply -f -
```

The local `secrets.env` file contains secret values. Do not share its contents or put passwords in YAML.

Important: individual resource files do not set a namespace on each resource; Kustomize adds it when deploying the bundle. Therefore, when testing one file by itself, pass `-n myedudrive` to `kubectl apply`. Otherwise, `kubectl` may deploy it to the default Namespace.

Dependency order:

```text
Namespace + Secret
        ↓
  MariaDB + Redis
        ↓
      MyEduDrive image
   landing at /, files
  at /login and APIs
        ↓
 Nextcloud CronJob
```

## 1. `namespace.yaml`

### Sections and purpose

- `apiVersion: v1` and `kind: Namespace`: identify a Namespace resource in the Kubernetes API.
- `metadata.name: myedudrive`: the Namespace that holds the application resources.
- `metadata.labels`: an organizational label indicating that the Namespace is part of MyEduDrive.

The Namespace logically isolates this project's resources from `default` and other Kubernetes resources. Using `-n myedudrive` scopes a command to this project.

### Test independently

```bash
kubectl apply --dry-run=server -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/namespace.yaml
kubectl get namespace myedudrive --show-labels
```

Expected status: `Active`. Do not test cleanup by deleting the Namespace; that removes the resources inside it.

## 2. `kustomization.yaml`

### Sections and purpose

- `apiVersion` and `kind`: identify this as Kustomize configuration, not a Pod or Service.
- `namespace: myedudrive`: adds the Namespace to resources that support this field.
- `resources`: files included by Kustomize: Namespace, MariaDB, Redis, Nextcloud, external Service, and CronJob.
- The HPA is not included here; it is an optional overlay in `k8s/overlays/scaling`.

Kustomize reduces duplicated resource definitions and allows the base configuration to be deployed with separate optional additions.

### Inspect without deploying

```bash
kubectl kustomize k8s/base
kubectl apply --dry-run=server -k k8s/base
kubectl diff -k k8s/base
```

The first command prints the rendered YAML, the second validates it through the API Server without saving it, and the third shows differences from live resources. Actual deployment uses `kubectl apply -k k8s/base`.

## 3. `mariadb.yaml`

This file defines two Services and a database StatefulSet.

### `mariadb-headless` Service

- `clusterIP: None`: makes this a headless Service without a regular ClusterIP.
- `selector`: selects the Pod carrying the MariaDB label.
- `port: 3306` and `targetPort: mysql`: expose the MySQL/MariaDB port.
- The StatefulSet refers to this Service through `serviceName` to provide the Pod with a stable DNS name.

### `mariadb` Service

- `type: ClusterIP`: an internal connection address inside Kubernetes.
- `selector`: routes connections to the MariaDB Pod.
- The application uses the stable Service name `mariadb` and port `3306`; Nextcloud connects by Service name rather than a changing Pod address.

### StatefulSet and Pod

- `replicas: 1`: one instance in the Server 1 lab; this is not database HA or replication.
- `selector` and `template labels`: must match so the StatefulSet manages the correct Pods.
- `image: mariadb:11`: the database image.
- `env` and `secretKeyRef`: read the password and database name from a Secret rather than hard-coding them in YAML.
- `startupProbe`: waits for the database connection and InnoDB initialization, allowing a longer startup time.
- `readinessProbe`: does not mark the database ready until its health check passes.
- `livenessProbe`: detects when the database stops responding.
- `resources` requests/limits: reserve CPU and memory and set upper limits.
- `volumeMounts`: mounts storage at `/var/lib/mysql`, where MariaDB stores its files.
- `volumeClaimTemplates`: creates a persistent PVC named `data-mariadb-0` with 10 GiB capacity.
- `ReadWriteOnce`: requests that the disk be mounted for writing on one node.
- `terminationGracePeriodSeconds: 60`: gives the database time to shut down cleanly.

### Test MariaDB alone

The Namespace and Secret must already be ready:

```bash
kubectl apply --dry-run=server -n myedudrive -f k8s/base/mariadb.yaml
kubectl apply -n myedudrive -f k8s/base/mariadb.yaml
kubectl -n myedudrive rollout status statefulset/mariadb --timeout=5m
kubectl -n myedudrive get pods,svc,pvc
kubectl -n myedudrive exec mariadb-0 -- healthcheck.sh --connect --innodb_initialized
```

To test SQL from inside the container using secret environment variables:

```bash
kubectl -n myedudrive exec mariadb-0 -- sh -c \
  'mariadb -h 127.0.0.1 -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "SELECT 1;"'
```

Expected: `SELECT` prints `1`, and the PVC is `Bound`. Do not delete the PVC; doing so may lose the database.

## 4. `redis.yaml`

### Service

- `type: ClusterIP`: internal connectivity only.
- `selector`: routes the connection to the Redis Pod.
- `port: 6379` and `targetPort: redis`: the Redis port inside the cluster.

### StatefulSet and Pod

- `replicas: 1`: one Redis instance in the lab; there is no Sentinel, Redis Cluster, or HA.
- `image: redis:7-alpine`: a small Redis image.
- `args`: runs `redis-server` with AOF (append-only file) and periodic saves.
- `startupProbe`, `readinessProbe`, and `livenessProbe`: run `redis-cli ping`; the `PONG` response means Redis is responding.
- `resources`: CPU and memory requests and limits.
- `volumeMounts`: mounts a PVC at `/data`, where Redis data and AOF files are stored.
- `volumeClaimTemplates`: creates a 2 GiB `ReadWriteOnce` PVC named `data-redis-0`.

### Test Redis alone

```bash
kubectl apply --dry-run=server -n myedudrive -f k8s/base/redis.yaml
kubectl apply -n myedudrive -f k8s/base/redis.yaml
kubectl -n myedudrive rollout status statefulset/redis --timeout=5m
kubectl -n myedudrive exec redis-0 -- redis-cli PING
```

Expected: `PONG`. Test a temporary value:

```bash
kubectl -n myedudrive exec redis-0 -- redis-cli SET docs-test-key hello
kubectl -n myedudrive exec redis-0 -- redis-cli GET docs-test-key
kubectl -n myedudrive exec redis-0 -- redis-cli DEL docs-test-key
```

Expected: `OK`, then `hello`, then `1`. To test persistence, set a temporary key, delete only the `redis-0` Pod, wait for the StatefulSet to recreate it, then read and delete the key. This briefly interrupts Redis and does not demonstrate HA; perform it only in the lab.

## 5. `nextcloud.yaml`

This file defines the application PVC, an internal Service, and a Deployment.

### `nextcloud-data` PVC

- Requests 20 GiB using `ReadWriteOnce`.
- All Nextcloud Pods in the single-node Minikube use this PVC.
- RWO does not mean the disk is shared between Server 1 and Server 2.

### `nextcloud` Service

- `type: ClusterIP`: an internal DNS name used by the Nextcloud CronJob and other Kubernetes workloads.
- `selector`: selects Nextcloud Pods.
- `port: 80` and `targetPort: http`: route traffic to Apache inside the container.
- The HPA is not in this file; it is in a separate overlay.

### Deployment

- `replicas: 1`: the initial count. When HPA is enabled, the HPA manages the count from 2 to 10.
- `progressDeadlineSeconds: 1800`: allows time to download the image and start Nextcloud for the first time.
- `strategy: Recreate`: stops the old application instance before creating the replacement during an update, reducing overlap between updates that use the application directory. This does not prevent the HPA from creating multiple replicas.
- `image: nextcloud:apache` in the base; `k8s/overlays/dockerhub` replaces it with the unified MyEduDrive image. Apache in this image serves the landing page at `/` and Nextcloud at the remaining paths.
- `MYSQL_HOST=mariadb` and `REDIS_HOST=redis`: Service names Nextcloud connects to.
- Database and administrator credentials are read from a Secret.
- `NEXTCLOUD_TRUSTED_DOMAINS`: initial local values; add the Minikube address used by the browser.
- `PHP_MEMORY_LIMIT` and `PHP_UPLOAD_LIMIT`: PHP memory and upload-size limits.
- `startupProbe`: checks `/status.php` and allows enough time for the first installation.
- `readinessProbe`: prevents sending users to a Pod that is not ready.
- `livenessProbe`: restarts the container if it stops responding.
- `Host` header: `localhost` in health checks prevents the probe from being rejected because of trusted-domain validation.
- `requests.cpu: 250m`: important for calculating CPU utilization in the HPA.
- `volumeMounts`: mounts data at `/var/www/html`.
- `volumes.persistentVolumeClaim.claimName`: connects the Pod to the `nextcloud-data` PVC.

### Test Nextcloud alone

MariaDB, Redis, the Secret, and storage must be ready first:

```bash
kubectl apply --dry-run=server -n myedudrive -f k8s/base/nextcloud.yaml
kubectl apply -n myedudrive -f k8s/base/nextcloud.yaml
kubectl -n myedudrive rollout status deployment/nextcloud --timeout=30m
kubectl -n myedudrive exec deployment/nextcloud -- php occ status
kubectl -n myedudrive get pvc nextcloud-data
```

Expected: `occ status` reports that Nextcloud is installed, and the PVC is `Bound`. To test HTTP without NGINX, start a port-forward in one terminal:

```bash
kubectl -n myedudrive port-forward service/nextcloud 18080:80
```

In another terminal:

```bash
curl -i -H 'Host: localhost' http://127.0.0.1:18080/status.php
```

Stop the port-forward with Ctrl+C. Do not delete the `nextcloud-data` PVC; it contains Nextcloud files.

## 6. `myedudrive-web.yaml`

This file keeps the current NodePort Service so the Server 1 address remains on `:30080`, but now routes directly to the unified application Pods.

- `metadata.name: myedudrive-nginx` is a historical resource name; it does not mean that an NGINX container exists.
- `type: NodePort` and `nodePort: 30080` preserve the current browser URL.
- `selector: app.kubernetes.io/name: nextcloud` selects Pods running the unified image.
- `targetPort: http` sends the request to Apache port 80 inside the application.

Once the new image is ready, `scripts/deploy.sh` deletes the old NGINX Deployment and ConfigMap. It does not delete the external Service, PVC, or database.

### Test the Service after deploying the unified image

```bash
kubectl apply --dry-run=server -n myedudrive -f k8s/base/myedudrive-web.yaml
kubectl -n myedudrive get service myedudrive-nginx -o wide
kubectl -n myedudrive get endpoints myedudrive-nginx
```

Confirm that the endpoints point to Nextcloud Pods. Test through the NodePort:

```bash
MINIKUBE_IP="$(minikube ip)"
curl -sS -L -o /dev/null -w 'Final URL: %{url_effective}\nHTTP: %{http_code}\n' \
  "http://$MINIKUBE_IP:30080/"
```

Expected: `:30080` remains in the final URL and the result is HTTP 200. `/` displays the landing page and `/login` displays the MyEduDrive-branded sign-in page.

## 7. `nextcloud-cron.yaml`

### Sections and purpose

- `kind: CronJob`: creates a scheduled job instead of running cron inside every Nextcloud Pod.
- `schedule: "*/5 * * * *"`: every five minutes.
- `concurrencyPolicy: Forbid`: prevents two jobs from running at the same time.
- `startingDeadlineSeconds`: the allowed delay window for starting a job that missed its schedule.
- `successfulJobsHistoryLimit`/`failedJobsHistoryLimit`: how many previous jobs Kubernetes retains.
- `jobTemplate`: the Job and Pod template created by the CronJob.
- `backoffLimit: 2`: allows two retries after failure.
- `restartPolicy: OnFailure`: restarts the job Pod if it fails.
- `runAsUser: 33` and `runAsGroup: 33`: run the command as `www-data` instead of root.
- `command`: waits up to ten minutes for `installed=true` in `occ status`, then runs `cron.php`. If Nextcloud installation does not finish, it fails with a message.
- MariaDB and Redis variables are read from the same Services and Secret as Nextcloud.
- `volumeMounts`: mounts the same Nextcloud PVC at `/var/www/html` so the job can access `occ` and the files.
- `resources`: limits the resources used by the job.

### Test the CronJob alone

Nextcloud must be installed, and its PVC, Secret, database, and Redis must be available. Validate and apply the CronJob in the correct Namespace:

```bash
kubectl apply --dry-run=server -n myedudrive -f k8s/base/nextcloud-cron.yaml
kubectl apply -n myedudrive -f k8s/base/nextcloud-cron.yaml
```

Then create a test Job from the CronJob:

```bash
JOB="nextcloud-cron-test-$(date +%s)"
kubectl -n myedudrive create job --from=cronjob/nextcloud-cron "$JOB"
kubectl -n myedudrive wait --for=condition=complete "job/$JOB" --timeout=12m
kubectl -n myedudrive logs "job/$JOB"
```

The primary check is that the Job reaches `condition=complete`; logs may be empty if `cron.php` prints nothing. Delete only the test Job after inspection:

```bash
kubectl -n myedudrive delete job "$JOB"
```

Do not use `delete -f` on `nextcloud-cron.yaml` to clean up the test Job; that deletes the CronJob itself.

## Deploy and test the complete bundle

Kustomize combines the resources, but the Secret is created separately. After preparing it:

```bash
kubectl apply -k k8s/base
./scripts/verify.sh
kubectl -n myedudrive get pods,svc,pvc
```

The browser address is:

```text
http://<MINIKUBE-IP>:30080
```

## Before applying an individual file to a live cluster

The `apply -f` commands below modify real resources in the project Namespace; they are not simulations. Use `--dry-run=server` first. If HPA is enabled, do not apply `nextcloud.yaml` to the live cluster for a test; its initial replica value is 1 and may temporarily conflict with the HPA. Perform an actual deployment in Minikube or a separate test Namespace. Do not delete existing PVCs.

## Important notes

- `kubectl kustomize` and `--dry-run` do not deploy; `apply` creates real resources.
- Do not delete a PVC or Namespace as a quick test; data may be lost.
- Deleting a Pod to test storage persistence causes a brief outage; test in the lab only.
- MariaDB and Redis each have one instance; these checks do not demonstrate HA or replication.
- The current RWO setup is for a single Minikube node. Sharing across Server 1 and Server 2 requires a multi-node cluster and a different storage design.
- HPA from 2 to 10 is configured in `k8s/overlays/scaling/hpa.yaml`. To test it:

```bash
minikube addons enable metrics-server
kubectl top pods -n myedudrive
./scripts/enable-scaling.sh
./scripts/hpa-smoke.sh
```

# شرح ملفات Kubernetes واختبار كل ملف منفردًا

هذا الدليل يشرح ملفات المجلد k8s/base الظاهرة في الصورة: أجزاء كل ملف، سبب الإعدادات، وطريقة اختبار كل مورد بشكل مستقل على Minikube.

> الأوامر تفترض أن الطرفية مفتوحة في مجلد المشروع outputs/myedudrive، وأن kubectl يستخدم سياق Minikube. أوامر apply تنشئ موارد فعلية. ابدأ دائمًا بـdry-run، ولا تحذف PVC أو Namespace لأنهما قد يحتويان بيانات المشروع.

## تجهيز البيئة

~~~bash
minikube status
kubectl config current-context
kubectl get nodes
~~~

يجب أن يظهر Minikube بحالة Running، وأن يكون الـcontext هو minikube. جهز Namespace وSecret قبل MariaDB وNextcloud:

~~~bash
kubectl apply -f k8s/base/namespace.yaml
kubectl -n myedudrive create secret generic myedudrive-secrets \
  --from-env-file=secrets.env --dry-run=client -o yaml | kubectl apply -f -
~~~

ملف secrets.env محلي ويحوي القيم السرية. لا تشارك محتواه ولا تضع كلمات المرور في YAML.

مهم: ملفات الموارد الفردية لا تكتب namespace داخل كل مورد؛ Kustomize يضيفه عند النشر بالحزمة. لذلك عند اختبار ملف منفرد استخدم الخيار `-n myedudrive` مع kubectl apply، وإلا قد ينشره kubectl في namespace الافتراضية.

ترتيب الاعتمادية:

~~~text
Namespace + Secret
        ↓
  MariaDB + Redis
        ↓
      MyEduDrive image
   landing at /, files
  at /login and APIs
        ↓
 Nextcloud CronJob
~~~

## 1. namespace.yaml

### الأجزاء ولماذا

- apiVersion: v1 وkind: Namespace: نوع مورد Namespace من Kubernetes API.
- metadata.name: myedudrive: الاسم الذي نضع تحته موارد التطبيق.
- metadata.labels: وسم تنظيمي يوضح أن الـNamespace جزء من MyEduDrive.

الـNamespace يعزل موارد المشروع منطقيًا عن default وبقية موارد Kubernetes. عند استخدام الخيار -n myedudrive يصبح الأمر محددًا لهذا المشروع.

### اختبار مستقل

~~~bash
kubectl apply --dry-run=server -f k8s/base/namespace.yaml
kubectl apply -f k8s/base/namespace.yaml
kubectl get namespace myedudrive --show-labels
~~~

المتوقع STATUS=Active. لا تختبر التنظيف بحذف الـNamespace؛ حذفه يزيل الموارد التي بداخله.

## 2. kustomization.yaml

### الأجزاء ولماذا

- apiVersion وkind: يعرّفان هذا الملف كإعداد Kustomize، وليس Pod أو Service.
- namespace: myedudrive: يضيف الـNamespace إلى الموارد التي تقبل هذا الحقل.
- resources: الملفات التي يضمها Kustomize: namespace وMariaDB وRedis وNextcloud وService الخارجي وCronJob.
- HPA غير موجود هنا؛ له overlay اختياري في k8s/overlays/scaling.

Kustomize يقلل تكرار الموارد ويسمح بنشر الأساس مع إضافات منفصلة.

### اختبار من دون نشر

~~~bash
kubectl kustomize k8s/base
kubectl apply --dry-run=server -k k8s/base
kubectl diff -k k8s/base
~~~

الأول يعرض YAML الناتج فقط، والثاني يتحقق منه عبر API Server من دون حفظ، والثالث يعرض الفروق عن الموارد الحية. النشر الفعلي يكون بـkubectl apply -k k8s/base.

## 3. mariadb.yaml

يعرّف هذا الملف خدمتين وStatefulSet لقاعدة البيانات.

### خدمة mariadb-headless

- clusterIP: None: يجعلها Headless Service، من دون ClusterIP عادي.
- selector: يختار Pod التي عليها label الخاص بـMariaDB.
- port 3306 وtargetPort mysql: يفتحان منفذ MySQL/MariaDB.
- StatefulSet يشير إليها في serviceName لتوفير اسم DNS ثابت للـPod.

### خدمة mariadb

- type: ClusterIP: عنوان اتصال داخلي داخل Kubernetes.
- selector: يوجه الاتصالات إلى MariaDB Pod.
- الاسم mariadb والمنفذ 3306 ثابتان للتطبيق؛ Nextcloud يتصل باسم الخدمة لا بعنوان Pod المتغير.

### StatefulSet وPod

- replicas: 1: نسخة واحدة في مختبر Server 1؛ ليست قاعدة بيانات HA أو replication.
- selector وtemplate labels: يجب تطابقهما لكي يدير StatefulSet الـPods الصحيحة.
- image: mariadb:11: صورة قاعدة البيانات.
- env وsecretKeyRef: يقرآن كلمات المرور واسم DB من Secret، بدل تثبيتها في YAML.
- startupProbe: ينتظر اتصال DB وانتهاء تهيئة InnoDB، ويسمح بوقت إقلاع طويل.
- readinessProbe: لا يعتبر DB جاهزة قبل نجاح healthcheck.
- livenessProbe: يكتشف توقف DB عن الاستجابة.
- resources requests/limits: يحجزان CPU وذاكرة ويضعان حدًا أعلى.
- volumeMounts: يركب التخزين في /var/lib/mysql، حيث تحفظ MariaDB ملفاتها.
- volumeClaimTemplates: ينشئ PVC دائمة باسم data-mariadb-0 وسعتها 10Gi.
- ReadWriteOnce: يطلب تركيب القرص للكتابة على عقدة واحدة.
- terminationGracePeriodSeconds: 60: يمنح DB وقتًا للإغلاق المنظم.

### اختبار MariaDB وحدها

تحتاج Namespace وSecret جاهزين:

~~~bash
kubectl apply --dry-run=server -n myedudrive -f k8s/base/mariadb.yaml
kubectl apply -n myedudrive -f k8s/base/mariadb.yaml
kubectl -n myedudrive rollout status statefulset/mariadb --timeout=5m
kubectl -n myedudrive get pods,svc,pvc
kubectl -n myedudrive exec mariadb-0 -- healthcheck.sh --connect --innodb_initialized
~~~

لاختبار SQL من داخل الحاوية باستخدام متغيرات البيئة السرية:

~~~bash
kubectl -n myedudrive exec mariadb-0 -- sh -c \
  'mariadb -h 127.0.0.1 -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "SELECT 1;"'
~~~

المتوقع أن يعرض SELECT الرقم 1، وأن تكون PVC بحالة Bound. لا تحذف PVC؛ حذفها قد يفقد قاعدة البيانات.

## 4. redis.yaml

### الخدمة

- type: ClusterIP: اتصال داخلي فقط.
- selector: يوجه الاتصال إلى Redis Pod.
- port 6379 وtargetPort redis: منفذ Redis داخل الـcluster.

### StatefulSet وPod

- replicas: 1: Redis واحدة في المختبر؛ لا توجد Sentinel أو Redis Cluster أو HA.
- image: redis:7-alpine: صورة Redis صغيرة.
- args: تشغل redis-server مع AOF، أي append-only file، وحفظ دوري.
- startupProbe/readinessProbe/livenessProbe: تنفذ redis-cli ping؛ الرد PONG يعني أن Redis تستجيب.
- resources: طلبات وحدود CPU والذاكرة.
- volumeMounts: يركب PVC في /data، حيث تُحفظ بيانات Redis وAOF.
- volumeClaimTemplates: ينشئ PVC data-redis-0 بسعة 2Gi وReadWriteOnce.

### اختبار Redis وحدها

~~~bash
kubectl apply --dry-run=server -n myedudrive -f k8s/base/redis.yaml
kubectl apply -n myedudrive -f k8s/base/redis.yaml
kubectl -n myedudrive rollout status statefulset/redis --timeout=5m
kubectl -n myedudrive exec redis-0 -- redis-cli PING
~~~

المتوقع PONG. اختبر قيمة مؤقتة:

~~~bash
kubectl -n myedudrive exec redis-0 -- redis-cli SET docs-test-key hello
kubectl -n myedudrive exec redis-0 -- redis-cli GET docs-test-key
kubectl -n myedudrive exec redis-0 -- redis-cli DEL docs-test-key
~~~

المتوقع OK ثم hello ثم 1. يمكن اختبار persistence بوضع مفتاح مؤقت، ثم حذف Pod redis-0 وحدها والانتظار حتى يعيدها StatefulSet، ثم قراءة المفتاح وحذفه. هذا يسبب توقف Redis قصيرًا ولا يثبت HA؛ نفذه في المختبر فقط.

## 5. nextcloud.yaml

يعرّف PVC للتطبيق، وService داخلية، وDeployment.

### PVC nextcloud-data

- تطلب سعة 20Gi بوضع ReadWriteOnce.
- جميع Nextcloud Pods في Minikube ذي العقدة الواحدة تستخدم هذه الـPVC.
- RWO لا يعني أن القرص مشترك بين Server 1 وServer 2.

### Service nextcloud

- type: ClusterIP: اسم DNS داخلي تستخدمه Nextcloud CronJob وأي workload داخل Kubernetes.
- selector: يختار Nextcloud Pods.
- port 80 وtargetPort http: يوجهان الحركة إلى Apache داخل الحاوية.
- HPA ليس في هذا الملف؛ يوجد في overlay منفصل.

### Deployment

- replicas: 1: العدد الابتدائي. عند تفعيل HPA يصبح HPA مسؤولًا عن العدد بين 2 و10.
- progressDeadlineSeconds: 1800: يسمح بوقت لتنزيل الصورة وإقلاع Nextcloud أول مرة.
- strategy: Recreate: أثناء تحديث التطبيق يوقف النسخة القديمة قبل إنشاء الجديدة؛ يقلل تداخل تحديثين يستخدمان مجلد التطبيق. لا يمنع HPA من إنشاء نسخ متعددة.
- image: nextcloud:apache في base؛ `k8s/overlays/dockerhub` يستبدلها بصورة MyEduDrive الموحدة. Apache داخل هذه الصورة يقدّم landing عند `/` ويقدّم Nextcloud لباقي المسارات.
- MYSQL_HOST=mariadb وREDIS_HOST=redis: أسماء الخدمات التي يتصل بها Nextcloud.
- بيانات DB وadmin تُقرأ من Secret.
- NEXTCLOUD_TRUSTED_DOMAINS: قيم محلية ابتدائية؛ أضف عنوان Minikube للمتصفح.
- PHP_MEMORY_LIMIT وPHP_UPLOAD_LIMIT: حد الذاكرة وحجم الرفع في PHP.
- startupProbe: يفحص /status.php ويتيح وقتًا كافيًا لأول تثبيت.
- readinessProbe: لا يرسل المستخدمين إلى Pod غير جاهزة.
- livenessProbe: يعيد تشغيل الحاوية إذا توقفت عن الاستجابة.
- ترويسة Host: localhost في الفحوص تمنع رفض probe بسبب trusted domains.
- requests.cpu: 250m: مهم لحساب CPU utilization في HPA.
- volumeMounts: يركب البيانات داخل /var/www/html.
- volumes.persistentVolumeClaim.claimName: يربط الـPod بالـPVC nextcloud-data.

### اختبار Nextcloud وحدها

تحتاج MariaDB وRedis وSecret والتخزين أولًا:

~~~bash
kubectl apply --dry-run=server -n myedudrive -f k8s/base/nextcloud.yaml
kubectl apply -n myedudrive -f k8s/base/nextcloud.yaml
kubectl -n myedudrive rollout status deployment/nextcloud --timeout=30m
kubectl -n myedudrive exec deployment/nextcloud -- php occ status
kubectl -n myedudrive get pvc nextcloud-data
~~~

المتوقع أن يقول occ status إن Nextcloud مثبتة، وأن تكون PVC بحالة Bound. لاختبار HTTP من دون NGINX افتح port-forward في طرفية:

~~~bash
kubectl -n myedudrive port-forward service/nextcloud 18080:80
~~~

وفي طرفية أخرى:

~~~bash
curl -i -H 'Host: localhost' http://127.0.0.1:18080/status.php
~~~

أوقف port-forward بـCtrl+C. لا تحذف PVC nextcloud-data؛ تحتوي ملفات Nextcloud.

## 6. myedudrive-web.yaml

هذا الملف يحتفظ بخدمة NodePort الحالية كي يظل عنوان Server 1 على `:30080` كما هو، لكنه يوجّه الآن مباشرة إلى Pods التطبيق الموحد.

- metadata.name: `myedudrive-nginx` اسم مورد تاريخي محفوظ؛ لا يعني أن هناك NGINX container.
- type: NodePort وnodePort: 30080: يحافظان على رابط المتصفح الحالي.
- selector: `app.kubernetes.io/name: nextcloud` يختار Pods التي تشغّل الصورة الموحدة.
- targetPort: http: يرسل الطلب إلى منفذ Apache 80 داخل التطبيق.

بعد جاهزية الصورة الجديدة، `scripts/deploy.sh` يحذف Deployment وConfigMap القديمين الخاصين بـNGINX. لا يحذف Service الخارجي ولا PVC أو قاعدة البيانات.

### اختبار الخدمة بعد نشر الصورة الموحدة

~~~bash
kubectl apply --dry-run=server -n myedudrive -f k8s/base/myedudrive-web.yaml
kubectl -n myedudrive get service myedudrive-nginx -o wide
kubectl -n myedudrive get endpoints myedudrive-nginx
~~~

تأكد أن endpoints تشير إلى Nextcloud Pods. اختبر من NodePort:

~~~bash
MINIKUBE_IP="$(minikube ip)"
curl -sS -L -o /dev/null -w 'Final URL: %{url_effective}\nHTTP: %{http_code}\n' \
  "http://$MINIKUBE_IP:30080/"
~~~

المتوقع أن تظل `:30080` في Final URL، وأن تكون النتيجة HTTP 200. `/` يعرض landing و`/login` يعرض صفحة الدخول ذات علامة MyEduDrive.

## 7. nextcloud-cron.yaml

### الأجزاء ولماذا

- kind: CronJob: ينشئ مهمة مجدولة بدل تشغيل cron داخل كل Nextcloud Pod.
- schedule: "*/5 * * * *": كل خمس دقائق.
- concurrencyPolicy: Forbid: يمنع تشغيل مهمتين في الوقت نفسه.
- startingDeadlineSeconds: نافذة السماح بتشغيل مهمة تأخرت عن موعدها.
- successfulJobsHistoryLimit/failedJobsHistoryLimit: عدد المهام السابقة التي يحتفظ بها Kubernetes.
- jobTemplate: قالب Job وPod اللذين ينشئهما CronJob.
- backoffLimit: 2: يسمح بمحاولتي إعادة عند الفشل.
- restartPolicy: OnFailure: يعيد Pod المهمة إذا فشلت.
- runAsUser: 33 وrunAsGroup: 33: يشغلان الأمر كمستخدم www-data بدل root.
- command: ينتظر حتى عشر دقائق ظهور installed=true في occ status، ثم ينفذ cron.php. إن لم يكتمل تثبيت Nextcloud يفشل برسالة.
- متغيرات MariaDB وRedis تُقرأ مثل Nextcloud من الخدمات وSecret.
- volumeMounts: يستخدم PVC Nextcloud نفسها في /var/www/html ليصل إلى occ والملفات.
- resources: حدود للموارد التي تستخدمها المهمة.

### اختبار CronJob وحده

يحتاج Nextcloud مثبتة وPVC وSecret وDB وRedis شغالة. تحقق من ملف CronJob وطبقه داخل namespace الصحيح:

~~~bash
kubectl apply --dry-run=server -n myedudrive -f k8s/base/nextcloud-cron.yaml
kubectl apply -n myedudrive -f k8s/base/nextcloud-cron.yaml
~~~

ثم أنشئ Job تجريبية من CronJob:

~~~bash
JOB="nextcloud-cron-test-$(date +%s)"
kubectl -n myedudrive create job --from=cronjob/nextcloud-cron "$JOB"
kubectl -n myedudrive wait --for=condition=complete "job/$JOB" --timeout=12m
kubectl -n myedudrive logs "job/$JOB"
~~~

نجاح condition=complete هو الاختبار الأساسي؛ قد تكون السجلات فارغة إذا لم يطبع cron.php شيئًا. احذف Job التجريبية فقط بعد الفحص:

~~~bash
kubectl -n myedudrive delete job "$JOB"
~~~

لا تستخدم delete -f على nextcloud-cron.yaml لتنظيف Job الاختبار؛ ذلك يحذف CronJob نفسه.

## نشر الحزمة واختبارها كاملة

ملف Kustomize يجمع الموارد، لكن Secret ينشأ منفصلًا. بعد إعداده:

~~~bash
kubectl apply -k k8s/base
./scripts/verify.sh
kubectl -n myedudrive get pods,svc,pvc
~~~

عنوان المتصفح هو:

~~~text
http://<MINIKUBE-IP>:30080
~~~

## قبل تطبيق ملف منفرد على الكلاستر المستخدم

أوامر `apply -f` أدناه تعدّل موارد حقيقية في namespace المشروع؛ ليست محاكاة. استخدم `--dry-run=server` أولًا. إذا كان HPA مفعّلًا، لا تطبق nextcloud.yaml على الكلاستر الحي للتجربة؛ قيمة replicas الابتدائية فيه 1 وقد تتعارض مؤقتًا مع HPA. جرّب النشر الفعلي في Minikube أو namespace منفصل مخصص للتجربة. لا تحذف ملفات PVC الموجودة.

## تنبيهات مهمة

- kubectl kustomize و--dry-run لا ينشران؛ apply ينشئ موارد فعلية.
- لا تحذف PVC أو Namespace كتجربة سريعة؛ قد تفقد البيانات.
- حذف Pod لاختبار استمرارية التخزين يسبب توقفًا قصيرًا؛ اختبر في المختبر فقط.
- MariaDB وRedis نسخة واحدة؛ الاختبارات لا تثبت HA أو replication.
- RWO الحالي لعقدة Minikube الواحدة؛ المشاركة بين Server 1 وServer 2 تحتاج cluster متعدد العقد وتصميم تخزين آخر.
- HPA من 2 إلى 10 موجود في k8s/overlays/scaling/hpa.yaml. لتجربته:

~~~bash
minikube addons enable metrics-server
kubectl top pods -n myedudrive
./scripts/enable-scaling.sh
./scripts/hpa-smoke.sh
~~~


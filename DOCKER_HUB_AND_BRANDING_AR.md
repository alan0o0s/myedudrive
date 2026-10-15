# صورة MyEduDrive الموحدة

## التصميم

المستودع `alan0o0s/myedudrive-server:v1.1.2` يحتوي صورة واحدة مبنية من Nextcloud `35.0.1-apache`. Apache نفسه يقدّم landing page عند `/` وأصولها الثابتة، ويواصل تقديم Nextcloud عند `/login` وWebDAV وواجهات التطبيق. التشغيل يحتاج **حاوية تطبيق واحدة** بجانب MariaDB وRedis الخارجيين؛ لا توجد حاوية landing منفصلة.

لا تحتوي الصورة على بيانات قاعدة البيانات أو ملفات المستخدمين أو كلمات مرور. PVCs وSecret وMariaDB وRedis تظل موارد مستقلة. بيانات Nextcloud تستمر عبر استبدال الصورة لأن `/var/www/html` يبقى على PVC.

الصورة تضمن إخفاء نافذتي الترحيب و“What’s new” للمستخدمين الجدد بطريقتين حسب الحالة:

- تثبيت جديد: hook داخل صورة Nextcloud الرسمية ينفّذ إعداد الهوية ويعطّل `firstrunwizard` بعد نجاح التثبيت وقبل أول تسجيل دخول.
- تثبيت موجود/PVC موجودة: `scripts/deploy.sh` يطبّق الإعداد بعد جاهزية التطبيق. لا يعيد تثبيت قاعدة البيانات.

كما تُضبط قيمة Nextcloud الرسمية `skeletondirectory` على نص فارغ. ملفات الأمثلة الظاهرة في Files مصدرها `core/skeleton`، وNextcloud ينسخها إلى ملفات المستخدم عند أول دخول. الإعداد موجود في ملف إعداد إضافي قبل أول تثبيت، ويتكرر عبر سكربت الهوية للحالات التي لديها PVC مسبقة. بذلك يظل skeleton الأصلي داخل ملفات التطبيق ولا تُحذف أي ملفات مستخدم؛ المستخدمون الموجودون يحتفظون بنسخهم السابقة، والحسابات الجديدة تبدأ فارغة.

توثّق صورة Nextcloud الرسمية hook باسم `post-installation` بعد اكتمال التثبيت، ولا تشغّل إلا الملفات التنفيذية المنتهية بـ`.sh` داخل مجلد hook نفسه. [مرجع hooks الرسمي](https://github.com/nextcloud/docker#auto-configuration-via-hook-folders)

## بناء نسخة مطابقة للإصدار المثبّت

تحقق من إصدار Nextcloud داخل PVC قبل البناء:

```bash
kubectl -n myedudrive exec deployment/nextcloud -- php occ status
```

ثم من مجلد المشروع:

```bash
export DOCKERHUB_USERNAME='alan0o0s'
export NEXTCLOUD_VERSION='35.0.1'
export IMAGE_TAG='v1.1.2'
./scripts/build-images.sh
```

لا تستخدم إصدارًا أحدث من إصدار بيانات PVC؛ ترقية Nextcloud تحتاج خطة backup ومهاجرة مستقلة.

## تجربة محلية معزولة

ابدأ stack جديدًا على منفذ 8081، مستقلًا عن Minikube وعن بيانات Preview السابقة:

```bash
PREVIEW_HTTP_PORT=8081 docker compose -p myedudrive-unified -f compose.preview.yaml up -d
```

افتح `http://127.0.0.1:8081`. تحقق من ظهور landing page، ثم جرّب زر الدخول إلى `/login`، وتأكد أن الحالة تعرض MyEduDrive وأن `firstrunwizard` معطّل:

```bash
docker compose -p myedudrive-unified -f compose.preview.yaml exec nextcloud \
  su -s /bin/sh www-data -c 'php /var/www/html/occ app:list --disabled'
```

في أول تشغيل، hook يطبق الهوية بعد اكتمال التثبيت. مع PVC موجودة مسبقًا، نفّذ مرة واحدة:

```bash
docker compose -p myedudrive-unified -f compose.preview.yaml exec nextcloud \
  /usr/local/bin/myedudrive-apply-branding
```

لإيقاف حاويات الاختبار فقط مع إبقاء بيانات الاختبار:

```bash
docker compose -p myedudrive-unified -f compose.preview.yaml stop
```

## النشر إلى Docker Hub

بعد اجتياز اختبارات الصورة محليًا، سجّل الدخول باستخدام Access Token من مطالبة Docker، ولا تضعه في ملف المشروع:

```bash
docker login --username alan0o0s
docker push alan0o0s/myedudrive-server:v1.1.2
```

احتفظ بـtag إصدار ثابت لكل build. لا تستخدم `latest` لمرجع النشر.

## Kubernetes على Server 1

الـoverlay `k8s/overlays/dockerhub` يبدّل صورة Deployment وCronJob إلى مستودع MyEduDrive. يظل NodePort `30080` وعنوان الوصول كما هما: Service الخارجي التاريخي `myedudrive-nginx` أصبح يوجّه مباشرة إلى Pods التطبيق، بينما Service `nextcloud` الداخلي يخدم الاتصالات داخل namespace. بعد rollout وحسب الـmanifest، `deploy.sh` يحذف Deployment وConfigMap القديمين الخاصين بـNGINX فقط؛ لا يحذف PVCs أو قاعدة البيانات أو Redis.

اعرض ما سيُطبّق قبل النشر:

```bash
kubectl kustomize k8s/overlays/dockerhub
```

ثم انشره بعد مراجعة المخرجات:

```bash
minikube start
kubectl config use-context minikube
./scripts/deploy.sh
```

رابط Server 1 يظل:

```text
http://<MINIKUBE-IP>:30080/
```

`/` يفتح صفحة البداية، وروابطها تفتح `/login`. MariaDB وRedis ومراجع PVC وSecret تبقى خارج صورة التطبيق. الصورة خاصة بـServer 1/Minikube الحالي وليست Kubernetes HA متعدد العقد.

## مستودع Docker Hub خاص

لو جعلت repository خاصًا، أنشئ Kubernetes `imagePullSecret` باستخدام Access Token وأضفه إلى Pod specs الخاصة بـDeployment وCronJob. لا تحفظ Docker credentials في Git أو ملفات YAML.

## حدود إعادة العلامة التجارية

نستخدم آلية Nextcloud Theme المدعومة من دون تعديل ملفات core. `nextcloud` وأسماء متغيرات `NEXTCLOUD_*` و`php occ` تظل معرفات تقنية مطلوبة للتشغيل. أية نصوص متبقية مضمّنة في core أو الترجمات تحتاج Theme/App متوافقًا مستقلًا ولا يجري استبدالها آليًا.

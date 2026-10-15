# MyEduDrive — تجهيز Server 1

الحزمة دي بتجهّز **MyEduDrive على Server 1 فقط** باستخدام Minikube، مع MariaDB وRedis. صورة تطبيق واحدة تجمع صفحة البداية وخادم MyEduDrive (المبني على Nextcloud) في **container واحد**؛ Apache يقدّم الصفحة من `/` ويترك `/login` وWebDAV وواجهات التطبيق لخادم MyEduDrive. كل موارد Kubernetes داخل `myedudrive`، وبيانات التطبيقات محفوظة في PVCs.

## حدود المرحلة الحالية

- Minikube الحالي بيئة تجريبية بعقدة واحدة؛ مش Kubernetes cluster بين السيرفرين ولا يوفّر HA فعليًا.
- التشغيل الأساسي يبدأ بنسخة واحدة من خادم MyEduDrive وMariaDB/Redis نسخة واحدة لكل خدمة.
- HPA من 2 إلى 10 Pods موجود في overlay منفصل، ولا يتفعّل مع الـbase تلقائيًا.
- `ReadWriteOnce` مناسب لتجربة العقدة الواحدة. قبل توزيع Nextcloud على عقد متعددة، يلزم StorageClass يدعم `ReadWriteMany`، ونقل بيانات آمن إلى PVC جديدة. مجرد تغيير access mode لا يحوّل التخزين المحلي إلى shared storage.
- MariaDB وRedis هنا نسخة واحدة لكل منهما؛ ملفات المشروع لا تدّعي database/Redis HA أو replication.
- صورة التطبيق الموحدة تحمل علامة MyEduDrive على Docker Hub. الإصدار الحالي مبني على Nextcloud `35.0.1`؛ قاعدة البيانات والملفات ليست ضمن الصورة.

## المتطلبات

- Minikube يعمل مع Kubernetes context متاح لـ`kubectl`.
- StorageClass افتراضية provisioner شغالة.
- `kubectl` و`minikube` وBash.
- مساحة متاحة كافية للـPVCs: MariaDB ‏10Gi، Redis ‏2Gi، Nextcloud ‏20Gi. السعة الفعلية حسب provisioner.

## 1. تجهيز الأسرار

من هذا المجلد:

```bash
cp secrets.env.example secrets.env
openssl rand -hex 24
```

استخدم قيمًا عشوائية مختلفة لكلمات المرور في `secrets.env`، واحفظ الملف محليًا. `.gitignore` يستثنيه. احتفظ بهذه القيم لاستعادة قاعدة البيانات والإدارة؛ تغيّر كلمات المرور في Secret لا يبدّل كلمات المرور داخل قاعدة MariaDB بعد تهيئتها لأول مرة.

## 2. تشغيل Minikube ونشر الخدمات

ابنِ واختبر الصورة الموحدة محليًا ثم انشرها إلى Docker Hub حسب [دليل الصور والهوية](DOCKER_HUB_AND_BRANDING_AR.md). الوسم الحالي `v1.1.2` لمستودع `alan0o0s/myedudrive-server`؛ اجعله Public أو أضف `imagePullSecret`.

```bash
minikube start
kubectl config use-context minikube
./scripts/deploy.sh
```

السكربت ينشئ namespace وSecret ثم ينشر صورة Docker Hub، وينتظر جاهزية MariaDB وRedis وNextcloud. يحوّل NodePort الحالي إلى التطبيق الموحد ثم يزيل Deployment/ConfigMap الخاصين بـNGINX القديم فقط، وبعدها يطبّق الهوية ويعطّل `firstrunwizard`. لا يحذف PVC أو قاعدة البيانات.

لتجربة النسخة الموحدة على Docker محليًا في stack معزول عن Minikube:

```bash
PREVIEW_HTTP_PORT=8081 docker compose -p myedudrive-unified -f compose.preview.yaml up -d
```

افتح `http://127.0.0.1:8081`. هذا الأمر يستخدم قاعدة وبيانات Preview منفصلة.

## 3. فتح MyEduDrive محليًا

```bash
minikube ip
```

أضف عنوان الـIP الظاهر كـtrusted domain في Nextcloud بعد النشر وقبل التصفح:

```bash
kubectl -n myedudrive exec deployment/nextcloud -- php occ config:system:set trusted_domains 1 --value="$(minikube ip)"
```

ثم افتح:

```text
http://<MINIKUBE-IP>:30080
```

الجذر يعرض صفحة البداية. زر الدخول يفتح `/login`، مع بقاء `:30080` في العنوان. خدمة NodePort الحالية تحتفظ باسم Kubernetes التاريخي `myedudrive-nginx` للتوافق، لكنها توجّه مباشرة إلى Pod التطبيق؛ لا يوجد NGINX application container في التصميم الموحد.

بيانات admin هي `NEXTCLOUD_ADMIN_USER` و`NEXTCLOUD_ADMIN_PASSWORD` من `secrets.env`. هذا الإعداد يجهز التثبيت تلقائيًا باستخدام MariaDB وRedis؛ لو قاعدة البيانات أو Nextcloud مهيأة مسبقًا، لن تعيد متغيرات البداية إنشاءها أو تهيئتها من جديد. إعداد trusted proxy وTLS/domain خارجي يضاف فقط عند تحديد عنوان proxy الفعلي في cluster النهائي.

## 4. فحوصات التشغيل

```bash
./scripts/verify.sh
```

التحقق يشمل حالة الموارد والـPVC، MariaDB healthcheck، Redis `PING`، و`php occ status`. لا يمسح الفحوص أي بيانات. لاختبار حفظ Nextcloud عمليًا ارفع ملفًا صغيرًا من الواجهة، أعد تشغيل Nextcloud Pod، ثم تأكد أن الملف ما زال موجودًا.

## 5. تفعيل HPA الاختياري

المتطلبات: Metrics Server يعمل (`kubectl top pods -n myedudrive` يعرض بيانات)، وNextcloud اجتاز فحوص التشغيل، وسعة الجهاز تتحمل الزيادة. في Minikube يمكن تفعيل Metrics Server مثلًا:

```bash
minikube addons enable metrics-server
kubectl top pods -n myedudrive
./scripts/enable-scaling.sh
./scripts/hpa-smoke.sh
kubectl -n myedudrive get hpa nextcloud --watch
```

الحد الأدنى للـHPA هو 2 والحد الأقصى 10، وهدف CPU هو 70% من request البالغ 250m. سكربت `hpa-smoke.sh` يضيف حمل CPU مؤقتًا داخل كل Nextcloud Pod، ينتظر حتى تصبح 10 Pods جاهزة، ثم يوقف الحمل تلقائيًا حتى لو أوقفته بـCtrl+C. بعد توقف الحمل، يظل HPA على العدد الحالي حتى تنتهي مهلة خفض التوسع البالغة 300 ثانية. الحد الأقصى سقف وليس وعدًا؛ يحتاج CPU ضغطًا فعليًا وموارد كافية. راقب RAM/CPU على Server 1 أثناء الاختبار. `ReadWriteOnce` يسمح بأكثر من Pod على **العقدة نفسها**، لكنه لا يشارك البيانات بين عقد مختلفة.

## الملفات

- `k8s/base/`: الموارد الأساسية، نسخة واحدة من الخدمات، وتخزين RWO.
- `k8s/overlays/scaling/`: HPA اختياري 2–10.
- `k8s/overlays/dockerhub/`: يختار صور MyEduDrive الموجودة في حساب Docker Hub.
- `images/nextcloud/`: Dockerfile للصورة الموحدة، إعداد Apache، hook أول تثبيت، والثيم وسكربت ضبط الهوية.
- `landing/`: صفحة البداية وأصولها التي تُضمّن داخل صورة التطبيق.
- `scripts/build-images.sh`: بناء صورة MyEduDrive واحدة بإصدار المحرك المطابق للـPVC.
- `DOCKER_HUB_AND_BRANDING_AR.md`: خطوات البناء والنشر وتشغيل الهوية.
- `BRANDING_AUDIT_AR.md`: سجل تصنيف الاسم التجاري والمعرفات التقنية الباقية.
- `scripts/deploy.sh`: إنشاء Secret ونشر صور الحساب وضبط الثيم الرسمي.
- `scripts/verify.sh`: فحوص تشغيل غير مدمرة.
- `scripts/enable-scaling.sh`: إضافة HPA بعد نشر الأساس.
- `scripts/hpa-smoke.sh`: اختبار ارتفاع HPA إلى 10 مع إيقاف حمل CPU تلقائيًا.
- `secrets.env.example`: أسماء القيم المطلوبة فقط.

## إيقاف المختبر

```bash
minikube stop
```

لا تحذف PVCs إذا كانت البيانات مهمة. `kubectl delete -k k8s/base` لا يُستخدم كتنظيف اعتيادي؛ حذف PVC أو StatefulSet قد يؤدي إلى فقد البيانات حسب سياسة التخزين.

## تجهيز Server 2 لاحقًا

الخطوة القادمة ليست تشغيل Minikube مستقل على Server 2 وتسمية ذلك HA. عند وصوله، نقرر cluster واحدًا مناسبًا (مثل k3s أو kubeadm)، ونختار StorageClass مشتركة/موزعة، ونخطط backup ثم نقل البيانات. بعدها نضيف توزيع Pods بين nodes وHA مدروسة لقاعدة البيانات وRedis، ونراجع الوصول الخارجي وTLS. ملفات هذه المرحلة منظمة لتكون نقطة بداية، لكنها ليست تحويلة تلقائية إلى cluster متعدد العقد.

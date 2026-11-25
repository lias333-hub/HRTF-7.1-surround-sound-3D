# Directional Audio — MANIFEST (الهوية الثابتة للمشروع)

> **ما هذا الملف:** الوصف الثابت نسبياً للمشروع: ما هو، كيف هو مبني، كيف نبني ونختبر، وما الذي اتفقنا عليه. يتغير فقط عندما تتغير البنية أو القرارات أو طريقة العمل.
> **الملفات الشقيقة:** `CHECKPOINT.md` (أين وصلنا الآن وماذا بعد) · `NOTEBOOK.md` (الدفتر الزمني الكامل) · `IDEAS_REGISTRY.md` (سجل الأفكار وحكمنا على كل فكرة) · `EXPERIMENTS.md` (سجل التجارب: فرضية → قراءة من السجل → قرار).
> **آخر تحديث:** 2026-11-25 · **الإصدار:** v0.4.1 (build 6) · **HEAD (كود) وقت الكتابة:** `175399e` (قد يتقدم بـcommits توثيق فقط)
> **قاعدة التحديث:** يُحدَّث هذا الملف عند أي تغيير في البنية أو القرارات أو الأدوات، ويُذكر التغيير في سطر بقسم «سجل تغييرات المانيفست» أسفله.

---

## 1. الهوية والهدف

- **الاسم:** Directional Audio.
- **الهدف (بكلمات صاحب المشروع):** تطبيق يجعل **أي سماعة Stereo** تعطي صوتاً محيطياً دقيقاً وقريباً من Surround 7.1، بإضافة **HRTF**.
- **المنصة:** أندرويد. واجهة Flutter (Dart) + طبقة أصلية Kotlin، ونواة DSP بـ C++ لاحقاً.
- **المستودع:** `https://github.com/lias333-hub/hrtf-7.1-surround-sound-3d` (عام Public). الفرع الرئيسي `main`. الإصدار الحالي v0.4.1 (آخر commit للكود `175399e`).
- **اسم الحزمة:** `com.directionalaudio.directional_audio` · اسم مشروع Flutter: `directional_audio`.
- **لغة المستخدم:** العربية (لهجة لبنانية). يريد ردوداً مختصرة وعملية، ونقاشاً عميقاً عندما يطلبه أو عندما تُطرح أفكار جديدة.
- **المشروع في claude.ai:** Project باسم «Directional Audio». فيه مستند `claude/ideas-registry.md` ونسخ من هذه الملفات (بما فيها `claude/EXPERIMENTS.md`).

## 2. قرارات ثابتة (أكدها صاحب المشروع)

1. **التطبيق غير مربوط بهاتف بعينه.** التصميم حسب **القدرات (capability-based)** وليس حسب الموديل. الهواتف عنده للاختبار فقط.
2. **المحرك يشمل كل المسارات:** تقنيات حديثة حيث يسمح الهاتف، وبدائل (fallbacks) للهواتف القديمة، كي يخسر المستخدم أقل ما يمكن من الميزات.
3. **خمس لغات للواجهة:** العربية `ar`، الإنجليزية `en`، الفرنسية `fr`، الإسبانية `es`، التركية `tr` + خيار «لغة النظام».
4. **الأساس أولاً:** EQ، الملفات (profiles)، استيراد/تصدير GraphicEQ، قبل الميزات المتقدمة.
5. **من محادثته مع Gemini:** وضع داكن + ثيمات + Dynamic Color (أندرويد 12+)؛ إدارة حالة بأسلوب Provider مع تخزين محلي؛ واجهة بأسلوب Wavelet (مفتاح رئيسي، منحنى EQ، ملفات) مع تبويبات إضافية للمكاني/HRTF؛ شريط حالة حي للخدمة (مع زر استثناء البطارية)؛ بلاطة Quick Settings لاحقاً؛ «بنك أفكار» يشمل الأفكار الصعبة وتُفلتر لاحقاً مع Claude/ChatGPT/Gemini.
6. **Root ليس شرطاً.** يعرف Shizuku/ADB ويريد تجنب Root. (طبقة اختيارية لاحقاً — انظر مقترحات لم تُؤكد في `CHECKPOINT.md`.)

## 3. اتفاقيات العمل مع صاحب المشروع

- **ملاحظاته = عصف ذهني مع شريك مبدع، وليست أوامر.** أناقش وأعترض وأقترح.
- **أناقش أفكار ChatGPT وGemini بعمق**، لا أكتفي بالبناء. (صحّحني عندما تجاوزتها في المرة الأولى.)
- **عند الشك أو عدم الفهم لفكرة:** أكتب **رسالة باسمي** (من Claude) يرسلها هو إلى Gemini أو غيره، بدل أن أخمّن.
- **أفصل الحقائق المثبتة عن الفرضيات**، وأقول بصراحة ما لم يُختبر.
- **تعليمات الـProject (2026-11-24):** أعمل باحتراف وكأن المشروع مشروعي وأريده الأفضل؛ **واقعية وصراحة دائمة بلا مجاملة حتى في الصغائر**؛ **أخبره دائماً قبل إنشاء ملف حفظ جديد** (مثل الأربعة الأولى) حين أرى حاجة له؛ **ما يهمه دائماً: جودة الصوت وسرعة التطبيق** (فلا يدخل أي شيء في مسار الصوت بلا قياس، ولا تسجيل داخل خيط الصوت).
- **التوثيق المستمر:** يطلب تحديث هذه الملفات باستمرار «ولا شيء بدون تسجيل» تحسباً لفتح محادثة جديدة. يُحدَّث `CHECKPOINT.md` و`NOTEBOOK.md` عند **كل** إنجاز أو قرار أو نتيجة اختبار أو خطأ، ويُدفع إلى `main` ويُنسخ إلى الـProject.
- الحساب مجاني (Claude free plan): لا مهام مجدولة ولا تحكم بمتصفح/حاسوب. شبكة Bash مغلقة عن تثبيت الحزم (لا pip/npm محلياً).

## 4. المعمارية

### 4.1 طبقات الوصول إلى الصوت (Tiers)

| الطبقة | الوصف | الحالة |
|---|---|---|
| **T1** | مؤثرات النظام على الخلط العام (session 0): Equalizer, BassBoost, Virtualizer, LoudnessEnhancer, DynamicsProcessing. يعمل بحسب الجهاز. | **منفذ v0.3/v0.4** (سماع DP على الجهاز الحقيقي لم يُتحقق) |
| **T2** | مؤثرات على جلسة تطبيق محدد (audio session id). | مخطط |
| **T3** | التقاط صوت التطبيقات AudioPlaybackCapture (**أندرويد 10+ — J7 (أندرويد 9) لا يدعمه**، موافقة MediaProjection، بعض التطبيقات تمنع الالتقاط). مشكلة «الصوت المضاعف» (الأصلي لا يُكتم) غير محسومة. | تجربة لاحقة |
| **T4** | مشغّل داخل التطبيق + نواة C++ بمعالجتنا الخاصة. **الوحيد الذي يضمن HRTF حقيقياً.** | مخطط (القلب المستقبلي) |
| **T5** | Shizuku / Root. اختياري، خارج الأساس. | مؤجل |

> الخدمة الأمامية (Foreground Service) **تُبقي العملية حية فقط**؛ ليست التقاطاً للصوت.

### 4.2 طبقات اللغات والتقنيات

- **Flutter/Dart:** الواجهة، الحالة، التخزين (`shared_preferences`)، الترجمة، التقارير.
- **Kotlin:** الجسر الأصلي (`MainActivity`)، مركز المحرك (`EngineHub`)، الخدمة (`EngineService`).
- **C++ (لاحقاً):** نواة DSP عند الحاجة (HRTF/convolution/limiter). **Oboe** فقط عندما يناسب المسار. **Rust** مؤجل.
- تفاصيل أخرى عن الطبقات في `IDEAS_REGISTRY.md` (مصدرها ملف ChatGPT).

### 4.3 EngineHub (Kotlin) — قلب v0.3

Singleton يملك كل المؤثرات الحية (وليس الـActivity)، فتستمر بعد إغلاق الشاشة.

- **المؤثرات:** `eq` (Equalizer النظام) · `dp` (DynamicsProcessing) · `bass` · `virt` · `loud`.
- **الحالة:** `eqKind` = `none|system|dynamics`، `eqEnabled`، `sysSession`، `sysLevels`، `dpCenters`، `dpGains`، `dpPreamp`، `fxActive`، خرائط `fxOn/fxVal`، `running`، `wanted`، `lastError`، `lastRebuildMs`.
- **الدوال العامة:** `init`, `markService`, `setWanted`, `status()`, `emit()` (EventChannel), `eqMap`, `systemEqMap`, `startSystem(session)`, `setSysLevels`, `startDynamics(centers)`, `probeDynamics()`, `setDpGains(gains, preamp)`, `setEqEnabled`, `stopEq`, `fxStart/fxSet/fxStop`, `rebuild()`, `restoreIfEmpty()`, `watchRoutes()`.
- **DynamicsProcessing:** `Config.Builder(variant, channels, preEq, bands, mbc, mbcBands, postEq, postBands, limiter)`. نستخدم **pre-EQ بـ10 نطاقات** (القطع عند المتوسط الهندسي بين المراكز، آخر نطاق 20000 Hz) + **limiter** (`Limiter(true,true,0,1f,60f,10f,-1f,0f)`). **MBC وpost-EQ غير مستخدمين.** الكسب مقيّد ±15 dB، وinput gain ±24.
- **مراقبة المخارج:** `AudioDeviceCallback` مع تأخير debounce **700 ms**، ويُتجاهل أول **1500 ms** بعد البدء؛ عند التغيير `rebuild()`.
- **الاستمرارية:** يحفظ حالة المحرك JSON في SharedPreferences (`engine_state`، المفاتيح `state` و`wanted`) ويستعيدها في الخدمة (`restoreIfEmpty()`).
- **ملاحظة Kotlin:** `JSONObject(HashMap)` لا يُبنى في Kotlin القديم لـFlutter 3.22؛ تُبنى كائنات JSON يدوياً بحلقة `put`.

**إضافات v0.4 في EngineHub:**
- **جدول مخرج ← ملف (`slots`)** يعيش هنا لا في Dart (الخدمة قد تعمل بلا واجهة). الخانة: `{key "type|name", type, name, profile, gains[10], preamp, levels[]}`. `levels` (مللي بل للمعادل System) يحسبها Dart (`deviceLevels`) ويعيد إرسالها (`resync`) بعد كل بدء للمحرك وبعد حفظ/حذف ملف.
- **حالة أخرى محفوظة في `engine_state`:** `profile` (آخر ملف طُبّق)، `locked`، `lastKey` (آخر مخرج أساسي)، `slots`. (`switchSeq` في الذاكرة فقط.)
- **`decideProfile()`:** يحسب المخرج الأساسي (`OutputRouting.primary`) ويبدّل الملف **فقط** عند تغيّر المفتاح، وبلا قفل، ووجود خانة (`OutputRouting.shouldSwitch`). **مخرج بلا خانة ← يبقى الملف الحالي.** `syncOutput()` (يستدعيه Dart بعد بدء المعادل) و`onRouteChange()` (بعد debounce الجهاز، ثم `retryNow()`).
- **Bypass:** `bypassReason()` = `create_failed` (فشل `rebuild`) أو `control_lost` (`hasControl()`/`OnControlStatusChangeListener`) بشرط أن المستخدم يريد المعالجة. **قاعدة العودة:** `scheduleRetry()` بتأخير 5 ثم 15 ثم 45 ث (`OutputRouting.retryDelay`) ثم الانتظار؛ وتُعاد من البداية عند تغيّر المخرج (`onRouteChange`) أو عودة التطبيق للواجهة (`retryIfBypassed` في `HomeShell`) أو زر «إعادة المحاولة». `stateListener` يخبر الخدمة لتغيير نص الإشعار.
- **تقييد:** كشف Bypass يغطي معادل EQ فقط؛ أخطاء Bass/Virtualizer/Loudness تُسجَّل في `lastError` ولا ترفع Bypass.

### 4.4 EngineService (Kotlin)

- `ACTION_STOP` = `com.directionalaudio.directional_audio.STOP_ENGINE`، القناة `"engine"`، رقم الإشعار `42`.
- `startForeground` بنوع `mediaPlayback` على API 29+. النصوص (العنوان/النص/زر الإيقاف) تأتي من Dart وتُخزَّن في prefs ليعمل بعد إعادة التشغيل.
- عند البدء: `stateListener` ثم `markService(true)` ثم `restoreIfEmpty()` ثم `watchRoutes()`. نص الإشعار يتبدل إلى نص Bypass (مُترجَم من Dart، مخزّن في prefs `n_bypass`) أثناء Bypass. زر الإيقاف يستدعي `setWanted(false)`. `START_STICKY`.

### 4.5 الجسر Flutter ↔ Kotlin

- **MethodChannel `directional/eq`:** `start, setLevels(+profile), dpProbe, dpStart, dpGains(+profile), setEnabled, stop, deviceInfo, fxStart, fxSet, fxStop, svcStart(+bypass), svcStop, status, notifStatus, notifRequest, batteryIgnored, batteryRequest, tone, toneStop` و**(v0.4)** `outAssign, outUnassign, outSync, lockSet, retry` و**(v0.4.1)** `logGet` (يعيد `{header, text}`)، `logClear`، `logAdd(tag,msg)`، و`retry` يقبل `reason` (`manual` / `app resume` / `output changed` / `restored after process restart`).
- **EventChannel `directional/status`:** يبث حالة المحرك من `EngineHub.emit()` إلى `EngineApi.stream()`. حقول الحالة (v0.4): `profile, switchSeq, locked, bypass, output{key,type,name}, assignments[]` إضافة للحقول السابقة؛ و`outSync` يضيف `switched`.
- **سجل الأحداث (v0.4.1):** وسوم: `proc` (بدء العملية/استعادة)، `svc`، `device` (إضافة/إزالة جهاز صوت)، `route` (المخرج الأساسي + القرار + قائمة المخارج)، `switch`، `profile`، `slot`، `lock`، `eq`، `fx`، `rebuild`، `control`، `bypass`، `retry`، `app`، `log`. **لا يُكتب شيء من مسار الصوت** (أحداث نادرة فقط) فلا أثر على السرعة؛ كتابة الملف على خيط خلفي واحد.
- **أخطاء:** الأخطاء تعود كـ `PlatformException('EQ_ERROR', …)`؛ فشل Dynamics الصريح يعود `DP_FAILED`.

### 4.6 صلاحيات AndroidManifest (`native/AndroidManifest.xml`)

`MODIFY_AUDIO_SETTINGS`، `FOREGROUND_SERVICE`، `FOREGROUND_SERVICE_MEDIA_PLAYBACK`، `POST_NOTIFICATIONS` (API 33+، طلب وقت التشغيل)، `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. الخدمة `.EngineService` بنوع `mediaPlayback`، `exported=false`.

### 4.7 معرّفات المؤثرات (UUIDs)

| المؤثر | UUID |
|---|---|
| Equalizer | `0bed4300-ddd6-11db-8f34-0002a5d5c51b` |
| BassBoost | `0634f220-ddd4-11db-a0fc-0002a5d5c51b` |
| Virtualizer | `37cc2c00-dddd-11db-8577-0002a5d5c51b` |
| LoudnessEnhancer | `fe3199be-aed0-413f-87bb-11260eb63cf1` |
| DynamicsProcessing | `7261676f-6d75-7369-6364-28e2fd3ac39e` |

(Virtualizer UUID صُحِّح بعد فحصه على المحاكي — انظر الدفتر.)

## 5. خريطة المستودع

```
lib/                      واجهة Flutter (≈3,000 سطر)
  main.dart               نقطة الدخول، الثيم، اللغة
  shell.dart              التنقل السفلي (EQ / Effects / Tools / Settings) + resumeIfWanted
  eq_screen.dart          شاشة EQ: 10 نطاقات، ملفات، منتقي النوع System/Dynamics/Auto، بطاقة المخرج والتعيين والقفل، شريط Bypass
  eq_model.dart           EqProfile، kBandFreqs (31.25…16000 Hz)، ±12 dB، ملفات builtin، استيراد/تصدير GraphicEQ
  effects_screen.dart     Bass / Virtualizer / Loudness
  tools_screen.dart       أدوات: اختبار القنوات (tone)، بطاقة المحرك، تقرير الجهاز
  engine.dart             EqEngine (apply/assign/resync), FxEngine, EngineApi, EngineStatus (+OutputRef/Assignment), ToneEngine, DeviceInfo
  engine_screen.dart      شاشة المحرك: مفتاح الخدمة + حالة حية (ملف/قفل/Bypass) + قائمة التعيينات + إشعارات + بطارية
  device_report.dart      تقرير القدرات (yes/no/needs N)
  device_info_screen.dart شاشة معلومات الجهاز مع التقرير القابل للنسخ
  settings_screen.dart / language_sheet.dart
  store.dart              تخزين SharedPreferences (user, working, selected, enabled, backend, lang, fx)
  strings.dart            L10n: جداول 5 لغات + fallback إنجليزي (≈ 900 سطر)
  app_info.dart           kAppVersion = '0.4.1'
  event_log_card.dart     بطاقة سجل الأحداث (عرض آخر 40 سطراً، نسخ الكل مع ترويسة الجهاز، تحديث، مسح)
native/                   ملفات Kotlin والـManifest (تُنسخ إلى android/ عند البناء)
  EngineHub.kt · EngineService.kt · MainActivity.kt · AndroidManifest.xml
  EventLog.kt             سجل أحداث دائري (300 سطر) بملف files/events.log يبقى بعد قتل العملية؛ بلا Android (اختُبر JUnit)؛ الكتابة على خيط خلفي
  OutputRouting.kt        منطق نقي بلا Android: أولوية المخرج، المفتاح، متى يُبدَّل الملف، جدول إعادة المحاولة
  test/OutputRoutingTest.kt (10) · test/EventLogTest.kt (7)   اختبارات JUnit (تُنسخ إلى android/app/src/test عند البناء)
test/                     7 ملفات اختبار Dart، 63 اختباراً كلها تنجح
ci/
  prepare_android.sh      يولّد android/ (غير مُلتزَم به) ويُسقط native/*.kt فوقه، وينسخ مفتاح التوقيع الثابت إلى ~/.android/debug.keystore
  check_signing.sh        يفشل إن لم يكن الـAPK موقّعاً بالمفتاح التجريبي الثابت (يُشغَّل في build.yml)
  test-signing/debug.keystore   مفتاح تجريبي **علني** (alias androiddebugkey، كلمة السر android) — للتجارب فقط، لا للنشر
  devshell/               صندوق البناء التفاعلي (client.sh, loop.sh, bin/emu, bin/dsync …)
.github/workflows/
  build.yml               CI على push إلى main: analyze + test + build APK
  dev-shell.yml           الصندوق التفاعلي على فرع dev-shell
docs/                     هذه الملفات (MANIFEST، CHECKPOINT، NOTEBOOK، IDEAS_REGISTRY، EXPERIMENTS)
pubspec.yaml              الاسم directional_audio، 0.4.1+6، تبعية وحيدة: shared_preferences ^2.2.3
```

> مجلد `android/` **غير موجود في المستودع**؛ يُولَّد في كل بناء بـ `ci/prepare_android.sh`.

## 6. البناء والاختبار والنشر

### 6.1 لا Flutter في بيئة Claude
البناء والاختبار يجريان على صندوق GitHub Actions («dev-shell») أو على CI.

### 6.2 Dev-shell
```
ci/devshell/client.sh start [branch]            يبدأ جلسة (يدفع فرع dev-shell) وينتظر الجاهزية
ci/devshell/client.sh run [-t secs] 'cmd'       ينفذ أمراً على الصندوق (مهلة افتراضية 900 ث)
ci/devshell/client.sh run [-t secs] -f file.sh  نفس الشيء من ملف
ci/devshell/client.sh wait <seq> [secs]         ينتظر نتيجة أمر ما زال يعمل
ci/devshell/client.sh art <seq> [dir]           ينزّل ما تركه الأمر في $DS_ART  (يهبط في <dir>/art/<000seq>/)
ci/devshell/client.sh status | stop
```
- يعمل عبر فرعي git `shell-in`/`shell-out`. **الصندوق يستنسخ فرعاً مدفوعاً**، لذا يجب عمل commit وpush أولاً.
- الصندوق يخمل ويُغلق بعد **720 ثانية**. انسخ الـAPK إلى `$DS_ART` (= `/tmp/ds-art`) **في نفس الأمر** ثم نزّله بـ `art`.
- متغير `DS_TRAILERS` يضيف أسطر trailers لرسائل commit التي ينشئها السكربت.
- **المستودع عام:** لا تضع أسراراً في أوامر dev-shell أبداً (الأوامر والمخرجات علنية).
- الأداة `emu` على الصندوق: `emu start 34` (محاكي أندرويد 14)، `install`, `launch`, `shot NAME`, `ui`, `tap X Y`, `tapt 'text'`, `key BACK`, `sh`, `crash`, `logclear`. أخطاء Kotlin تُقرأ من `/tmp/kotlin-daemon*.log`.
- **لتحديث الصندوق بآخر ما دُفع:** `git fetch -q origin main && git reset -q --hard origin/main` (`git pull` يفشل: «divergent branches»). JDK 17: `export JAVA_HOME=$JAVA_HOME_17_X64`.
- `emu`: `emu tapt 'System'` قد يضغط عنصراً خاطئاً (يطابق الوصف الكامل)؛ استعمل إحداثيات المنتقي. العناصر خارج الشاشة لا تظهر في `emu ui` فيلزم التمرير بـ`emu sh 'input swipe ...'`.
- Flutter **3.22.0** / Dart **3.4**. الزمن: بناء ≈ 20–135 ث. يلزم **JDK 17** لـGradle 7.x (الافتراضي على الصندوق JDK 25 ويفشل).

### 6.3 CI (`build.yml`)
يعمل على push إلى `main` (إلا إن احتوت الرسالة `[skip ci]`): JDK 17 + Flutter 3.22.0 → `prepare_android.sh` → `flutter analyze` → `flutter test` → **اختبارات Kotlin** (`cd android && ./gradlew :app:testDebugUnitTest`) → `flutter build apk --release` → **`ci/check_signing.sh`** (التحقق من بصمة المفتاح الثابت) → رفع الـAPK كـartifact. **حالياً كل الـcommits تحمل `[skip ci]`** والبناء يجري على dev-shell.

### 6.4 اصطلاح الـcommit
- نهاية الرسالة: `[skip ci]`.
- ثم السطران:
  ```
  Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01WnhsQLhoQH9u8qQj3g3MMd
  ```
- نص الـcommit بالإنجليزية.

### 6.5 تسليم الـAPK للمستخدم
يُبنى على dev-shell، يُنسخ إلى `$DS_ART`، يُنزَّل، ويُرسل عبر `SendUserFile`. اسم الملف: `directional-audio-vX.Y.Z.apk`.
- **التوقيع (منذ 0.4.1):** كل البناءات توقَّع بالمفتاح التجريبي الثابت، فتُثبَّت النسخ فوق بعضها. قبل 0.4.1 كان لكل صندوق مفتاح مختلف. **لا تُغيّر `ci/test-signing/debug.keystore`** وإلا انكسر التحديث على هاتف المستخدم. المفتاح علني؛ النشر الحقيقي بمفتاح سري لاحقاً.
- `emu launch` يحتاج اسم الحزمة: `emu launch com.directionalaudio.directional_audio`. لقتل العملية على المحاكي: `emu sh 'su 0 kill -9 $(pidof com.directionalaudio.directional_audio)'`.

## 7. اصطلاحات الكود

- **L10n:** الجداول الثابتة للغات الخمس، fallback إنجليزي. الاختبارات تفرض تطابق **المفاتيح** و**العناصر النائبة** `{x}` بين اللغات. في العربية تُكتب عزلات bidi كـ `⁦ … ⁩` (LTR isolate) حول الأرقام ونطاقات الترددات.
- **كل قراءة من التخزين دفاعية:** البيانات التالفة ترجع إلى الافتراضي.
- **الاختبارات تحاكي القنوات:** `directional/eq` (MethodChannel) و`directional/status` (قناة الطرق الخاصة بالـEventChannel).
- في الاختبارات: نافذة طويلة (tall viewport) لقائمة EQ الكسولة؛ `pump(500ms)` ثم `settle` بعد تأخير 400 ms في تشغيل الخدمة.
- Kotlin: اسم وسيط `catch` يجب ألا يكون `_`؛ `release()` يتعارض مع `FlutterActivity.release()` فسُمّي `releaseEq()`.

## 8. أجهزة الاختبار (للاختبار فقط، لا ارتباط)

| الجهاز | المواصفات | الحالة |
|---|---|---|
| Samsung Galaxy J7 Pro (SM-J730F) | أندرويد 9 (API 28)، **armeabi-v7a فقط (32-bit)**، مخرج 48000 Hz / 240 إطار، Equalizer النظام **5 نطاقات** ±15 dB، 23 مؤثراً منها Samsung SoundAlive+/MySpace/MySound/SoundBoosterPlus/VR360Audio وAOSP Dynamics Processing | الجهاز الرئيسي للاختبار |
| POCO C71 | أندرويد 15 Go (بحسب ملف ChatGPT) | تقرير الجهاز لم يصل بعد |
| محاكي أندرويد 14 (API 34) على dev-shell | لا يمكنه محاكاة توصيل سماعة | للتحقق من البناء والواجهة والخدمة |
| سماعة FX-03 (ألعاب، ≈ $8) | 3.5mm + USB-A، ستيريو، 40mm | سماعته الأساسية. يعدّلها بنفسه في Wavelet (Legacy FX) |

الأدوات الأخرى عنده: Samsung Sound Assistant (فيه خيار Dolby Atmos)، Wavelet. لاحظ تسرّباً بين القنوات (يعزو السبب للهاتف لا للسماعة).

## 9. المصادر الخارجية

- **ملف ChatGPT:** `AUDIO_ENGINE_MASTER_LOGNEW.md` (مُرفق من المستخدم). يتضمن طبقات البرمجة، خطة المسارات، مسار «الهندسة العكسية السلوكية» (DSP فقط، ليس هندسة شرائح).
- **محادثة Gemini:** 84 صفحة PDF (نسخة نظيفة محفوظة في scratchpad الجلسة السابقة). سجل Gemini النهائي أسقط عدة أفكار وردت في المحادثة (موسومة «مسقطة من سجل Gemini» في السجل). Gemini اعترف بأن سياقه لا يتضمن الـPDF كاملاً.

## 10. مصطلحات

- **HRTF:** Head-Related Transfer Function — دوال تحاكي كيف تعدّل الرأس والأذن الصوت حسب الاتجاه.
- **DP:** DynamicsProcessing (API 28+).
- **MBC:** Multiband Compressor داخل DP.
- **Tier / T1…T5:** طبقة الوصول إلى الصوت (القسم 4.1).
- **Session 0:** الخلط العام للنظام (مؤثرات تُطبَّق على كل الصوت إن سمح الجهاز).
- **Golden vectors:** متجهات مرجعية تُقارن بها نواة C++ خارج الجهاز.
- **Bypass:** تجاوز المعالجة (حماية عند فشل الـDSP).
- **EngineParams / AudioSource:** عقد مقترح بين طبقة التحكم والنواة (انظر السجل والـCHECKPOINT).

## 11. سجل تغييرات المانيفست

- 2026-11-21: إنشاء الملف (v0.3.0).
- 2026-11-24: تحديث لـv0.4.0 (OutputRouting، جدول المخرجات، Bypass، قنوات جديدة، اختبارات Kotlin في CI، ملاحظات الصندوق).
- 2026-11-25: تحديث لـv0.4.1 (التوقيع الثابت، EventLog، قنوات `logGet/logClear/logAdd` و`retry(reason)`، `EXPERIMENTS.md`).

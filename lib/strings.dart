/// Minimal Arabic/English strings (no code generation).
class L10n {
  static String lang = 'ar';
  static bool get rtl => lang == 'ar';

  static String t(String key) => _m[lang]?[key] ?? _m['en']![key] ?? key;

  /// Display name of a profile key (built-ins are translated, user names are shown as typed).
  static String profileName(String key) =>
      key.startsWith('builtin:') ? t(key.substring(8)) : key;

  static const Map<String, Map<String, String>> _m = {
    'ar': {
      'app_title': 'Directional Audio',
      'effect_on': 'تفعيل المعادِل على كل التطبيقات',
      'tip_global':
          'يعمل كمؤثر عام على الجهاز. قد لا يعمل على بعض الأجهزة، وللحفاظ عليه أبقِ التطبيق مفتوحاً.',
      'bands_info': 'نطاقات الجهاز: {n} · أقصى تعديل {r} ديسيبل',
      'note_bands':
          'الواجهة بـ 10 نطاقات، لكن الجهاز يطبّقها على نطاقاته الفعلية فقط (غالباً 5).',
      'profile': 'البروفايل',
      'save_as': 'حفظ باسم',
      'delete': 'حذف',
      'reset': 'تصفير',
      'import': 'استيراد',
      'export': 'تصدير',
      'preamp': 'التضخيم المسبق',
      'name': 'الاسم',
      'cancel': 'إلغاء',
      'save': 'حفظ',
      'paste': 'لصق',
      'import_title': 'استيراد GraphicEQ',
      'import_hint': 'الصق نص GraphicEQ (من AutoEq أو Wavelet)',
      'import_ok': 'تم الاستيراد وتحويله إلى 10 نطاقات. احفظه باسم إن أردت.',
      'import_bad': 'تعذّر قراءة النص: لا توجد نقاط تردد/ديسيبل صالحة.',
      'copied': 'نُسخ GraphicEQ إلى الحافظة',
      'flat': 'مسطّح',
      'bass': 'تعزيز الباص',
      'vocal': 'وضوح الأصوات',
      'treble': 'تعزيز الحدّة',
      'soft': 'تخفيف الحدّة',
    },
    'en': {
      'app_title': 'Directional Audio',
      'effect_on': 'Enable equalizer for all apps',
      'tip_global':
          'Runs as a global device effect. It may not work on some devices; keep the app open to keep it active.',
      'bands_info': 'Device bands: {n} · range ±{r} dB',
      'note_bands':
          'The UI has 10 bands, but the device applies them to its real bands only (often 5).',
      'profile': 'Profile',
      'save_as': 'Save as',
      'delete': 'Delete',
      'reset': 'Reset',
      'import': 'Import',
      'export': 'Export',
      'preamp': 'Preamp',
      'name': 'Name',
      'cancel': 'Cancel',
      'save': 'Save',
      'paste': 'Paste',
      'import_title': 'Import GraphicEQ',
      'import_hint': 'Paste GraphicEQ text (from AutoEq or Wavelet)',
      'import_ok': 'Imported and resampled to 10 bands. Save it under a name if you like.',
      'import_bad': 'Could not read the text: no valid frequency/gain points found.',
      'copied': 'GraphicEQ copied to clipboard',
      'flat': 'Flat',
      'bass': 'Bass boost',
      'vocal': 'Vocal clarity',
      'treble': 'Treble boost',
      'soft': 'Softer highs',
    },
  };
}

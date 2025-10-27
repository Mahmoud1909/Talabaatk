// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get home => 'الرئيسية';

  @override
  String get orders => 'الطلبات';

  @override
  String get previousOrders => 'الطلبات السابقة';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get noRestaurantFound => 'لم يتم العثور على مطعم لهذا الحساب.';

  @override
  String get failedToLoadRestaurant =>
      'فشل تحميل بيانات المطعم. حاول مرة أخرى.';

  @override
  String get accountInfo => 'معلومات الحساب';

  @override
  String get save => 'حفظ';

  @override
  String get edit => 'تعديل';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get firstName => 'الاسم الأول';

  @override
  String get lastName => 'اسم العائلة';

  @override
  String phone(Object phone) {
    return 'الهاتف: $phone';
  }

  @override
  String get birthday => 'تاريخ الميلاد';

  @override
  String get genderOptional => 'النوع (اختياري)';

  @override
  String get male => 'ذكر';

  @override
  String get female => 'أنثى';

  @override
  String get deleteAccount => 'حذف الحساب';

  @override
  String get deleteAccountTitle => 'حذف الحساب';

  @override
  String get deleteAccountMessage =>
      'هل أنت متأكد أنك تريد حذف الحساب؟ هذا الإجراء لا يمكن التراجع عنه.';

  @override
  String get cancel => 'إلغاء';

  @override
  String get delete => 'حذف';

  @override
  String get profileSaved => 'تم حفظ البيانات ✅';

  @override
  String get failedToSave => 'فشل الحفظ';

  @override
  String get failedToDelete => 'فشل الحذف';

  @override
  String get requiresRecentLogin =>
      'الرجاء تسجيل الدخول مرة أخرى قبل حذف الحساب.';

  @override
  String get requiredField => 'مطلوب';

  @override
  String get items => 'العناصر';

  @override
  String get noAddress => 'لا يوجد عنوان';

  @override
  String deliveryWithDriver(Object driver) {
    return 'التوصيل مع: $driver';
  }

  @override
  String get deliveryNotAssigned => 'التوصيل: لم يتم تعيين سائق بعد';

  @override
  String get comment => 'ملاحظات';

  @override
  String get deliveredMessage => 'تم تسليم هذا الطلب بنجاح';

  @override
  String get noOrdersTitle => 'لا توجد طلبات مُسلَّمة بعد';

  @override
  String get noOrdersSubtitle =>
      'لم تصل أي طلبات مُسلَّمة حتى الآن. عندما يتم تسليم طلب سيظهر هنا تلقائياً.';

  @override
  String get go => 'اذهب';

  @override
  String get yourCart => 'سلة مشترياتك';

  @override
  String get syncing => 'جاري المزامنة';

  @override
  String get emptyCart => 'سلتك فارغة 😊';

  @override
  String failedToUpdateQty(Object error) {
    return 'فشل تحديث الكمية: $error';
  }

  @override
  String failedToRemoveItem(Object error) {
    return 'فشل إزالة المنتج: $error';
  }

  @override
  String failedToClearCart(Object error) {
    return 'فشل مسح السلة: $error';
  }

  @override
  String failedToNavigatePayment(Object error) {
    return 'فشل الانتقال إلى الدفع: $error';
  }

  @override
  String get restaurant => 'المطعم';

  @override
  String get clear => 'مسح';

  @override
  String get checkout => 'الدفع';

  @override
  String currency(Object amount) {
    return '$amount ج.م';
  }

  @override
  String get allRestaurants => 'كل المطاعم';

  @override
  String results(Object count) {
    return '$count نتيجة';
  }

  @override
  String get noRestaurantsCategory => 'لا يوجد مطاعم في هذا التصنيف.';

  @override
  String get noRestaurantsFilter => 'لا يوجد مطاعم مطابقة لهذا الفلتر حالياً.';

  @override
  String get sortAToZ => 'من الألف للياء';

  @override
  String get sortFastDelivery => 'توصيل سريع';

  @override
  String get sortUnder45 => 'أقل من ٤٥ دقيقة';

  @override
  String get sortCloser => 'الأقرب للموقع';

  @override
  String mins(Object value) {
    return '$value دقيقة';
  }

  @override
  String prepRange(Object max, Object min) {
    return '$min - $max دقيقة';
  }

  @override
  String get deliveryFree => 'مجاناً';

  @override
  String deliveryFee(Object amount) {
    return '$amount جنيه';
  }

  @override
  String distance(Object km) {
    return '$km كم';
  }

  @override
  String errorMessage(Object error) {
    return 'خطأ: $error';
  }

  @override
  String get checkout_title => 'الدفع';

  @override
  String get delivery_location => 'موقع التوصيل';

  @override
  String get choose_address => 'اضغط على الخريطة لاختيار عنوان التوصيل';

  @override
  String get change => 'تغيير';

  @override
  String get pay_with => 'ادفع بواسطة:';

  @override
  String get please_accept_terms => 'من فضلك وافق على الشروط قبل المتابعة.';

  @override
  String get enter_valid_phone => 'من فضلك أدخل رقم هاتف مكون من 11 رقمًا';

  @override
  String get no_nearby_restaurant => 'لا يوجد مطعم قريب.';

  @override
  String get could_not_determine_restaurant =>
      'تعذر تحديد المطعم لإتمام الطلب.';

  @override
  String get order_success => 'تم إرسال الطلب بنجاح! 🎉';

  @override
  String get order_failed => 'فشل في إرسال الطلب. حاول مرة أخرى.';

  @override
  String get checkout_failed => 'فشل الدفع:';

  @override
  String get error_loading_categories => 'حدث خطأ أثناء تحميل الفئات:';

  @override
  String get no_categories => 'لا توجد فئات بعد';

  @override
  String get error_loading_restaurants => 'حدث خطأ أثناء تحميل المطاعم:';

  @override
  String get no_nearby_restaurants => 'لا توجد مطاعم قريبة';

  @override
  String get big_brands => 'الماركات الكبيرة';

  @override
  String get big_brands_near_you => 'الماركات الكبيرة بالقرب منك';

  @override
  String big_brands_category(Object category) {
    return 'الماركات الكبيرة — $category';
  }

  @override
  String get item_title => 'المنتج';

  @override
  String get error_loading_item => 'خطأ:';

  @override
  String get please_sign_in => 'يرجى تسجيل الدخول لإضافة عناصر إلى السلة';

  @override
  String get adding_to_cart => 'جارٍ الإضافة إلى السلة...';

  @override
  String get added_to_cart => 'تمت الإضافة إلى السلة';

  @override
  String failed_to_add(Object error) {
    return 'فشل في الإضافة إلى السلة: $error';
  }

  @override
  String get choose_option => 'اختر خيارًا';

  @override
  String get option => 'خيار';

  @override
  String add_it(Object price) {
    return 'أضف — $price';
  }

  @override
  String get address => 'العنوان';

  @override
  String get latitude => 'خط العرض';

  @override
  String get longitude => 'خط الطول';

  @override
  String get pleasePickLocation => 'من فضلك اختر موقعًا أولاً';

  @override
  String get useThisLocation => 'استخدم هذا الموقع';

  @override
  String get tapEatSmile => 'اضغط - كُل - ابتسم';

  @override
  String get tapEatSmileSubtitle => 'وجباتك المفضلة على بُعد ضغطة واحدة';

  @override
  String get flavorInFlash => 'الطعم بسرعة البرق';

  @override
  String get flavorInFlashSubtitle => 'ساخن، طازج، وسريع إلى بابك';

  @override
  String get foodYourWay => 'طعامك بطريقتك';

  @override
  String get foodYourWaySubtitle => 'اطلب بالضبط ما تحبه';

  @override
  String get enterYourEmail => 'أدخل بريدك الإلكتروني';

  @override
  String get enterOtpCode => 'أدخل رمز التحقق';

  @override
  String get signInQuicklyWithGoogle => 'سجّل دخولك بسرعة باستخدام جوجل';

  @override
  String get next => 'التالي';

  @override
  String get google => 'جوجل';

  @override
  String get signInFailed => 'فشل تسجيل الدخول';

  @override
  String get googleSignInFailed => 'فشل تسجيل الدخول بجوجل';

  @override
  String get failedToLoadOrders => 'فشل تحميل الطلبات';

  @override
  String get close => 'إغلاق';

  @override
  String get contact => 'تواصل';

  @override
  String get failedToUpdateStatus => 'فشل في تحديث الحالة.';

  @override
  String get noOrdersYet => 'لا توجد طلبات بعد';

  @override
  String get noOrdersDescription =>
      'يبدو أنك لم تقم بأي طلب حتى الآن. ابدأ في استكشاف المطاعم واطلب وجبتك المفضلة!';

  @override
  String get cart => 'السلة';

  @override
  String get noItemsInCart => 'لا توجد عناصر في السلة لهذا المطعم';

  @override
  String get anyComments => 'أي ملاحظات:';

  @override
  String get addCommentsHint => 'يمكنك إضافة أي ملاحظات هنا';

  @override
  String get doYouHaveDiscountCode => 'هل لديك كود خصم؟';

  @override
  String get enterYourCode => 'أدخل الكود';

  @override
  String get submit => 'تطبيق';

  @override
  String get applied => 'تم التطبيق';

  @override
  String get off => 'خصم';

  @override
  String couponApplied(Object label) {
    return 'تم تطبيق الكوبون: $label';
  }

  @override
  String get couponRemoved => 'تم إزالة الكوبون';

  @override
  String get deliveryAddress => 'عنوان التوصيل';

  @override
  String get usingDeviceLocation =>
      'يتم استخدام موقع جهازك (أو القاهرة إذا لم يتوفر)';

  @override
  String get paymentSummary => 'ملخص الدفع';

  @override
  String get calculating => 'جاري الحساب';

  @override
  String get subtotal => 'الإجمالي الفرعي';

  @override
  String get discount => 'الخصم';

  @override
  String get removePromo => 'إزالة الكوبون';

  @override
  String get total => 'الإجمالي';

  @override
  String get addItems => 'إضافة عناصر';

  @override
  String get pleaseEnterPromo => 'من فضلك أدخل كود الخصم';

  @override
  String get couponAlreadyApplied => 'تم تطبيق هذا الكوبون بالفعل';

  @override
  String get onlyOneCoupon => 'يمكنك استخدام كوبون واحد فقط في الطلب';

  @override
  String get couponNotFound => 'الكوبون غير موجود';

  @override
  String get couponInactive => 'الكوبون غير مفعل';

  @override
  String get couponNotValidYet => 'الكوبون غير صالح بعد';

  @override
  String get couponExpired => 'انتهت صلاحية الكوبون';

  @override
  String get couponFullyUsed => 'تم استهلاك الكوبون بالكامل';

  @override
  String couponMinOrder(Object amount) {
    return 'الحد الأدنى للطلب لهذا الكوبون هو $amount جنيه';
  }

  @override
  String get couponHasNoValue => 'الكوبون لا يحتوي على قيمة خصم';

  @override
  String get couponFailed => 'فشل تطبيق الكوبون';

  @override
  String get noAddressSelected => 'لم يتم اختيار عنوان';

  @override
  String get no_items => 'لا توجد عناصر';

  @override
  String get other => 'أخرى';

  @override
  String get free => 'مجانًا';

  @override
  String get minutes => 'دقيقة';

  @override
  String get delivery_fee => 'رسوم التوصيل';

  @override
  String get prep_time => 'وقت التحضير';

  @override
  String get search => 'بحث';

  @override
  String get banner => 'إعلان';

  @override
  String get ads_load_error => 'فشل تحميل الإعلانات';

  @override
  String minutes_range(Object max, Object min) {
    return '$min - $max دقيقة';
  }

  @override
  String get km_unit => 'كم';

  @override
  String get guest => 'ضيف';

  @override
  String get settings => 'الإعدادات';

  @override
  String get password => 'كلمة المرور';

  @override
  String get changePassword => 'تغيير كلمة المرور';

  @override
  String get savedAddresses => 'العناوين المحفوظة';

  @override
  String get changeEmail => 'تغيير البريد الإلكتروني';

  @override
  String get notifications => 'الإشعارات';

  @override
  String get languages => 'اللغات';

  @override
  String get country => 'البلد';

  @override
  String get logOut => 'تسجيل الخروج';

  @override
  String get selectLanguage => 'اختر لغتك';

  @override
  String get arabic => 'العربية';

  @override
  String get english => 'الإنجليزية';

  @override
  String get logoutConfirmTitle => 'تسجيل الخروج';

  @override
  String get logoutConfirmMessage => 'هل أنت متأكد أنك تريد تسجيل الخروج؟';

  @override
  String get manageNotificationsMessage =>
      'لإدارة إشعارات التطبيق، افتح إعدادات جهازك الخاصة بتطبيق طلبك.';

  @override
  String get openSettings => 'الإعدادات';

  @override
  String get no => 'لا';

  @override
  String get yes => 'نعم';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get saved => 'تم الحفظ';

  @override
  String get payment_summary => 'ملخص الدفع';

  @override
  String get any_comments => 'ملاحظاتك';

  @override
  String get do_you_have_discount => 'هل لديك كود خصم؟';

  @override
  String get enter_your_code => 'ادخل الكود';

  @override
  String get delivery_address => 'عنوان التوصيل';

  @override
  String get add_items => 'إضافة عناصر';

  @override
  String get searchPlaceHint => 'ابحث عن عنوان أو مكان';

  @override
  String get locationPermissionPermanentlyDenied =>
      'تم رفض إذن الموقع نهائيًا. فعّل الإذن من إعدادات التطبيق.';

  @override
  String get closed => 'مغلق';

  @override
  String get open => 'مفتوح';

  @override
  String get errorUpdate => 'فشل التحديث!';

  @override
  String get imageUploaded => 'تم رفع الصورة بنجاح';

  @override
  String get noPrepTime => 'لا يوجد وقت تحضير';

  @override
  String get noRestaurantsFound => 'لا توجد مطاعم';

  @override
  String restaurantTypesLoadedCount(Object count) {
    return 'تم تحميل $count نوع مطاعم';
  }

  @override
  String get uploadingImage => 'جاري رفع الصورة...';

  @override
  String get loading => 'جاري التحميل...';

  @override
  String get refresh => 'تحديث';

  @override
  String get restaurantTypes => 'أنواع المطاعم';

  @override
  String get savingLanguage => 'جاري حفظ اللغة...';

  @override
  String get languageSaved => 'تم حفظ اللغة بنجاح';

  @override
  String get languageSavedLocalFailed => 'فشل في حفظ اللغة محليًا';

  @override
  String get onboardingTapEatSmile => 'اضغط، كل، ابتسم';

  @override
  String get onboardingTapEatSmileSubtitle => 'اطلب أكلك في ثوانٍ';

  @override
  String get onboardingFlavorInAFlash => 'النكهة في لمح البصر';

  @override
  String get onboardingFlavorInAFlashSubtitle => 'وجباتك توصلك بسرعة';

  @override
  String get onboardingFoodYourWay => 'أكلك بطريقتك';

  @override
  String get onboardingFoodYourWaySubtitle => 'خصص طلبك واستمتع';

  @override
  String get details => 'التفاصيل';

  @override
  String get seeAll => 'عرض الكل';

  @override
  String get hotOffers => 'عروض مميزة';

  @override
  String get darkMode => 'الوضع الداكن';

  @override
  String get system => 'افتراضي النظام';

  @override
  String get loadingOrders => 'جاري تحميل الطلبات...';

  @override
  String get assignedDriver => 'تم تعيين سائق';

  @override
  String get notAssigned => 'لم يتم التعيين بعد';

  @override
  String get currencySymbol => 'ج.م';

  @override
  String get sweetBoxTitle => 'الحلو: تم التوصيل 🍰';

  @override
  String get sweetBoxBody => 'كل شيء سار على ما يرام — بالهناء والشفاء!';

  @override
  String get bitterBoxTitle => 'الوحش: مشكلة ⚠️';

  @override
  String get bitterBoxBody => 'حدثت مشكلة في هذا الطلب. نحن نعمل على حلها.';

  @override
  String get qtyUpdated => 'تم تحديث الكمية';

  @override
  String get itemRemoved => 'تم حذف العنصر من السلة';

  @override
  String get cartCleared => 'تم إفراغ السلة بنجاح';

  @override
  String get errorLoadingRestaurants =>
      'فشل تحميل المطاعم. من فضلك حاول مرة أخرى.';

  @override
  String get errorLoadingRestaurantsDescription =>
      'حدث خطأ أثناء تحميل المطاعم.';

  @override
  String get terms_title => 'الشروط والأحكام';

  @override
  String get terms_paragraph1 => 'الفقرة 1: الرجاء القراءة بعناية.';

  @override
  String get terms_paragraph2 => 'الفقرة 2: سياسات التوصيل.';

  @override
  String get terms_paragraph3 => 'الفقرة 3: الدفع والاسترجاع.';

  @override
  String get terms_paragraph4 => 'الفقرة 4: مسؤوليات المستخدم.';

  @override
  String get thank_you => 'شكرًا لاستخدامك خدمتنا!';

  @override
  String get dark_mode_on => 'تم تفعيل الوضع الداكن';

  @override
  String get light_mode_on => 'تم تفعيل الوضع الفاتح';

  @override
  String get dark => 'داكن';

  @override
  String get light => 'فاتح';

  @override
  String get fixed_delivery_price_applied => 'تم تطبيق سعر التوصيل الثابت.';

  @override
  String get searching => 'جارٍ البحث...';

  @override
  String get error => 'حدث خطأ، حاول مرة أخرى.';

  @override
  String get noResults => 'لا توجد نتائج';

  @override
  String get restaurantLabel => 'مطعم';

  @override
  String get searchHint => 'ابحث عن مطاعم أو وجبات أو عروض';

  @override
  String get searchNewHint => 'ابحث عن مطاعم';

  @override
  String get categoriesLabel => 'التصنيفات';

  @override
  String get search_hint => 'ابحث...';

  @override
  String get no_results => 'لا توجد نتائج';

  @override
  String get categories => 'الفئات';

  @override
  String get done => 'تم';

  @override
  String get no_network_short => 'لا يوجد اتصال بالانترنت';

  @override
  String get somethingWentWrong => 'حدث خطأ ما';

  @override
  String get dismiss => 'إغلاق';

  @override
  String get privacyPolicy => 'سياسة خصوصية Talabaatk';

  @override
  String get termsOfUse => 'شروط استخدام Talabaatk';

  @override
  String get deleteAccountDesc => 'حذف حسابك نهائيًا وكل البيانات المرتبطة به.';

  @override
  String get deleteConfirmTitle => 'حذف الحساب؟';

  @override
  String get deleteConfirmMessage =>
      'سيتم حذف حسابك وكل البيانات المرتبطة به نهائيًا. لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get deletingAccount => 'جاري حذف الحساب...';

  @override
  String get deleteSuccess => 'تم حذف الحساب بنجاح';

  @override
  String get deletePartialSuccess =>
      'تم حذف بيانات الحساب لكن سجل التسجيل لا يزال موجودًا (مطلوب إعادة توثيق).';

  @override
  String get deleteFailed => 'فشل حذف الحساب — حاول مرة أخرى';

  @override
  String get reauthRequired =>
      'يرجى إعادة تسجيل الدخول للتأكد قبل حذف الحساب (لأسباب أمنية).';
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get home => 'Home';

  @override
  String get orders => 'Orders';

  @override
  String get previousOrders => 'Previous Orders';

  @override
  String get retry => 'Retry';

  @override
  String get noRestaurantFound => 'No restaurant found for this account.';

  @override
  String get failedToLoadRestaurant =>
      'Failed to load restaurant info. Please try again.';

  @override
  String get accountInfo => 'Account info';

  @override
  String get save => 'Save';

  @override
  String get edit => 'Edit';

  @override
  String get email => 'Email';

  @override
  String get firstName => 'First Name';

  @override
  String get lastName => 'Last Name';

  @override
  String phone(Object phone) {
    return 'Phone: $phone';
  }

  @override
  String get birthday => 'Date of birthday';

  @override
  String get genderOptional => 'Gender (optional)';

  @override
  String get male => 'Male';

  @override
  String get female => 'Female';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountTitle => 'Delete Account';

  @override
  String get deleteAccountMessage =>
      'Are you sure you want to delete your account? This action cannot be undone.';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get profileSaved => 'Profile saved ✅';

  @override
  String get failedToSave => 'Failed to save';

  @override
  String get failedToDelete => 'Failed to delete';

  @override
  String get requiresRecentLogin =>
      'Please sign in again before deleting your account.';

  @override
  String get requiredField => 'Required';

  @override
  String get items => 'Items';

  @override
  String get noAddress => 'No address provided';

  @override
  String deliveryWithDriver(Object driver) {
    return 'Delivery with driver: $driver';
  }

  @override
  String get deliveryNotAssigned => 'Delivery: Not assigned yet';

  @override
  String get comment => 'Comment';

  @override
  String get deliveredMessage => 'This order was delivered successfully';

  @override
  String get noOrdersTitle => 'No delivered orders yet';

  @override
  String get noOrdersSubtitle =>
      'You don\'t have any delivered orders yet. When an order is delivered it\'ll appear here automatically.';

  @override
  String get go => 'Go';

  @override
  String get yourCart => 'Your Cart';

  @override
  String get syncing => 'Syncing';

  @override
  String get emptyCart => 'Your cart is empty 😊';

  @override
  String failedToUpdateQty(Object error) {
    return 'Failed to update qty: $error';
  }

  @override
  String failedToRemoveItem(Object error) {
    return 'Failed to remove item: $error';
  }

  @override
  String failedToClearCart(Object error) {
    return 'Failed to clear cart: $error';
  }

  @override
  String failedToNavigatePayment(Object error) {
    return 'Failed to navigate to payment: $error';
  }

  @override
  String get restaurant => 'Restaurant';

  @override
  String get clear => 'Clear';

  @override
  String get checkout => 'Checkout';

  @override
  String currency(Object amount) {
    return '$amount EGP';
  }

  @override
  String get allRestaurants => 'All restaurants';

  @override
  String results(Object count) {
    return '$count results';
  }

  @override
  String get noRestaurantsCategory => 'No restaurants found in this category.';

  @override
  String get noRestaurantsFilter =>
      'No restaurants currently match this filter.';

  @override
  String get sortAToZ => 'A to Z';

  @override
  String get sortFastDelivery => 'Fast delivery';

  @override
  String get sortUnder45 => 'Under 45 mins';

  @override
  String get sortCloser => 'Closer to site';

  @override
  String mins(Object value) {
    return '$value mins';
  }

  @override
  String prepRange(Object max, Object min) {
    return '$min - $max mins';
  }

  @override
  String get deliveryFree => 'Free';

  @override
  String deliveryFee(Object amount) {
    return '$amount EGP';
  }

  @override
  String distance(Object km) {
    return '$km km';
  }

  @override
  String errorMessage(Object error) {
    return 'Error: $error';
  }

  @override
  String get checkout_title => 'Checkout';

  @override
  String get delivery_location => 'Delivery location';

  @override
  String get choose_address => 'Tap the map to choose delivery address';

  @override
  String get change => 'Change';

  @override
  String get pay_with => 'Pay with:';

  @override
  String get please_accept_terms =>
      'Please accept the terms before continuing.';

  @override
  String get enter_valid_phone => 'Please enter an 11-digit phone number';

  @override
  String get no_nearby_restaurant => 'No nearby restaurant found.';

  @override
  String get could_not_determine_restaurant =>
      'Could not determine restaurant for checkout.';

  @override
  String get order_success => 'Order placed successfully! 🎉';

  @override
  String get order_failed => 'Failed to place order. Please try again.';

  @override
  String get checkout_failed => 'Checkout failed:';

  @override
  String get error_loading_categories => 'Error loading categories:';

  @override
  String get no_categories => 'No categories yet';

  @override
  String get error_loading_restaurants => 'Error loading restaurants:';

  @override
  String get no_nearby_restaurants => 'No nearby restaurants';

  @override
  String get big_brands => 'Big Brands';

  @override
  String get big_brands_near_you => 'Big Brands Near You';

  @override
  String big_brands_category(Object category) {
    return 'Big Brands — $category';
  }

  @override
  String get item_title => 'Item';

  @override
  String get error_loading_item => 'Error:';

  @override
  String get please_sign_in => 'Please sign in to add items to cart';

  @override
  String get adding_to_cart => 'Adding to cart...';

  @override
  String get added_to_cart => 'Added to cart';

  @override
  String failed_to_add(Object error) {
    return 'Failed to add to cart: $error';
  }

  @override
  String get choose_option => 'Choose option';

  @override
  String get option => 'Option';

  @override
  String add_it(Object price) {
    return 'Add it — $price';
  }

  @override
  String get address => 'Address';

  @override
  String get latitude => 'Latitude';

  @override
  String get longitude => 'Longitude';

  @override
  String get pleasePickLocation => 'Please pick a location first';

  @override
  String get useThisLocation => 'Use this location';

  @override
  String get tapEatSmile => 'Tap - Eat - Smile';

  @override
  String get tapEatSmileSubtitle => 'Your favorite meals, just a tap away';

  @override
  String get flavorInFlash => 'Flavor in a Flash';

  @override
  String get flavorInFlashSubtitle => 'Hot, fresh, and fast to your door';

  @override
  String get foodYourWay => 'Food, Your Way';

  @override
  String get foodYourWaySubtitle => 'Order exactly what you love';

  @override
  String get enterYourEmail => 'Enter your email';

  @override
  String get enterOtpCode => 'Enter OTP Code';

  @override
  String get signInQuicklyWithGoogle => 'Sign in quickly with Google';

  @override
  String get next => 'Next';

  @override
  String get google => 'Google';

  @override
  String get signInFailed => 'Sign in failed';

  @override
  String get googleSignInFailed => 'Google sign-in failed';

  @override
  String get failedToLoadOrders => 'Failed to load orders';

  @override
  String get close => 'Close';

  @override
  String get contact => 'Contact';

  @override
  String get failedToUpdateStatus => 'Failed to update status.';

  @override
  String get noOrdersYet => 'No orders yet';

  @override
  String get noOrdersDescription =>
      'Looks like you haven\'t placed any orders yet. Start exploring restaurants and order your favorite meal!';

  @override
  String get cart => 'Cart';

  @override
  String get noItemsInCart => 'No items in the cart for this restaurant';

  @override
  String get anyComments => 'Any comments:';

  @override
  String get addCommentsHint => 'You can add any comments here';

  @override
  String get doYouHaveDiscountCode => 'Do you have a discount code?';

  @override
  String get enterYourCode => 'Enter your code';

  @override
  String get submit => 'Submit';

  @override
  String get applied => 'Applied';

  @override
  String get off => 'off';

  @override
  String couponApplied(Object label) {
    return 'Coupon applied: $label';
  }

  @override
  String get couponRemoved => 'Coupon removed';

  @override
  String get deliveryAddress => 'Delivery address';

  @override
  String get usingDeviceLocation =>
      'Using your device location (or Cairo if unavailable)';

  @override
  String get paymentSummary => 'Payment summary';

  @override
  String get calculating => 'Calculating';

  @override
  String get subtotal => 'Subtotal';

  @override
  String get discount => 'Discount';

  @override
  String get removePromo => 'Remove promo';

  @override
  String get total => 'Total';

  @override
  String get addItems => 'Add items';

  @override
  String get pleaseEnterPromo => 'Please enter a promo code';

  @override
  String get couponAlreadyApplied => 'This coupon is already applied';

  @override
  String get onlyOneCoupon => 'You can only use one coupon per order';

  @override
  String get couponNotFound => 'Coupon not found';

  @override
  String get couponInactive => 'Coupon is not active';

  @override
  String get couponNotValidYet => 'Coupon not valid yet';

  @override
  String get couponExpired => 'Coupon expired';

  @override
  String get couponFullyUsed => 'Coupon fully used';

  @override
  String couponMinOrder(Object amount) {
    return 'Minimum order for this coupon is $amount EGP';
  }

  @override
  String get couponHasNoValue => 'Coupon has no discount value';

  @override
  String get couponFailed => 'Failed to apply coupon';

  @override
  String get noAddressSelected => 'No address selected';

  @override
  String get no_items => 'No items';

  @override
  String get other => 'Other';

  @override
  String get free => 'Free';

  @override
  String get minutes => 'mins';

  @override
  String get delivery_fee => 'Delivery Fee';

  @override
  String get prep_time => 'Preparation Time';

  @override
  String get search => 'Search';

  @override
  String get banner => 'Banner';

  @override
  String get ads_load_error => 'Failed to load ads';

  @override
  String minutes_range(Object max, Object min) {
    return '$min - $max mins';
  }

  @override
  String get km_unit => 'km';

  @override
  String get guest => 'Guest';

  @override
  String get settings => 'Settings';

  @override
  String get password => 'Password';

  @override
  String get changePassword => 'Change password';

  @override
  String get savedAddresses => 'Saved addresses';

  @override
  String get changeEmail => 'Change email';

  @override
  String get notifications => 'Notifications';

  @override
  String get languages => 'Languages';

  @override
  String get country => 'Country';

  @override
  String get logOut => 'Log Out';

  @override
  String get selectLanguage => 'Select your language';

  @override
  String get arabic => 'Arabic';

  @override
  String get english => 'English';

  @override
  String get logoutConfirmTitle => 'Log Out';

  @override
  String get logoutConfirmMessage => 'Are you sure you want to log out?';

  @override
  String get manageNotificationsMessage =>
      'To manage your application notifications, please open your device settings for Talabak.';

  @override
  String get openSettings => 'Settings';

  @override
  String get no => 'No';

  @override
  String get yes => 'Yes';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get saved => 'Saved';

  @override
  String get payment_summary => 'Payment summary';

  @override
  String get any_comments => 'Any comments';

  @override
  String get do_you_have_discount => 'Do you have a discount code?';

  @override
  String get enter_your_code => 'Enter your code';

  @override
  String get delivery_address => 'Delivery address';

  @override
  String get add_items => 'Add items';

  @override
  String get searchPlaceHint => 'Search address or place';

  @override
  String get locationPermissionPermanentlyDenied =>
      'Location permission permanently denied. Enable in settings.';

  @override
  String get closed => 'Closed';

  @override
  String get open => 'Open';

  @override
  String get errorUpdate => 'Update failed!';

  @override
  String get imageUploaded => 'Image uploaded successfully';

  @override
  String get noPrepTime => 'No preparation time';

  @override
  String get noRestaurantsFound => 'No restaurants found';

  @override
  String restaurantTypesLoadedCount(Object count) {
    return 'Loaded $count restaurant types';
  }

  @override
  String get uploadingImage => 'Uploading image...';

  @override
  String get loading => 'Loading...';

  @override
  String get refresh => 'Refresh';

  @override
  String get restaurantTypes => 'Restaurant Types';

  @override
  String get savingLanguage => 'Saving language...';

  @override
  String get languageSaved => 'Language saved successfully';

  @override
  String get languageSavedLocalFailed => 'Failed to save language locally';

  @override
  String get onboardingTapEatSmile => 'Tap, Eat, Smile';

  @override
  String get onboardingTapEatSmileSubtitle => 'Order food with just a few taps';

  @override
  String get onboardingFlavorInAFlash => 'Flavor in a Flash';

  @override
  String get onboardingFlavorInAFlashSubtitle =>
      'Get your meals delivered fast';

  @override
  String get onboardingFoodYourWay => 'Food Your Way';

  @override
  String get onboardingFoodYourWaySubtitle => 'Customize and enjoy your orders';

  @override
  String get details => 'Details';

  @override
  String get seeAll => 'See all';

  @override
  String get hotOffers => 'Hot Offers';

  @override
  String get darkMode => 'Dark Mode';

  @override
  String get system => 'System Default';

  @override
  String get loadingOrders => 'Loading orders...';

  @override
  String get assignedDriver => 'Assigned driver';

  @override
  String get notAssigned => 'Not assigned yet';

  @override
  String get currencySymbol => 'EGP';

  @override
  String get sweetBoxTitle => 'Sweet: Order Complete 🍰';

  @override
  String get sweetBoxBody => 'Everything went smoothly — enjoy your meal!';

  @override
  String get bitterBoxTitle => 'Bitter: Issue Found ⚠️';

  @override
  String get bitterBoxBody =>
      'There was a problem with this order. We\'re working on it.';

  @override
  String get qtyUpdated => 'Quantity updated';

  @override
  String get itemRemoved => 'Item removed from cart';

  @override
  String get cartCleared => 'Cart cleared successfully';

  @override
  String get errorLoadingRestaurants =>
      'Failed to load restaurants. Please try again.';

  @override
  String get errorLoadingRestaurantsDescription =>
      'An error occurred while loading restaurants.';

  @override
  String get terms_title => 'Terms and Conditions';

  @override
  String get terms_paragraph1 => 'Paragraph 1: Please read carefully.';

  @override
  String get terms_paragraph2 => 'Paragraph 2: Delivery policies.';

  @override
  String get terms_paragraph3 => 'Paragraph 3: Payment and refund.';

  @override
  String get terms_paragraph4 => 'Paragraph 4: User responsibilities.';

  @override
  String get thank_you => 'Thank you for using our service!';

  @override
  String get dark_mode_on => 'Dark mode is ON';

  @override
  String get light_mode_on => 'Light mode is ON';

  @override
  String get dark => 'Dark';

  @override
  String get light => 'Light';

  @override
  String get fixed_delivery_price_applied =>
      'Fixed delivery price has been applied.';

  @override
  String get searching => 'Searching...';

  @override
  String get error => 'An error occurred. Please try again.';

  @override
  String get noResults => 'No results found';

  @override
  String get restaurantLabel => 'Restaurant';

  @override
  String get searchHint => 'Search for restaurants, meals, or offers';

  @override
  String get searchNewHint => 'Search for restaurants';

  @override
  String get categoriesLabel => 'Categories';

  @override
  String get search_hint => 'Search...';

  @override
  String get no_results => 'No results found';

  @override
  String get categories => 'Categories';

  @override
  String get done => 'Done';

  @override
  String get no_network_short => 'No internet connection';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get privacyPolicy => 'Talabaatk Privacy Policy';

  @override
  String get termsOfUse => 'Talabaatk Terms of Use';

  @override
  String get deleteAccountDesc =>
      'Permanently delete your account and all your data.';

  @override
  String get deleteConfirmTitle => 'Delete account?';

  @override
  String get deleteConfirmMessage =>
      'This will permanently remove your account and all associated data. This action cannot be undone.';

  @override
  String get deletingAccount => 'Deleting account...';

  @override
  String get deleteSuccess => 'Account deleted successfully';

  @override
  String get deletePartialSuccess =>
      'Account data removed, but authentication record remains (re-auth needed).';

  @override
  String get deleteFailed => 'Failed to delete account — please try again';

  @override
  String get reauthRequired =>
      'Please re-authenticate to delete your account (for security reasons).';
}

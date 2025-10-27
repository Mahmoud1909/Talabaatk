import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ar'),
  ];

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @orders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get orders;

  /// No description provided for @previousOrders.
  ///
  /// In en, this message translates to:
  /// **'Previous Orders'**
  String get previousOrders;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @noRestaurantFound.
  ///
  /// In en, this message translates to:
  /// **'No restaurant found for this account.'**
  String get noRestaurantFound;

  /// No description provided for @failedToLoadRestaurant.
  ///
  /// In en, this message translates to:
  /// **'Failed to load restaurant info. Please try again.'**
  String get failedToLoadRestaurant;

  /// No description provided for @accountInfo.
  ///
  /// In en, this message translates to:
  /// **'Account info'**
  String get accountInfo;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First Name'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last Name'**
  String get lastName;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone: {phone}'**
  String phone(Object phone);

  /// No description provided for @birthday.
  ///
  /// In en, this message translates to:
  /// **'Date of birthday'**
  String get birthday;

  /// No description provided for @genderOptional.
  ///
  /// In en, this message translates to:
  /// **'Gender (optional)'**
  String get genderOptional;

  /// No description provided for @male.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get male;

  /// No description provided for @female.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get female;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete your account? This action cannot be undone.'**
  String get deleteAccountMessage;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @profileSaved.
  ///
  /// In en, this message translates to:
  /// **'Profile saved ✅'**
  String get profileSaved;

  /// No description provided for @failedToSave.
  ///
  /// In en, this message translates to:
  /// **'Failed to save'**
  String get failedToSave;

  /// No description provided for @failedToDelete.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete'**
  String get failedToDelete;

  /// No description provided for @requiresRecentLogin.
  ///
  /// In en, this message translates to:
  /// **'Please sign in again before deleting your account.'**
  String get requiresRecentLogin;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get items;

  /// No description provided for @noAddress.
  ///
  /// In en, this message translates to:
  /// **'No address provided'**
  String get noAddress;

  /// No description provided for @deliveryWithDriver.
  ///
  /// In en, this message translates to:
  /// **'Delivery with driver: {driver}'**
  String deliveryWithDriver(Object driver);

  /// No description provided for @deliveryNotAssigned.
  ///
  /// In en, this message translates to:
  /// **'Delivery: Not assigned yet'**
  String get deliveryNotAssigned;

  /// No description provided for @comment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get comment;

  /// No description provided for @deliveredMessage.
  ///
  /// In en, this message translates to:
  /// **'This order was delivered successfully'**
  String get deliveredMessage;

  /// No description provided for @noOrdersTitle.
  ///
  /// In en, this message translates to:
  /// **'No delivered orders yet'**
  String get noOrdersTitle;

  /// No description provided for @noOrdersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have any delivered orders yet. When an order is delivered it\'ll appear here automatically.'**
  String get noOrdersSubtitle;

  /// No description provided for @go.
  ///
  /// In en, this message translates to:
  /// **'Go'**
  String get go;

  /// No description provided for @yourCart.
  ///
  /// In en, this message translates to:
  /// **'Your Cart'**
  String get yourCart;

  /// No description provided for @syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing'**
  String get syncing;

  /// No description provided for @emptyCart.
  ///
  /// In en, this message translates to:
  /// **'Your cart is empty 😊'**
  String get emptyCart;

  /// No description provided for @failedToUpdateQty.
  ///
  /// In en, this message translates to:
  /// **'Failed to update qty: {error}'**
  String failedToUpdateQty(Object error);

  /// No description provided for @failedToRemoveItem.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove item: {error}'**
  String failedToRemoveItem(Object error);

  /// No description provided for @failedToClearCart.
  ///
  /// In en, this message translates to:
  /// **'Failed to clear cart: {error}'**
  String failedToClearCart(Object error);

  /// No description provided for @failedToNavigatePayment.
  ///
  /// In en, this message translates to:
  /// **'Failed to navigate to payment: {error}'**
  String failedToNavigatePayment(Object error);

  /// No description provided for @restaurant.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get restaurant;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @checkout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkout;

  /// No description provided for @currency.
  ///
  /// In en, this message translates to:
  /// **'{amount} EGP'**
  String currency(Object amount);

  /// No description provided for @allRestaurants.
  ///
  /// In en, this message translates to:
  /// **'All restaurants'**
  String get allRestaurants;

  /// No description provided for @results.
  ///
  /// In en, this message translates to:
  /// **'{count} results'**
  String results(Object count);

  /// No description provided for @noRestaurantsCategory.
  ///
  /// In en, this message translates to:
  /// **'No restaurants found in this category.'**
  String get noRestaurantsCategory;

  /// No description provided for @noRestaurantsFilter.
  ///
  /// In en, this message translates to:
  /// **'No restaurants currently match this filter.'**
  String get noRestaurantsFilter;

  /// No description provided for @sortAToZ.
  ///
  /// In en, this message translates to:
  /// **'A to Z'**
  String get sortAToZ;

  /// No description provided for @sortFastDelivery.
  ///
  /// In en, this message translates to:
  /// **'Fast delivery'**
  String get sortFastDelivery;

  /// No description provided for @sortUnder45.
  ///
  /// In en, this message translates to:
  /// **'Under 45 mins'**
  String get sortUnder45;

  /// No description provided for @sortCloser.
  ///
  /// In en, this message translates to:
  /// **'Closer to site'**
  String get sortCloser;

  /// No description provided for @mins.
  ///
  /// In en, this message translates to:
  /// **'{value} mins'**
  String mins(Object value);

  /// No description provided for @prepRange.
  ///
  /// In en, this message translates to:
  /// **'{min} - {max} mins'**
  String prepRange(Object max, Object min);

  /// No description provided for @deliveryFree.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get deliveryFree;

  /// No description provided for @deliveryFee.
  ///
  /// In en, this message translates to:
  /// **'{amount} EGP'**
  String deliveryFee(Object amount);

  /// No description provided for @distance.
  ///
  /// In en, this message translates to:
  /// **'{km} km'**
  String distance(Object km);

  /// No description provided for @errorMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorMessage(Object error);

  /// No description provided for @checkout_title.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkout_title;

  /// No description provided for @delivery_location.
  ///
  /// In en, this message translates to:
  /// **'Delivery location'**
  String get delivery_location;

  /// No description provided for @choose_address.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to choose delivery address'**
  String get choose_address;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @pay_with.
  ///
  /// In en, this message translates to:
  /// **'Pay with:'**
  String get pay_with;

  /// No description provided for @please_accept_terms.
  ///
  /// In en, this message translates to:
  /// **'Please accept the terms before continuing.'**
  String get please_accept_terms;

  /// No description provided for @enter_valid_phone.
  ///
  /// In en, this message translates to:
  /// **'Please enter an 11-digit phone number'**
  String get enter_valid_phone;

  /// No description provided for @no_nearby_restaurant.
  ///
  /// In en, this message translates to:
  /// **'No nearby restaurant found.'**
  String get no_nearby_restaurant;

  /// No description provided for @could_not_determine_restaurant.
  ///
  /// In en, this message translates to:
  /// **'Could not determine restaurant for checkout.'**
  String get could_not_determine_restaurant;

  /// No description provided for @order_success.
  ///
  /// In en, this message translates to:
  /// **'Order placed successfully! 🎉'**
  String get order_success;

  /// No description provided for @order_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to place order. Please try again.'**
  String get order_failed;

  /// No description provided for @checkout_failed.
  ///
  /// In en, this message translates to:
  /// **'Checkout failed:'**
  String get checkout_failed;

  /// No description provided for @error_loading_categories.
  ///
  /// In en, this message translates to:
  /// **'Error loading categories:'**
  String get error_loading_categories;

  /// No description provided for @no_categories.
  ///
  /// In en, this message translates to:
  /// **'No categories yet'**
  String get no_categories;

  /// No description provided for @error_loading_restaurants.
  ///
  /// In en, this message translates to:
  /// **'Error loading restaurants:'**
  String get error_loading_restaurants;

  /// No description provided for @no_nearby_restaurants.
  ///
  /// In en, this message translates to:
  /// **'No nearby restaurants'**
  String get no_nearby_restaurants;

  /// No description provided for @big_brands.
  ///
  /// In en, this message translates to:
  /// **'Big Brands'**
  String get big_brands;

  /// No description provided for @big_brands_near_you.
  ///
  /// In en, this message translates to:
  /// **'Big Brands Near You'**
  String get big_brands_near_you;

  /// No description provided for @big_brands_category.
  ///
  /// In en, this message translates to:
  /// **'Big Brands — {category}'**
  String big_brands_category(Object category);

  /// No description provided for @item_title.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get item_title;

  /// No description provided for @error_loading_item.
  ///
  /// In en, this message translates to:
  /// **'Error:'**
  String get error_loading_item;

  /// No description provided for @please_sign_in.
  ///
  /// In en, this message translates to:
  /// **'Please sign in to add items to cart'**
  String get please_sign_in;

  /// No description provided for @adding_to_cart.
  ///
  /// In en, this message translates to:
  /// **'Adding to cart...'**
  String get adding_to_cart;

  /// No description provided for @added_to_cart.
  ///
  /// In en, this message translates to:
  /// **'Added to cart'**
  String get added_to_cart;

  /// No description provided for @failed_to_add.
  ///
  /// In en, this message translates to:
  /// **'Failed to add to cart: {error}'**
  String failed_to_add(Object error);

  /// No description provided for @choose_option.
  ///
  /// In en, this message translates to:
  /// **'Choose option'**
  String get choose_option;

  /// No description provided for @option.
  ///
  /// In en, this message translates to:
  /// **'Option'**
  String get option;

  /// No description provided for @add_it.
  ///
  /// In en, this message translates to:
  /// **'Add it — {price}'**
  String add_it(Object price);

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @latitude.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get latitude;

  /// No description provided for @longitude.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get longitude;

  /// No description provided for @pleasePickLocation.
  ///
  /// In en, this message translates to:
  /// **'Please pick a location first'**
  String get pleasePickLocation;

  /// No description provided for @useThisLocation.
  ///
  /// In en, this message translates to:
  /// **'Use this location'**
  String get useThisLocation;

  /// No description provided for @tapEatSmile.
  ///
  /// In en, this message translates to:
  /// **'Tap - Eat - Smile'**
  String get tapEatSmile;

  /// No description provided for @tapEatSmileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your favorite meals, just a tap away'**
  String get tapEatSmileSubtitle;

  /// No description provided for @flavorInFlash.
  ///
  /// In en, this message translates to:
  /// **'Flavor in a Flash'**
  String get flavorInFlash;

  /// No description provided for @flavorInFlashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hot, fresh, and fast to your door'**
  String get flavorInFlashSubtitle;

  /// No description provided for @foodYourWay.
  ///
  /// In en, this message translates to:
  /// **'Food, Your Way'**
  String get foodYourWay;

  /// No description provided for @foodYourWaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Order exactly what you love'**
  String get foodYourWaySubtitle;

  /// No description provided for @enterYourEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get enterYourEmail;

  /// No description provided for @enterOtpCode.
  ///
  /// In en, this message translates to:
  /// **'Enter OTP Code'**
  String get enterOtpCode;

  /// No description provided for @signInQuicklyWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Sign in quickly with Google'**
  String get signInQuicklyWithGoogle;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @google.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get google;

  /// No description provided for @signInFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign in failed'**
  String get signInFailed;

  /// No description provided for @googleSignInFailed.
  ///
  /// In en, this message translates to:
  /// **'Google sign-in failed'**
  String get googleSignInFailed;

  /// No description provided for @failedToLoadOrders.
  ///
  /// In en, this message translates to:
  /// **'Failed to load orders'**
  String get failedToLoadOrders;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @failedToUpdateStatus.
  ///
  /// In en, this message translates to:
  /// **'Failed to update status.'**
  String get failedToUpdateStatus;

  /// No description provided for @noOrdersYet.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get noOrdersYet;

  /// No description provided for @noOrdersDescription.
  ///
  /// In en, this message translates to:
  /// **'Looks like you haven\'t placed any orders yet. Start exploring restaurants and order your favorite meal!'**
  String get noOrdersDescription;

  /// No description provided for @cart.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get cart;

  /// No description provided for @noItemsInCart.
  ///
  /// In en, this message translates to:
  /// **'No items in the cart for this restaurant'**
  String get noItemsInCart;

  /// No description provided for @anyComments.
  ///
  /// In en, this message translates to:
  /// **'Any comments:'**
  String get anyComments;

  /// No description provided for @addCommentsHint.
  ///
  /// In en, this message translates to:
  /// **'You can add any comments here'**
  String get addCommentsHint;

  /// No description provided for @doYouHaveDiscountCode.
  ///
  /// In en, this message translates to:
  /// **'Do you have a discount code?'**
  String get doYouHaveDiscountCode;

  /// No description provided for @enterYourCode.
  ///
  /// In en, this message translates to:
  /// **'Enter your code'**
  String get enterYourCode;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @applied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get applied;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'off'**
  String get off;

  /// No description provided for @couponApplied.
  ///
  /// In en, this message translates to:
  /// **'Coupon applied: {label}'**
  String couponApplied(Object label);

  /// No description provided for @couponRemoved.
  ///
  /// In en, this message translates to:
  /// **'Coupon removed'**
  String get couponRemoved;

  /// No description provided for @deliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Delivery address'**
  String get deliveryAddress;

  /// No description provided for @usingDeviceLocation.
  ///
  /// In en, this message translates to:
  /// **'Using your device location (or Cairo if unavailable)'**
  String get usingDeviceLocation;

  /// No description provided for @paymentSummary.
  ///
  /// In en, this message translates to:
  /// **'Payment summary'**
  String get paymentSummary;

  /// No description provided for @calculating.
  ///
  /// In en, this message translates to:
  /// **'Calculating'**
  String get calculating;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @discount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// No description provided for @removePromo.
  ///
  /// In en, this message translates to:
  /// **'Remove promo'**
  String get removePromo;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @addItems.
  ///
  /// In en, this message translates to:
  /// **'Add items'**
  String get addItems;

  /// No description provided for @pleaseEnterPromo.
  ///
  /// In en, this message translates to:
  /// **'Please enter a promo code'**
  String get pleaseEnterPromo;

  /// No description provided for @couponAlreadyApplied.
  ///
  /// In en, this message translates to:
  /// **'This coupon is already applied'**
  String get couponAlreadyApplied;

  /// No description provided for @onlyOneCoupon.
  ///
  /// In en, this message translates to:
  /// **'You can only use one coupon per order'**
  String get onlyOneCoupon;

  /// No description provided for @couponNotFound.
  ///
  /// In en, this message translates to:
  /// **'Coupon not found'**
  String get couponNotFound;

  /// No description provided for @couponInactive.
  ///
  /// In en, this message translates to:
  /// **'Coupon is not active'**
  String get couponInactive;

  /// No description provided for @couponNotValidYet.
  ///
  /// In en, this message translates to:
  /// **'Coupon not valid yet'**
  String get couponNotValidYet;

  /// No description provided for @couponExpired.
  ///
  /// In en, this message translates to:
  /// **'Coupon expired'**
  String get couponExpired;

  /// No description provided for @couponFullyUsed.
  ///
  /// In en, this message translates to:
  /// **'Coupon fully used'**
  String get couponFullyUsed;

  /// No description provided for @couponMinOrder.
  ///
  /// In en, this message translates to:
  /// **'Minimum order for this coupon is {amount} EGP'**
  String couponMinOrder(Object amount);

  /// No description provided for @couponHasNoValue.
  ///
  /// In en, this message translates to:
  /// **'Coupon has no discount value'**
  String get couponHasNoValue;

  /// No description provided for @couponFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply coupon'**
  String get couponFailed;

  /// No description provided for @noAddressSelected.
  ///
  /// In en, this message translates to:
  /// **'No address selected'**
  String get noAddressSelected;

  /// No description provided for @no_items.
  ///
  /// In en, this message translates to:
  /// **'No items'**
  String get no_items;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @free.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get free;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'mins'**
  String get minutes;

  /// No description provided for @delivery_fee.
  ///
  /// In en, this message translates to:
  /// **'Delivery Fee'**
  String get delivery_fee;

  /// No description provided for @prep_time.
  ///
  /// In en, this message translates to:
  /// **'Preparation Time'**
  String get prep_time;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @banner.
  ///
  /// In en, this message translates to:
  /// **'Banner'**
  String get banner;

  /// No description provided for @ads_load_error.
  ///
  /// In en, this message translates to:
  /// **'Failed to load ads'**
  String get ads_load_error;

  /// No description provided for @minutes_range.
  ///
  /// In en, this message translates to:
  /// **'{min} - {max} mins'**
  String minutes_range(Object max, Object min);

  /// No description provided for @km_unit.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get km_unit;

  /// No description provided for @guest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get guest;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get changePassword;

  /// No description provided for @savedAddresses.
  ///
  /// In en, this message translates to:
  /// **'Saved addresses'**
  String get savedAddresses;

  /// No description provided for @changeEmail.
  ///
  /// In en, this message translates to:
  /// **'Change email'**
  String get changeEmail;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @languages.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get languages;

  /// No description provided for @country.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get country;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logOut;

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select your language'**
  String get selectLanguage;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @logoutConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logoutConfirmTitle;

  /// No description provided for @logoutConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get logoutConfirmMessage;

  /// No description provided for @manageNotificationsMessage.
  ///
  /// In en, this message translates to:
  /// **'To manage your application notifications, please open your device settings for Talabak.'**
  String get manageNotificationsMessage;

  /// No description provided for @openSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get openSettings;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @payment_summary.
  ///
  /// In en, this message translates to:
  /// **'Payment summary'**
  String get payment_summary;

  /// No description provided for @any_comments.
  ///
  /// In en, this message translates to:
  /// **'Any comments'**
  String get any_comments;

  /// No description provided for @do_you_have_discount.
  ///
  /// In en, this message translates to:
  /// **'Do you have a discount code?'**
  String get do_you_have_discount;

  /// No description provided for @enter_your_code.
  ///
  /// In en, this message translates to:
  /// **'Enter your code'**
  String get enter_your_code;

  /// No description provided for @delivery_address.
  ///
  /// In en, this message translates to:
  /// **'Delivery address'**
  String get delivery_address;

  /// No description provided for @add_items.
  ///
  /// In en, this message translates to:
  /// **'Add items'**
  String get add_items;

  /// No description provided for @searchPlaceHint.
  ///
  /// In en, this message translates to:
  /// **'Search address or place'**
  String get searchPlaceHint;

  /// No description provided for @locationPermissionPermanentlyDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission permanently denied. Enable in settings.'**
  String get locationPermissionPermanentlyDenied;

  /// No description provided for @closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closed;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @errorUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update failed!'**
  String get errorUpdate;

  /// No description provided for @imageUploaded.
  ///
  /// In en, this message translates to:
  /// **'Image uploaded successfully'**
  String get imageUploaded;

  /// No description provided for @noPrepTime.
  ///
  /// In en, this message translates to:
  /// **'No preparation time'**
  String get noPrepTime;

  /// No description provided for @noRestaurantsFound.
  ///
  /// In en, this message translates to:
  /// **'No restaurants found'**
  String get noRestaurantsFound;

  /// No description provided for @restaurantTypesLoadedCount.
  ///
  /// In en, this message translates to:
  /// **'Loaded {count} restaurant types'**
  String restaurantTypesLoadedCount(Object count);

  /// No description provided for @uploadingImage.
  ///
  /// In en, this message translates to:
  /// **'Uploading image...'**
  String get uploadingImage;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @restaurantTypes.
  ///
  /// In en, this message translates to:
  /// **'Restaurant Types'**
  String get restaurantTypes;

  /// No description provided for @savingLanguage.
  ///
  /// In en, this message translates to:
  /// **'Saving language...'**
  String get savingLanguage;

  /// No description provided for @languageSaved.
  ///
  /// In en, this message translates to:
  /// **'Language saved successfully'**
  String get languageSaved;

  /// No description provided for @languageSavedLocalFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save language locally'**
  String get languageSavedLocalFailed;

  /// No description provided for @onboardingTapEatSmile.
  ///
  /// In en, this message translates to:
  /// **'Tap, Eat, Smile'**
  String get onboardingTapEatSmile;

  /// No description provided for @onboardingTapEatSmileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Order food with just a few taps'**
  String get onboardingTapEatSmileSubtitle;

  /// No description provided for @onboardingFlavorInAFlash.
  ///
  /// In en, this message translates to:
  /// **'Flavor in a Flash'**
  String get onboardingFlavorInAFlash;

  /// No description provided for @onboardingFlavorInAFlashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Get your meals delivered fast'**
  String get onboardingFlavorInAFlashSubtitle;

  /// No description provided for @onboardingFoodYourWay.
  ///
  /// In en, this message translates to:
  /// **'Food Your Way'**
  String get onboardingFoodYourWay;

  /// No description provided for @onboardingFoodYourWaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customize and enjoy your orders'**
  String get onboardingFoodYourWaySubtitle;

  /// No description provided for @details.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get details;

  /// No description provided for @seeAll.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get seeAll;

  /// No description provided for @hotOffers.
  ///
  /// In en, this message translates to:
  /// **'Hot Offers'**
  String get hotOffers;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get system;

  /// No description provided for @loadingOrders.
  ///
  /// In en, this message translates to:
  /// **'Loading orders...'**
  String get loadingOrders;

  /// No description provided for @assignedDriver.
  ///
  /// In en, this message translates to:
  /// **'Assigned driver'**
  String get assignedDriver;

  /// No description provided for @notAssigned.
  ///
  /// In en, this message translates to:
  /// **'Not assigned yet'**
  String get notAssigned;

  /// No description provided for @currencySymbol.
  ///
  /// In en, this message translates to:
  /// **'EGP'**
  String get currencySymbol;

  /// No description provided for @sweetBoxTitle.
  ///
  /// In en, this message translates to:
  /// **'Sweet: Order Complete 🍰'**
  String get sweetBoxTitle;

  /// No description provided for @sweetBoxBody.
  ///
  /// In en, this message translates to:
  /// **'Everything went smoothly — enjoy your meal!'**
  String get sweetBoxBody;

  /// No description provided for @bitterBoxTitle.
  ///
  /// In en, this message translates to:
  /// **'Bitter: Issue Found ⚠️'**
  String get bitterBoxTitle;

  /// No description provided for @bitterBoxBody.
  ///
  /// In en, this message translates to:
  /// **'There was a problem with this order. We\'re working on it.'**
  String get bitterBoxBody;

  /// No description provided for @qtyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Quantity updated'**
  String get qtyUpdated;

  /// No description provided for @itemRemoved.
  ///
  /// In en, this message translates to:
  /// **'Item removed from cart'**
  String get itemRemoved;

  /// No description provided for @cartCleared.
  ///
  /// In en, this message translates to:
  /// **'Cart cleared successfully'**
  String get cartCleared;

  /// No description provided for @errorLoadingRestaurants.
  ///
  /// In en, this message translates to:
  /// **'Failed to load restaurants. Please try again.'**
  String get errorLoadingRestaurants;

  /// No description provided for @errorLoadingRestaurantsDescription.
  ///
  /// In en, this message translates to:
  /// **'An error occurred while loading restaurants.'**
  String get errorLoadingRestaurantsDescription;

  /// No description provided for @terms_title.
  ///
  /// In en, this message translates to:
  /// **'Terms and Conditions'**
  String get terms_title;

  /// No description provided for @terms_paragraph1.
  ///
  /// In en, this message translates to:
  /// **'Paragraph 1: Please read carefully.'**
  String get terms_paragraph1;

  /// No description provided for @terms_paragraph2.
  ///
  /// In en, this message translates to:
  /// **'Paragraph 2: Delivery policies.'**
  String get terms_paragraph2;

  /// No description provided for @terms_paragraph3.
  ///
  /// In en, this message translates to:
  /// **'Paragraph 3: Payment and refund.'**
  String get terms_paragraph3;

  /// No description provided for @terms_paragraph4.
  ///
  /// In en, this message translates to:
  /// **'Paragraph 4: User responsibilities.'**
  String get terms_paragraph4;

  /// No description provided for @thank_you.
  ///
  /// In en, this message translates to:
  /// **'Thank you for using our service!'**
  String get thank_you;

  /// No description provided for @dark_mode_on.
  ///
  /// In en, this message translates to:
  /// **'Dark mode is ON'**
  String get dark_mode_on;

  /// No description provided for @light_mode_on.
  ///
  /// In en, this message translates to:
  /// **'Light mode is ON'**
  String get light_mode_on;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @fixed_delivery_price_applied.
  ///
  /// In en, this message translates to:
  /// **'Fixed delivery price has been applied.'**
  String get fixed_delivery_price_applied;

  /// No description provided for @searching.
  ///
  /// In en, this message translates to:
  /// **'Searching...'**
  String get searching;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'An error occurred. Please try again.'**
  String get error;

  /// No description provided for @noResults.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get noResults;

  /// No description provided for @restaurantLabel.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get restaurantLabel;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search for restaurants, meals, or offers'**
  String get searchHint;

  /// No description provided for @searchNewHint.
  ///
  /// In en, this message translates to:
  /// **'Search for restaurants'**
  String get searchNewHint;

  /// No description provided for @categoriesLabel.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categoriesLabel;

  /// No description provided for @search_hint.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get search_hint;

  /// No description provided for @no_results.
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get no_results;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @no_network_short.
  ///
  /// In en, this message translates to:
  /// **'No internet connection'**
  String get no_network_short;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Talabaatk Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Talabaatk Terms of Use'**
  String get termsOfUse;

  /// No description provided for @deleteAccountDesc.
  ///
  /// In en, this message translates to:
  /// **'Permanently delete your account and all your data.'**
  String get deleteAccountDesc;

  /// No description provided for @deleteConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete account?'**
  String get deleteConfirmTitle;

  /// No description provided for @deleteConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This will permanently remove your account and all associated data. This action cannot be undone.'**
  String get deleteConfirmMessage;

  /// No description provided for @deletingAccount.
  ///
  /// In en, this message translates to:
  /// **'Deleting account...'**
  String get deletingAccount;

  /// No description provided for @deleteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Account deleted successfully'**
  String get deleteSuccess;

  /// No description provided for @deletePartialSuccess.
  ///
  /// In en, this message translates to:
  /// **'Account data removed, but authentication record remains (re-auth needed).'**
  String get deletePartialSuccess;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete account — please try again'**
  String get deleteFailed;

  /// No description provided for @reauthRequired.
  ///
  /// In en, this message translates to:
  /// **'Please re-authenticate to delete your account (for security reasons).'**
  String get reauthRequired;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

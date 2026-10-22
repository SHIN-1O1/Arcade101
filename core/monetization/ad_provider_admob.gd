extends "res://core/monetization/ad_provider.gd"
## AdMob backend using the Poing Studios "AdMob" Godot plugin (addons/admob, v5+).
## ONLY loaded by AdService on Android when res://addons/admob exists,
## because it names plugin classes (MobileAds, InterstitialAdLoader, ...). Never preload it.
## Not testable in the cloud: needs an Android device or emulator.

const Cfg := preload("res://core/monetization/ad_config.gd")

var _host: Node
var _interstitial: InterstitialAd
var _rewarded: RewardedAd
var _banner: AdView
var _ready_sdk := false
var _loading_interstitial := false
var _loading_rewarded := false
var _showing := false


func start(host: Node, on_done: Callable) -> void:
	_host = host
	_request_consent(func():
		# Ask for ads only if consent is not still outstanding (EEA/UK user dismissed the form).
		var info := UserMessagingPlatform.consent_information
		if info.get_consent_status() != info.ConsentStatus.REQUIRED:
			_init_sdk()
		on_done.call())


# --- Consent (Google UMP) ---------------------------------------------------

func _request_consent(done: Callable) -> void:
	var params := ConsentRequestParameters.new()
	params.tag_for_under_age_of_consent = Cfg.UNDER_AGE_OF_CONSENT
	if Cfg.DEBUG_FORCE_EEA and OS.is_debug_build() and Cfg.DEBUG_TEST_DEVICE_HASH != "":
		var dbg := ConsentDebugSettings.new()
		dbg.debug_geography = DebugGeography.Values.EEA
		dbg.test_device_hashed_ids.append(Cfg.DEBUG_TEST_DEVICE_HASH)
		params.consent_debug_settings = dbg
	UserMessagingPlatform.consent_information.update(params,
		func():
			if UserMessagingPlatform.consent_information.get_is_consent_form_available():
				UserMessagingPlatform.load_consent_form(
					func(form: ConsentForm): _on_form_loaded(form, done),
					func(_e: FormError): done.call())
			else:
				done.call(),
		func(_e: FormError): done.call())


func _on_form_loaded(form: ConsentForm, done: Callable) -> void:
	var info := UserMessagingPlatform.consent_information
	if info.get_consent_status() == info.ConsentStatus.REQUIRED:
		form.show(func(_e: FormError): done.call())
	else:
		done.call()


func privacy_options_required() -> bool:
	var info := UserMessagingPlatform.consent_information
	return info.get_privacy_options_requirement_status() == info.PrivacyOptionsRequirementStatus.REQUIRED


func show_privacy_options(on_done: Callable) -> void:
	UserMessagingPlatform.show_privacy_options_form(func(_e: FormError):
		# The user may have just granted consent: start serving if we were holding back.
		var info := UserMessagingPlatform.consent_information
		if not _ready_sdk and info.get_consent_status() != info.ConsentStatus.REQUIRED:
			_init_sdk()
		on_done.call())


# --- SDK --------------------------------------------------------------------

func _init_sdk() -> void:
	if _ready_sdk:
		return
	var cfg := RequestConfiguration.new()
	cfg.tag_for_child_directed_treatment = (RequestConfiguration.TagForChildDirectedTreatment.TRUE
		if Cfg.CHILD_DIRECTED else RequestConfiguration.TagForChildDirectedTreatment.FALSE)
	cfg.tag_for_under_age_of_consent = (RequestConfiguration.TagForUnderAgeOfConsent.TRUE
		if Cfg.UNDER_AGE_OF_CONSENT else RequestConfiguration.TagForUnderAgeOfConsent.FALSE)
	cfg.max_ad_content_rating = RequestConfiguration.MAX_AD_CONTENT_RATING_PG
	MobileAds.set_request_configuration(cfg)
	var listener := OnInitializationCompleteListener.new()
	listener.on_initialization_complete = func(_status: InitializationStatus):
		_ready_sdk = true
		_load_interstitial()
		_load_rewarded()
	MobileAds.initialize(listener)


# --- Interstitial -----------------------------------------------------------

func _load_interstitial() -> void:
	var id := Cfg.interstitial_id()
	if not _ready_sdk or _loading_interstitial or _interstitial != null or id == "":
		return
	_loading_interstitial = true
	var cb := InterstitialAdLoadCallback.new()
	cb.on_ad_failed_to_load = func(e: LoadAdError):
		_loading_interstitial = false
		push_warning("[Ads] interstitial load failed: %s" % e.message)
		_retry_later(_load_interstitial)
	cb.on_ad_loaded = func(ad: InterstitialAd):
		_loading_interstitial = false
		_interstitial = ad
	InterstitialAdLoader.new().load(id, AdRequest.new(), cb)


func is_interstitial_ready() -> bool:
	return _interstitial != null and not _showing


func show_interstitial(on_closed: Callable) -> void:
	if not is_interstitial_ready():
		on_closed.call()
		return
	var ad := _interstitial
	_interstitial = null
	_showing = true
	var fin := func():
		if not _showing:
			return
		_showing = false
		ad.destroy()
		_load_interstitial()
		on_closed.call()
	var cb := FullScreenContentCallback.new()
	cb.on_ad_dismissed_full_screen_content = fin
	cb.on_ad_failed_to_show_full_screen_content = func(_e: AdError): fin.call()
	ad.full_screen_content_callback = cb
	ad.show()


# --- Rewarded ---------------------------------------------------------------

func _load_rewarded() -> void:
	var id := Cfg.rewarded_id()
	if not _ready_sdk or _loading_rewarded or _rewarded != null or id == "":
		return
	_loading_rewarded = true
	var cb := RewardedAdLoadCallback.new()
	cb.on_ad_failed_to_load = func(e: LoadAdError):
		_loading_rewarded = false
		push_warning("[Ads] rewarded load failed: %s" % e.message)
		_retry_later(_load_rewarded)
	cb.on_ad_loaded = func(ad: RewardedAd):
		_loading_rewarded = false
		_rewarded = ad
	RewardedAdLoader.new().load(id, AdRequest.new(), cb)


func is_rewarded_ready() -> bool:
	return _rewarded != null and not _showing


func show_rewarded(on_result: Callable) -> void:
	if not is_rewarded_ready():
		on_result.call(false)
		return
	var ad := _rewarded
	_rewarded = null
	_showing = true
	var earned := [false]
	var fin := func():
		if not _showing:
			return
		_showing = false
		ad.destroy()
		_load_rewarded()
		on_result.call(earned[0])
	var cb := FullScreenContentCallback.new()
	cb.on_ad_dismissed_full_screen_content = fin  # reward event arrives before dismissal
	cb.on_ad_failed_to_show_full_screen_content = func(_e: AdError): fin.call()
	ad.full_screen_content_callback = cb
	var listener := OnUserEarnedRewardListener.new()
	listener.on_user_earned_reward = func(_item: RewardedItem): earned[0] = true
	ad.show(listener)


# --- Banner -----------------------------------------------------------------

func show_banner() -> void:
	var id := Cfg.banner_id()
	if not _ready_sdk or id == "":
		return
	if _banner == null:
		_banner = AdView.new(id, AdSize.BANNER, AdPosition.BOTTOM)
		_banner.load_ad(AdRequest.new())
	_banner.show()


func hide_banner() -> void:
	if _banner != null:
		_banner.hide()


func _retry_later(loader: Callable) -> void:
	if _host != null and _host.is_inside_tree():
		_host.get_tree().create_timer(30.0).timeout.connect(loader)

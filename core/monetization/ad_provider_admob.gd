extends "res://core/monetization/ad_provider.gd"
## AdMob backend using the Poing Studios "AdMob" Godot plugin (addons/admob, v5+).
## Loaded by AdService only on Android when res://addons/admob exists.
## The plugin's classes (MobileAds, InterstitialAdLoader, ...) are looked up BY NAME at runtime
## (see _c) and everything is untyped, so this file parses cleanly in an editor that has no plugin
## installed. Never add typed references (`var x: InterstitialAd`) or direct class names here.
## Not testable in the cloud: needs an Android device or emulator.

const Cfg := preload("res://core/monetization/ad_config.gd")

static var _classes := {}

var _host: Node
var _interstitial = null
var _rewarded = null
var _banner = null
var _ready_sdk := false
var _loading_interstitial := false
var _loading_rewarded := false
var _showing := false


## Script of a plugin class (class_name) by name, e.g. _c("MobileAds"). Static calls, static vars,
## constants and .new() all work on the returned script.
static func _c(class_id: String):
	if not _classes.has(class_id):
		_classes[class_id] = null
		for entry in ProjectSettings.get_global_class_list():
			if entry["class"] == class_id:
				_classes[class_id] = load(entry["path"])
				break
	return _classes[class_id]


func start(host: Node, on_done: Callable) -> void:
	_host = host
	_request_consent(func():
		# Ask for ads only if consent is not still outstanding (EEA/UK user dismissed the form).
		if not _consent_outstanding():
			_init_sdk()
		on_done.call())


# --- Consent (Google UMP) ---------------------------------------------------

func _info():
	return _c("UserMessagingPlatform").consent_information


func _consent_outstanding() -> bool:
	return _info().get_consent_status() == 2  # ConsentStatus.REQUIRED


func _request_consent(done: Callable) -> void:
	var ump = _c("UserMessagingPlatform")
	var params = _c("ConsentRequestParameters").new()
	params.tag_for_under_age_of_consent = Cfg.UNDER_AGE_OF_CONSENT
	if Cfg.DEBUG_FORCE_EEA and OS.is_debug_build() and Cfg.DEBUG_TEST_DEVICE_HASH != "":
		var dbg = _c("ConsentDebugSettings").new()
		dbg.debug_geography = _c("DebugGeography").Values.EEA
		dbg.test_device_hashed_ids.append(Cfg.DEBUG_TEST_DEVICE_HASH)
		params.consent_debug_settings = dbg
	ump.consent_information.update(params,
		func():
			if ump.consent_information.get_is_consent_form_available():
				ump.load_consent_form(
					func(form): _on_form_loaded(form, done),
					func(_e): done.call())
			else:
				done.call(),
		func(_e): done.call())


func _on_form_loaded(form, done: Callable) -> void:
	if _consent_outstanding():
		form.show(func(_e): done.call())
	else:
		done.call()


func privacy_options_required() -> bool:
	return _info().get_privacy_options_requirement_status() == 2  # PrivacyOptionsRequirementStatus.REQUIRED


func show_privacy_options(on_done: Callable) -> void:
	_c("UserMessagingPlatform").show_privacy_options_form(func(_e):
		# The user may have just granted consent: start serving if we were holding back.
		if not _ready_sdk and not _consent_outstanding():
			_init_sdk()
		on_done.call())


# --- SDK --------------------------------------------------------------------

func _init_sdk() -> void:
	if _ready_sdk:
		return
	var rc = _c("RequestConfiguration")
	var cfg = rc.new()
	cfg.tag_for_child_directed_treatment = (rc.TagForChildDirectedTreatment.TRUE
		if Cfg.CHILD_DIRECTED else rc.TagForChildDirectedTreatment.FALSE)
	cfg.tag_for_under_age_of_consent = (rc.TagForUnderAgeOfConsent.TRUE
		if Cfg.UNDER_AGE_OF_CONSENT else rc.TagForUnderAgeOfConsent.FALSE)
	cfg.max_ad_content_rating = rc.MAX_AD_CONTENT_RATING_PG
	var ads = _c("MobileAds")
	ads.set_request_configuration(cfg)
	var listener = _c("OnInitializationCompleteListener").new()
	listener.on_initialization_complete = func(_status):
		_ready_sdk = true
		_load_interstitial()
		_load_rewarded()
	ads.initialize(listener)


# --- Interstitial -----------------------------------------------------------

func _load_interstitial() -> void:
	var id := Cfg.interstitial_id()
	if not _ready_sdk or _loading_interstitial or _interstitial != null or id == "":
		return
	_loading_interstitial = true
	var cb = _c("InterstitialAdLoadCallback").new()
	cb.on_ad_failed_to_load = func(e):
		_loading_interstitial = false
		push_warning("[Ads] interstitial load failed: %s" % e.message)
		_retry_later(_load_interstitial)
	cb.on_ad_loaded = func(ad):
		_loading_interstitial = false
		_interstitial = ad
	_c("InterstitialAdLoader").new().load(id, _c("AdRequest").new(), cb)


func is_interstitial_ready() -> bool:
	return _interstitial != null and not _showing


func show_interstitial(on_closed: Callable) -> void:
	if not is_interstitial_ready():
		on_closed.call()
		return
	var ad = _interstitial
	_interstitial = null
	_showing = true
	var fin := func():
		if not _showing:
			return
		_showing = false
		ad.destroy()
		_load_interstitial()
		on_closed.call()
	var cb = _c("FullScreenContentCallback").new()
	cb.on_ad_dismissed_full_screen_content = fin
	cb.on_ad_failed_to_show_full_screen_content = func(_e): fin.call()
	ad.full_screen_content_callback = cb
	ad.show()


# --- Rewarded ---------------------------------------------------------------

func _load_rewarded() -> void:
	var id := Cfg.rewarded_id()
	if not _ready_sdk or _loading_rewarded or _rewarded != null or id == "":
		return
	_loading_rewarded = true
	var cb = _c("RewardedAdLoadCallback").new()
	cb.on_ad_failed_to_load = func(e):
		_loading_rewarded = false
		push_warning("[Ads] rewarded load failed: %s" % e.message)
		_retry_later(_load_rewarded)
	cb.on_ad_loaded = func(ad):
		_loading_rewarded = false
		_rewarded = ad
	_c("RewardedAdLoader").new().load(id, _c("AdRequest").new(), cb)


func is_rewarded_ready() -> bool:
	return _rewarded != null and not _showing


func show_rewarded(on_result: Callable) -> void:
	if not is_rewarded_ready():
		on_result.call(false)
		return
	var ad = _rewarded
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
	var cb = _c("FullScreenContentCallback").new()
	cb.on_ad_dismissed_full_screen_content = fin  # reward event arrives before dismissal
	cb.on_ad_failed_to_show_full_screen_content = func(_e): fin.call()
	ad.full_screen_content_callback = cb
	var listener = _c("OnUserEarnedRewardListener").new()
	listener.on_user_earned_reward = func(_item): earned[0] = true
	ad.show(listener)


# --- Banner -----------------------------------------------------------------

func show_banner() -> void:
	var id := Cfg.banner_id()
	if not _ready_sdk or id == "":
		return
	if _banner == null:
		_banner = _c("AdView").new(id, _c("AdSize").BANNER, _c("AdPosition").BOTTOM)
		_banner.load_ad(_c("AdRequest").new())
	_banner.show()


func hide_banner() -> void:
	if _banner != null:
		_banner.hide()


func _retry_later(loader: Callable) -> void:
	if _host != null and _host.is_inside_tree():
		_host.get_tree().create_timer(30.0).timeout.connect(loader)

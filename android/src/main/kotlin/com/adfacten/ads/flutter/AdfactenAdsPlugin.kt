package com.adfacten.ads.flutter

import android.app.Activity
import android.content.Context
import com.adfacten.ads.AdError
import com.adfacten.ads.AdLoadCallback
import com.adfacten.ads.Adfacten
import com.adfacten.ads.AdfactenConfig
import com.adfacten.ads.AppOpenAd
import com.adfacten.ads.FullScreenAd
import com.adfacten.ads.FullScreenAdListener
import com.adfacten.ads.InterstitialAd
import com.adfacten.ads.LogLevel
import com.adfacten.ads.NativeAd
import com.adfacten.ads.NativeAdListener
import com.adfacten.ads.RewardedAd
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges the Dart API to the Adfacten Android SDK.
 *
 * Dart gives every ad an integer id. Loaded full-screen and native ads live in [ads] until Dart
 * disposes them (or a full-screen ad closes). Events go back on the same channel as `onAdEvent`.
 * All calls and SDK callbacks run on the main thread.
 */
class AdfactenAdsPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null
    private var appContext: Context? = null
    private var activity: Activity? = null

    private val ads = HashMap<Int, Any>()
    private val pendingLoads = HashSet<Int>()
    private val shown = HashSet<Int>()

    /** Bumped on `reset` (Dart hot restart) so callbacks of older ads are dropped. */
    private var generation = 0

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also { it.setMethodCallHandler(this) }
        binding.platformViewRegistry.registerViewFactory(BANNER_VIEW, BannerViewFactory(this))
        binding.platformViewRegistry.registerViewFactory(NATIVE_VIEW, NativeAdViewFactory(this))
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        clearAds()
        appContext = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "reset" -> {
                    clearAds()
                    result.success(null)
                }
                "initialize" -> initialize(call, result)
                "setUserId" -> {
                    Adfacten.setUserId(call.argument<String>("userId"))
                    result.success(null)
                }
                "isInitialized" -> result.success(Adfacten.isInitialized)
                "sdkVersion" -> result.success(Adfacten.sdkVersion)
                "loadAd" -> loadAd(call, result)
                "showAd" -> showAd(call, result)
                "isAdReady" -> {
                    val id = call.adId()
                    val ad = ads[id] as? FullScreenAd
                    result.success(ad != null && id !in shown && !ad.isExpired)
                }
                "disposeAd" -> {
                    disposeAd(call.adId())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("internal_error", e.message ?: e.toString(), null)
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext ?: return result.error("internal_error", "plugin is detached", null)
        val appKey = call.argument<String>("appKey").orEmpty()
        val config = AdfactenConfig(
            testMode = call.argument<Boolean>("testMode") ?: false,
            logLevel = when (call.argument<String>("logLevel")) {
                "none" -> LogLevel.NONE
                "error" -> LogLevel.ERROR
                "info" -> LogLevel.INFO
                "debug" -> LogLevel.DEBUG
                else -> LogLevel.WARN
            },
            childDirected = call.argument<Boolean>("childDirected") ?: false,
            userId = call.argument<String>("userId"),
        )
        Adfacten.setWrapper("flutter", call.argument<String>("pluginVersion") ?: "unknown")
        Adfacten.initialize(context, appKey, config)
        result.success(null)
    }

    private fun loadAd(call: MethodCall, result: MethodChannel.Result) {
        val context = appContext ?: return result.error("internal_error", "plugin is detached", null)
        val id = call.adId()
        val placementId = call.argument<String>("placementId").orEmpty()
        val gen = generation
        pendingLoads.add(id)

        fun <T : Any> callback(onLoaded: (T) -> Map<String, Any?>) = object : AdLoadCallback<T> {
            override fun onLoaded(ad: T) {
                if (gen != generation || !pendingLoads.remove(id)) {
                    (ad as? NativeAd)?.destroy()
                    result.error("disposed", "the ad was disposed while loading", null)
                    return
                }
                ads[id] = ad
                result.success(onLoaded(ad))
            }

            override fun onFailed(error: AdError) {
                pendingLoads.remove(id)
                result.error(error.name, error.message, error.details())
            }
        }

        when (call.argument<String>("format")) {
            "interstitial" -> InterstitialAd.load(context, placementId, callback<InterstitialAd> { emptyMap() })
            "appOpen" -> AppOpenAd.load(context, placementId, callback<AppOpenAd> { emptyMap() })
            "rewarded" -> RewardedAd.load(
                context,
                placementId,
                callback<RewardedAd> { ad -> mapOf("reward" to ad.reward?.let { mapOf("type" to it.type, "amount" to it.amount) }) },
                call.argument<String>("customData"),
            )
            "native" -> NativeAd.load(context, placementId, callback<NativeAd> { ad ->
                ad.listener = object : NativeAdListener {
                    override fun onShown() = send(gen, id, "shown")
                    override fun onClicked() = send(gen, id, "clicked")
                }
                ad.assets()
            })
            else -> {
                pendingLoads.remove(id)
                result.error("invalid_request", "unknown format ${call.argument<String>("format")}", null)
            }
        }
    }

    private fun showAd(call: MethodCall, result: MethodChannel.Result) {
        val id = call.adId()
        val ad = ads[id] as? FullScreenAd
            ?: return result.error("disposed", "the ad was disposed or not loaded", null)
        val act = activity
        if (act == null || act.isFinishing) {
            return result.error("show_failed", "no foreground activity", null)
        }
        val gen = generation
        ad.listener = object : FullScreenAdListener {
            override fun onShown() = send(gen, id, "shown")
            override fun onClicked() = send(gen, id, "clicked")
            override fun onClosed() {
                if (gen == generation) {
                    ads.remove(id)
                    shown.remove(id)
                }
                send(gen, id, "closed")
            }
            override fun onFailedToShow(error: AdError) {
                // SHOW_FAILED (another ad on screen, activity finishing) leaves the ad usable.
                if (gen == generation && error.code == AdError.SHOW_FAILED) shown.remove(id)
                send(gen, id, "failedToShow", mapOf("error" to error.toMap()))
            }
        }
        shown.add(id)
        when (ad) {
            is InterstitialAd -> ad.show(act)
            is AppOpenAd -> ad.show(act)
            is RewardedAd -> ad.show(act) { reward ->
                send(gen, id, "reward", mapOf("reward" to mapOf("type" to reward.type, "amount" to reward.amount)))
            }
        }
        result.success(null)
    }

    private fun disposeAd(id: Int) {
        pendingLoads.remove(id)
        shown.remove(id)
        when (val ad = ads.remove(id)) {
            is NativeAd -> ad.destroy()
            // A full-screen ad on screen is kept alive by the SDK until it closes.
            is FullScreenAd -> ad.listener = null
        }
    }

    private fun clearAds() {
        generation++
        ads.values.forEach { ad ->
            when (ad) {
                is NativeAd -> ad.destroy()
                is FullScreenAd -> ad.listener = null
            }
        }
        ads.clear()
        pendingLoads.clear()
        shown.clear()
    }

    internal fun nativeAd(id: Int): NativeAd? = ads[id] as? NativeAd

    /** Sends an ad event, unless the ad belongs to an earlier Dart isolate. */
    internal fun send(gen: Int, id: Int, event: String, extra: Map<String, Any?> = emptyMap()) {
        if (gen != generation) return
        send(id, event, extra)
    }

    internal fun send(id: Int, event: String, extra: Map<String, Any?> = emptyMap()) {
        channel?.invokeMethod("onAdEvent", hashMapOf<String, Any?>("adId" to id, "event" to event).apply { putAll(extra) })
    }

    internal val currentGeneration: Int get() = generation

    private fun MethodCall.adId(): Int = (argument<Number>("adId"))?.toInt()
        ?: throw IllegalArgumentException("adId is missing")

    private companion object {
        const val CHANNEL = "com.adfacten.ads"
        const val BANNER_VIEW = "com.adfacten.ads/banner"
        const val NATIVE_VIEW = "com.adfacten.ads/native"
    }
}

private fun NativeAd.assets(): Map<String, Any?> = mapOf(
    "title" to title,
    "body" to body,
    "brand" to brand,
    "callToAction" to callToAction,
    "adLabel" to adLabel,
    "imageUrl" to imageUrl,
    "iconUrl" to iconUrl,
    "imageWidth" to imageWidth,
    "imageHeight" to imageHeight,
    "hasImage" to (image != null),
    "hasIcon" to (icon != null),
)

internal fun AdError.details(): Map<String, Any?> = mapOf("serverCode" to serverCode, "nativeCode" to code)

/** Error payload for Dart. `code` is the SDK's stable error name (`no_fill`, `rejected`, ...). */
internal fun AdError.toMap(): Map<String, Any?> =
    mapOf("code" to name, "message" to message, "serverCode" to serverCode, "nativeCode" to code)

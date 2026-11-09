package com.adfacten.ads.flutter

import android.content.Context
import android.view.View
import com.adfacten.ads.AdError
import com.adfacten.ads.AdSize
import com.adfacten.ads.AdfactenBannerView
import com.adfacten.ads.BannerAdListener
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal class BannerViewFactory(private val plugin: AdfactenAdsPlugin) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<String, Any?>()
        return BannerPlatformView(
            context = context,
            plugin = plugin,
            adId = (params["adId"] as? Number)?.toInt() ?: -1,
            placementId = params["placementId"] as? String,
            size = when (params["size"]) {
                "largeBanner" -> AdSize.LARGE_BANNER
                "mediumRectangle" -> AdSize.MEDIUM_RECTANGLE
                "leaderboard" -> AdSize.LEADERBOARD
                else -> AdSize.BANNER
            },
        )
    }
}

/** Hosts an [AdfactenBannerView]. Flutter disposes it when the widget leaves the tree. */
private class BannerPlatformView(
    context: Context,
    plugin: AdfactenAdsPlugin,
    adId: Int,
    placementId: String?,
    size: AdSize,
) : PlatformView {
    private val banner = AdfactenBannerView(context).apply {
        this.placementId = placementId
        adSize = size
        listener = object : BannerAdListener {
            override fun onLoaded() = plugin.send(adId, "loaded")
            override fun onFailed(error: AdError) = plugin.send(adId, "failedToLoad", mapOf("error" to error.toMap()))
            override fun onShown() = plugin.send(adId, "shown")
            override fun onClicked() = plugin.send(adId, "clicked")
        }
    }

    init {
        banner.load()
    }

    override fun getView(): View = banner

    override fun dispose() {
        banner.listener = null
        banner.destroy()
    }
}

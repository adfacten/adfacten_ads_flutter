package com.adfacten.ads.flutter

import android.content.Context
import android.graphics.Color
import android.graphics.Outline
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.text.TextUtils
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import com.adfacten.ads.NativeAd
import com.adfacten.ads.NativeAdView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.roundToInt

internal class NativeAdViewFactory(private val plugin: AdfactenAdsPlugin) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<String, Any?>()
        return NativeTemplatePlatformView(context, plugin, params)
    }
}

/** Colors and radii sent from Dart (already resolved against the app theme). */
private class TemplateStyle(private val map: Map<*, *>) {
    private fun color(key: String, default: Int): Int = (map[key] as? Number)?.toInt() ?: default
    private fun dimen(key: String, default: Float): Float = (map[key] as? Number)?.toFloat() ?: default

    val background = color("backgroundColor", Color.WHITE)
    val title = color("titleColor", 0xFF1B1B1F.toInt())
    val body = color("bodyColor", 0xFF46464F.toInt())
    val brand = color("brandColor", 0xFF46464F.toInt())
    val ctaBackground = color("callToActionBackgroundColor", 0xFF3F51B5.toInt())
    val ctaText = color("callToActionTextColor", Color.WHITE)
    val labelBackground = color("adLabelBackgroundColor", 0xFFFFE082.toInt())
    val labelText = color("adLabelTextColor", 0xFF3E2E00.toInt())
    val cornerRadius = dimen("cornerRadius", 12f)
    val ctaCornerRadius = dimen("callToActionCornerRadius", 20f)
}

/**
 * Lays out a native ad in a [NativeAdView] from one of the templates. The SDK view records the
 * impression, the viewable impression and clicks. The content height is reported to Dart, which
 * sizes the platform view to match.
 */
private class NativeTemplatePlatformView(
    private val context: Context,
    private val plugin: AdfactenAdsPlugin,
    params: Map<*, *>,
) : PlatformView {
    private val adId = (params["adId"] as? Number)?.toInt() ?: -1
    private val small = params["template"] == "small"
    private val style = TemplateStyle(params["style"] as? Map<*, *> ?: emptyMap<String, Any?>())
    private val density = context.resources.displayMetrics.density
    private val adView = NativeAdView(context)
    private var content: View? = null
    private var measuredWidth = 0
    private var reportedHeight = 0

    init {
        val ad = plugin.nativeAd(adId)
        if (ad != null) {
            val root = if (small) buildSmall(ad) else buildMedium(ad)
            content = root
            adView.addView(root, FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
            adView.setNativeAd(ad)
            if (!small && ad.image == null) adView.imageView?.visibility = View.GONE
            val width = ((params["width"] as? Number)?.toFloat() ?: 0f) * density
            measure(width.roundToInt())
            adView.addOnLayoutChangeListener { _, left, _, right, _, _, _, _, _ ->
                val w = right - left
                if (w > 0 && w != measuredWidth) adView.post { measure(w) }
            }
        }
    }

    override fun getView(): View = adView

    override fun dispose() {
        if (adView.getNativeAd() != null) adView.setNativeAd(null)
    }

    private fun measure(widthPx: Int) {
        val root = content ?: return
        if (widthPx <= 0) return
        measuredWidth = widthPx
        root.measure(
            View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY),
            View.MeasureSpec.makeMeasureSpec(0, View.MeasureSpec.UNSPECIFIED),
        )
        val h = root.measuredHeight
        if (h > 0 && h != reportedHeight) {
            reportedHeight = h
            plugin.send(adId, "measured", mapOf("height" to h / density.toDouble()))
        }
    }

    // Templates

    private fun buildMedium(ad: NativeAd): View {
        val root = column().apply {
            setPadding(dp(12), dp(12), dp(12), dp(12))
            background = rounded(style.background, style.cornerRadius)
            clipRounded(style.cornerRadius)
        }

        val header = row()
        val icon = imageView(rounded = 8f)
        header.addView(icon, LinearLayout.LayoutParams(dp(40), dp(40)).apply { marginEnd = dp(10) })
        val names = column()
        val title = text(15f, style.title, bold = true, lines = 2)
        val brand = text(12f, style.brand, lines = 1)
        names.addView(title)
        names.addView(brand)
        header.addView(names, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))
        val label = adLabel()
        header.addView(label, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            marginStart = dp(8)
            gravity = Gravity.TOP
        })
        root.addView(header)

        val image = AspectImageView(context, ad.aspectRatio()).apply {
            scaleType = ImageView.ScaleType.CENTER_CROP
            clipRounded(8f)
        }
        root.addView(image, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(10)
        })

        val body = text(13f, style.body, lines = 3)
        root.addView(body, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(8)
        })

        val cta = callToAction()
        root.addView(cta, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(40)).apply {
            topMargin = dp(10)
        })

        adView.titleView = title
        adView.brandView = brand
        adView.bodyView = body
        adView.iconView = icon
        adView.imageView = image
        adView.callToActionView = cta
        adView.adLabelView = label
        return root
    }

    private fun buildSmall(ad: NativeAd): View {
        val root = row().apply {
            setPadding(dp(12), dp(10), dp(12), dp(10))
            background = rounded(style.background, style.cornerRadius)
            clipRounded(style.cornerRadius)
        }

        val thumb = imageView(rounded = 8f)
        root.addView(thumb, LinearLayout.LayoutParams(dp(56), dp(56)).apply { marginEnd = dp(10) })
        when {
            ad.icon != null -> adView.iconView = thumb
            ad.image != null -> adView.imageView = thumb
            else -> thumb.visibility = View.GONE
        }

        val texts = column()
        val top = row()
        val label = adLabel()
        top.addView(label)
        val brand = text(12f, style.brand, lines = 1)
        top.addView(brand, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply { marginStart = dp(6) })
        texts.addView(top)
        val title = text(14f, style.title, bold = true, lines = 2)
        texts.addView(title, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
            topMargin = dp(2)
        })
        val body = text(12f, style.body, lines = 1)
        texts.addView(body)
        root.addView(texts, LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f))

        val cta = callToAction().apply { setPadding(dp(14), 0, dp(14), 0) }
        root.addView(cta, LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, dp(36)).apply { marginStart = dp(10) })

        adView.titleView = title
        adView.brandView = brand
        adView.bodyView = body
        adView.callToActionView = cta
        adView.adLabelView = label
        return root
    }

    // Building blocks

    private fun dp(v: Int): Int = (v * density).roundToInt()

    private fun column() = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }

    private fun row() = LinearLayout(context).apply {
        orientation = LinearLayout.HORIZONTAL
        gravity = Gravity.CENTER_VERTICAL
    }

    private fun rounded(color: Int, radiusDp: Float) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = radiusDp * density
    }

    private fun View.clipRounded(radiusDp: Float) {
        val r = radiusDp * density
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, r)
            }
        }
        clipToOutline = r > 0
    }

    private fun imageView(rounded: Float) = ImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
        clipRounded(rounded)
    }

    private fun text(sizeSp: Float, color: Int, bold: Boolean = false, lines: Int) = TextView(context).apply {
        setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
        setTextColor(color)
        if (bold) typeface = Typeface.DEFAULT_BOLD
        maxLines = lines
        ellipsize = TextUtils.TruncateAt.END
    }

    private fun adLabel() = text(10f, style.labelText, bold = true, lines = 1).apply {
        setPadding(dp(5), dp(1), dp(5), dp(1))
        background = rounded(style.labelBackground, 4f)
    }

    private fun callToAction() = text(14f, style.ctaText, bold = true, lines = 1).apply {
        gravity = Gravity.CENTER
        background = rounded(style.ctaBackground, style.ctaCornerRadius)
    }
}

private fun NativeAd.aspectRatio(): Float =
    if (imageWidth > 0 && imageHeight > 0) (imageWidth.toFloat() / imageHeight).coerceIn(0.5f, 4f) else 1.91f

/** An image view whose height follows its width. */
private class AspectImageView(context: Context, private val ratio: Float) : ImageView(context) {
    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val w = MeasureSpec.getSize(widthMeasureSpec)
        val h = (w / ratio).roundToInt()
        setMeasuredDimension(w, h)
    }
}

//
//  PortraitNativeAdView.swift
//  MobileAdsClient
//
//  Portrait "poster" native ad renderer for grid cells. A fixed 9:16
//  `MediaView` hero sits on top (rounded, no background); the icon, headline,
//  advertiser + "Ad" badge and a full-width CTA are stacked below it, flush to
//  the card's width. The card itself has no background; only the media view is
//  corner-rounded. Unlike `RowMediaNativeAdView`, the media box is LOCKED to
//  the config's `mediaAspectMultiplier` and is not rewritten to the creative's
//  true ratio, so every card in a grid keeps a uniform hero height.
//

#if canImport(UIKit)
import GoogleMobileAds
import NativeAdClient
import UIKit

public class PortraitNativeAdView: NativeAdView {

    public typealias Style = NativeAdClient.Configuration.Style

    public let configuration: NativeAdClient.Configuration.Portrait
    public var style: Style {
        didSet { applyStyle() }
    }

    private var bodyDisplay: NativeAdClient.Configuration.BodyDisplay { configuration.bodyDisplay }
    private var insets: UIEdgeInsets { configuration.insets }

    // Fixed gap between the media hero and the footer chrome below it — kept
    // distinct from `metrics.verticalSpacing` (the inner text stack's gap).
    private let mediaToFooterSpacing: CGFloat = 10

    // MARK: - Subviews

    // Rounded, clipping host for the media hero. Only this view is corner-
    // rounded — the card itself stays background-less.
    private lazy var mediaContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = configuration.metrics.containerCornerRadius
        view.layer.masksToBounds = true
        return view
    }()

    private lazy var adMediaView: MediaView = {
        let view = MediaView()
        view.accessibilityIdentifier = "Portrait Native Media"
        view.translatesAutoresizingMaskIntoConstraints = false
        // Fill the fixed 9:16 box edge-to-edge so a portrait video/creative
        // (requested via `MediaAspectRatioOption(.portrait)`) covers the whole
        // hero. `masksToBounds` clips the center-crop overflow when a creative
        // isn't exactly 9:16.
        view.contentMode = .scaleAspectFill
        view.layer.masksToBounds = true
        // Defeat MediaView's intrinsic content size: once a video starts it
        // reports the creative's (often landscape) size, which would otherwise
        // beat the 9:16 aspect constraint and collapse the hero to that ratio.
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }()

    private lazy var adIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.accessibilityIdentifier = "Portrait Native Icon"
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.layer.masksToBounds = true
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        // Below the 999-priority width constraint so the fixed square
        // `iconSize` wins over the image's intrinsic width.
        imageView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return imageView
    }()

    private lazy var adHeadlineLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Portrait Native Headline"
        label.translatesAutoresizingMaskIntoConstraints = false
        // Title must never be truncated (Google native policy). Wrap instead
        // of clipping with an ellipsis.
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        return label
    }()

    private lazy var adAdvertiserLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Portrait Native Advertiser"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private lazy var adAttributionLabel: PaddedLabel = {
        let label = PaddedLabel(padding: UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6))
        label.accessibilityIdentifier = "Portrait Native Attribution"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Ad"
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private lazy var adBodyLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Portrait Native Body"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private lazy var actionButton: UIButton = {
        let button = UIButton(type: .system)
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
        button.configuration = config
        button.accessibilityIdentifier = "Portrait Native CTA"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Install", for: .normal)
        button.isUserInteractionEnabled = false
        // Lowered so `.fill` alignment stretches the CTA to the footer width.
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }()

    // MARK: - Init

    public init(
        frame: CGRect = .zero,
        configuration: NativeAdClient.Configuration.Portrait = .default
    ) {
        self.configuration = configuration
        self.style = configuration.style
        super.init(frame: frame)
        setupViews()
        updateViewBindings()
        applyStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            setNeedsLayout()
        }
    }
}

// MARK: - Setup

extension PortraitNativeAdView {
    private func setupViews() {
        // No fill/corner on the card itself — only `mediaContainer` is rounded.
        adIconImageView.layer.cornerRadius = configuration.metrics.iconCornerRadius

        switch bodyDisplay.mode {
            case .hidden, .full:
                adBodyLabel.numberOfLines = 0
            case .truncated(let lines):
                adBodyLabel.numberOfLines = max(1, lines)
        }

        let footer = makeFooter()
        mediaContainer.addSubview(adMediaView)
        addSubview(mediaContainer)
        addSubview(footer)

        NSLayoutConstraint.activate([
            // Media hero container: flush to the card's top + side edges, 9:16.
            mediaContainer.topAnchor.constraint(equalTo: topAnchor),
            mediaContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            mediaContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            mediaContainer.heightAnchor.constraint(
                equalTo: mediaContainer.widthAnchor,
                multiplier: configuration.mediaAspectMultiplier
            ).priority(.required),

            // Media fills its rounded container.
            adMediaView.topAnchor.constraint(equalTo: mediaContainer.topAnchor),
            adMediaView.leadingAnchor.constraint(equalTo: mediaContainer.leadingAnchor),
            adMediaView.trailingAnchor.constraint(equalTo: mediaContainer.trailingAnchor),
            adMediaView.bottomAnchor.constraint(equalTo: mediaContainer.bottomAnchor),

            // Footer chrome: icon + text + CTA below the media, flush to the
            // card width (insets default to 0 on the sides).
            footer.topAnchor.constraint(equalTo: mediaContainer.bottomAnchor, constant: mediaToFooterSpacing),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),

            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: configuration.metrics.ctaMinHeight)
                .priority(UILayoutPriority(999)),

            adIconImageView.widthAnchor.constraint(equalToConstant: configuration.metrics.iconSize.width)
                .priority(UILayoutPriority(999)),
            adIconImageView.heightAnchor.constraint(equalToConstant: configuration.metrics.iconSize.height)
                .priority(UILayoutPriority(999)),
        ])
    }

    /// Builds the footer chrome below the media: `[icon | headline / advertiser
    /// + "Ad"]` stacked on top of a full-width CTA.
    private func makeFooter() -> UIStackView {
        // Hug the advertiser text so it never stretches to fill the row; a
        // trailing flexible spacer absorbs the leftover space instead, keeping
        // the "Ad" chip pinned 6pt after the name however short the name is.
        adAdvertiserLabel.setContentHuggingPriority(.required, for: .horizontal)

        let trailingSpacer = UIView()
        trailingSpacer.translatesAutoresizingMaskIntoConstraints = false
        trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailingSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let advertiserRow = UIStackView(arrangedSubviews: [adAdvertiserLabel, adAttributionLabel, trailingSpacer])
        advertiserRow.axis = .horizontal
        advertiserRow.spacing = 6
        advertiserRow.alignment = .center
        advertiserRow.translatesAutoresizingMaskIntoConstraints = false

        // Body stays bound for impression tracking but collapses when hidden
        // (portrait defaults to `.hidden`).
        let bodyContainer = AutoHidingStackView(arrangedSubviews: [adBodyLabel])
        bodyContainer.axis = .vertical
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [adHeadlineLabel, advertiserRow, bodyContainer])
        textStack.axis = .vertical
        textStack.spacing = configuration.metrics.verticalSpacing
        textStack.alignment = .fill
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let innerRow = UIStackView(arrangedSubviews: [adIconImageView, textStack])
        innerRow.axis = .horizontal
        innerRow.spacing = configuration.metrics.horizontalSpacing
        innerRow.alignment = .top
        innerRow.translatesAutoresizingMaskIntoConstraints = false

        let footer = UIStackView(arrangedSubviews: [innerRow, actionButton])
        footer.axis = .vertical
        footer.spacing = mediaToFooterSpacing
        footer.alignment = .fill
        footer.translatesAutoresizingMaskIntoConstraints = false
        return footer
    }
}

// MARK: - Styling

extension PortraitNativeAdView {
    private func applyStyle() {
        // No fill on the card itself — only the media view is rounded. The
        // footer chrome sits on the app background below the media.
        adHeadlineLabel.textColor = style.text.headline
        adHeadlineLabel.font = style.text.headlineFont.resolved
        adAdvertiserLabel.textColor = style.text.sponsor
        adAdvertiserLabel.font = style.text.sponsorFont.resolved
        adBodyLabel.textColor = style.text.body
        adBodyLabel.font = style.text.bodyFont.resolved

        adAttributionLabel.backgroundColor = style.attribution.background
        adAttributionLabel.textColor = style.attribution.text
        adAttributionLabel.font = style.attribution.font.resolved

        var buttonConfig = actionButton.configuration ?? UIButton.Configuration.plain()
        buttonConfig.contentInsets = NSDirectionalEdgeInsets(style.actionButton.contentInsets)
        buttonConfig.background.backgroundColor = style.actionButton.background
        buttonConfig.baseForegroundColor = style.actionButton.title
        let titleFont = style.actionButton.font.resolved
        buttonConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { container in
            var c = container
            c.font = titleFont
            return c
        }
        actionButton.configuration = buttonConfig
        applyButtonShape()
    }

    private func applyButtonShape() {
        var config = actionButton.configuration ?? UIButton.Configuration.plain()
        switch style.actionButton.shape.mode {
            case let .rect(cornerRadius):
                config.cornerStyle = .fixed
                config.background.cornerRadius = cornerRadius
            case .capsule:
                config.cornerStyle = .capsule
        }
        actionButton.configuration = config
    }
}

// MARK: - Public API

extension PortraitNativeAdView {
    public func configure(with nativeAd: NativeAd) {
        // Content is set synchronously; the card height self-sizes at the
        // SwiftUI layer via `sizeThatFits`. The media box keeps its fixed 9:16
        // ratio regardless of the creative (no per-bind aspect rewrite).
        applyNativeContentUpdate(animated: false) { [self] in
            updateUI(with: nativeAd)
            updateVisibility(for: nativeAd)
            self.nativeAd = nativeAd

            // The Google SDK rebinds the registered `iconView` / media on
            // `nativeAd` assignment and may reset their rendering knobs.
            // Re-assert them so the icon and the media both stay
            // cropped-and-filled inside their slots.
            adIconImageView.contentMode = .scaleAspectFill
            adIconImageView.clipsToBounds = true
            adIconImageView.layer.masksToBounds = true
            adMediaView.contentMode = .scaleAspectFill
        }
    }

    public func calculateTotalHeight(fittingWidth: CGFloat) -> CGFloat {
        let target = CGSize(width: fittingWidth, height: UIView.layoutFittingCompressedSize.height)
        return systemLayoutSizeFitting(
            target,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
    }
}

// MARK: - Private helpers

extension PortraitNativeAdView {
    private func updateUI(with nativeAd: NativeAd) {
        adMediaView.mediaContent = nativeAd.mediaContent
        adIconImageView.image = nativeAd.icon?.image
        adHeadlineLabel.text = nativeAd.headline?.capitalizingFirstLetter()
        adAdvertiserLabel.text = (nativeAd.advertiser ?? nativeAd.store)?.capitalizingFirstLetter()
        adBodyLabel.text = nativeAd.body?.capitalizingFirstLetter()
        actionButton.setTitle(nativeAd.callToAction, for: .normal)
    }

    private func updateViewBindings() {
        self.iconView = adIconImageView
        self.headlineView = adHeadlineLabel
        self.advertiserView = adAdvertiserLabel
        self.bodyView = adBodyLabel
        self.callToActionView = actionButton
        self.mediaView = adMediaView
    }

    private func updateVisibility(for nativeAd: NativeAd) {
        adIconImageView.isHidden = nativeAd.icon?.image == nil
        adHeadlineLabel.isHidden = nativeAd.headline == nil
        adAdvertiserLabel.isHidden = (nativeAd.advertiser ?? nativeAd.store) == nil
        let bodyHidden: Bool
        switch bodyDisplay.mode {
            case .hidden:
                bodyHidden = true
            case .full, .truncated:
                bodyHidden = nativeAd.body == nil
        }
        adBodyLabel.isHidden = bodyHidden
        actionButton.isHidden = nativeAd.callToAction == nil
        // Collapse the media hero when the creative has neither a video nor a
        // meaningful aspect ratio. Video creatives can report `aspectRatio ==
        // 0` until playback metadata arrives, so `hasVideoContent` keeps the
        // slot visible for them.
        let mediaContent = nativeAd.mediaContent
        adMediaView.isHidden = !(mediaContent.hasVideoContent || mediaContent.aspectRatio > 0)
    }
}

#endif

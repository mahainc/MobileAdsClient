//
//  FullScreenNativeAdView.swift
//  MobileAdsClient
//
//  UIKit renderer for a native ad presented as a full-screen modal. Built from
//  `GoogleMobileAds` primitives only — no dependency on `ads_swift`. Intended
//  to back `MobileAdsClient.showNativeFullScreen(_:)` via `UIHostingController`.
//
//  Layout (top → bottom, safe-area-aware):
//    ┌────────────────────────────────────┐
//    │  [×]              [Sponsored]      │   close + ad chip, 16pt above safe-top
//    │                                    │
//    │        MediaView (~55%)            │   aspect-fit media
//    │                                    │
//    │  [Icon 56] Headline                │
//    │            Sponsor                 │
//    │  Body (4 lines max)                │
//    │                                    │
//    │  [    Install Now CTA    ]         │   56pt pill, 16pt above safe-bottom
//    └────────────────────────────────────┘
//

#if canImport(UIKit)
import GoogleMobileAds
import NativeAdClient
import UIKit

public class FullScreenNativeAdView: NativeAdView {

    public typealias Style = NativeAdClient.Configuration.Style

    public var style: Style {
        didSet { applyStyle() }
    }

    private let metrics: NativeAdClient.Configuration.Metrics

    /// Exposed so the SwiftUI wrapper / hosting controller can hook its
    /// `addTarget` to an `onClose` callback.
    public let closeButton: UIButton = {
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "Full Screen Native Close Button"
        button.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        button.imageView?.contentMode = .scaleAspectFit
        return button
    }()

    // MARK: - Subviews

    private lazy var adMediaView: MediaView = {
        let view = MediaView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.layer.cornerRadius = 16
        view.layer.masksToBounds = true
        view.clipsToBounds = true
        return view
    }()

    private lazy var adIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.accessibilityIdentifier = "Full Screen Native Icon"
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        // Corner radius is driven by `metrics.iconCornerRadius` and applied in `setupViews()`.
        imageView.layer.masksToBounds = true
        return imageView
    }()

    private lazy var adHeadlineLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Full Screen Native Headline"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 2
        label.font = .preferredFont(forTextStyle: .title3).withWeight(.bold)
        return label
    }()

    private lazy var adSponsorLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Full Screen Native Sponsor"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .footnote)
        return label
    }()

    private lazy var adBodyLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Full Screen Native Body"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 4
        label.lineBreakMode = .byTruncatingTail
        label.font = .preferredFont(forTextStyle: .callout)
        return label
    }()

    private lazy var adAttributionLabel: PaddedLabel = {
        let label = PaddedLabel(padding: UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6))
        label.accessibilityIdentifier = "Full Screen Native Attribution"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Sponsored"
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.font = .preferredFont(forTextStyle: .caption2).withWeight(.semibold)
        return label
    }()

    private lazy var actionButton: UIButton = {
        let button = UIButton(type: .system)
        button.accessibilityIdentifier = "Full Screen Native CTA"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Install Now", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.layer.masksToBounds = true
        // CTA is not user-interactive at the UIKit level — GoogleMobileAds'
        // NativeAdView proxies taps through `callToActionView` binding.
        button.isUserInteractionEnabled = false
        return button
    }()

    // MARK: - Init

    public init(
        frame: CGRect = .zero,
        style: Style = .fullScreen,
        metrics: NativeAdClient.Configuration.Metrics = .fullScreen
    ) {
        self.style = style
        self.metrics = metrics
        super.init(frame: frame)
        setupViews()
        applyStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        layoutNativeAdGradient()
        applyButtonShape()
        closeButton.layer.cornerRadius = closeButton.bounds.height / 2
    }
}

// MARK: - Setup

extension FullScreenNativeAdView {
    private func setupViews() {
        layer.cornerRadius = metrics.containerCornerRadius
        layer.masksToBounds = metrics.containerCornerRadius > 0

        adIconImageView.layer.cornerRadius = metrics.iconCornerRadius

        let textStack = UIStackView(arrangedSubviews: [adHeadlineLabel, adSponsorLabel])
        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let headerStack = UIStackView(arrangedSubviews: [adIconImageView, textStack])
        headerStack.axis = .horizontal
        headerStack.spacing = metrics.horizontalSpacing
        headerStack.alignment = .center
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let topBar = UIView()
        topBar.translatesAutoresizingMaskIntoConstraints = false
        topBar.addSubview(closeButton)
        topBar.addSubview(adAttributionLabel)

        addSubview(topBar)
        addSubview(adMediaView)
        addSubview(headerStack)
        addSubview(adBodyLabel)
        addSubview(actionButton)

        let guide = safeAreaLayoutGuide

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            topBar.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            topBar.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            topBar.heightAnchor.constraint(equalToConstant: 36),

            closeButton.leadingAnchor.constraint(equalTo: topBar.leadingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),

            adAttributionLabel.trailingAnchor.constraint(equalTo: topBar.trailingAnchor),
            adAttributionLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            adMediaView.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 16),
            adMediaView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 20),
            adMediaView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -20),
            adMediaView.heightAnchor.constraint(equalTo: guide.heightAnchor, multiplier: 0.48),

            headerStack.topAnchor.constraint(equalTo: adMediaView.bottomAnchor, constant: 20),
            headerStack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            headerStack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),

            adIconImageView.widthAnchor.constraint(equalToConstant: metrics.iconSize.width),
            adIconImageView.heightAnchor.constraint(equalToConstant: metrics.iconSize.height),

            adBodyLabel.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 12),
            adBodyLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            adBodyLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            adBodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: actionButton.topAnchor, constant: -16),

            actionButton.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            actionButton.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            actionButton.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -20),
            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: metrics.ctaMinHeight),
        ])
    }

    private func applyStyle() {
        applyBackgroundFill(style.backgrounds.card)
        adHeadlineLabel.textColor = style.text.headline
        adBodyLabel.textColor = style.text.body
        adSponsorLabel.textColor = style.text.sponsor
        adAttributionLabel.backgroundColor = style.attribution.background
        adAttributionLabel.textColor = style.attribution.text
        actionButton.backgroundColor = style.actionButton.background
        actionButton.setTitleColor(style.actionButton.title, for: .normal)
        // `closeButton.text` doubles as the icon tint color for the close button.
        closeButton.tintColor = style.closeButton.text
        closeButton.backgroundColor = style.closeButton.background
        applyButtonShape()
    }

    private func applyButtonShape() {
        switch style.actionButton.shape.mode {
        case let .rect(cornerRadius):
            actionButton.layer.cornerRadius = cornerRadius
        case .capsule:
            let h = actionButton.bounds.height > 0 ? actionButton.bounds.height : metrics.ctaMinHeight
            actionButton.layer.cornerRadius = h / 2
        }
    }
}

// MARK: - Public API

extension FullScreenNativeAdView {
    public func configure(with nativeAd: NativeAd) {
        updateUI(with: nativeAd)
        updateViewBindings()
        updateVisibility(for: nativeAd)

        self.nativeAd = nativeAd
        setNeedsLayout()
        layoutIfNeeded()
    }
}

// MARK: - Private Helpers

extension FullScreenNativeAdView {
    private func updateUI(with nativeAd: NativeAd) {
        adMediaView.mediaContent = nativeAd.mediaContent
        adIconImageView.image = nativeAd.icon?.image
        adHeadlineLabel.text = nativeAd.headline
        adSponsorLabel.text = nativeAd.advertiser
        adBodyLabel.text = nativeAd.body
        actionButton.setTitle(nativeAd.callToAction?.uppercased(), for: .normal)
    }

    private func updateViewBindings() {
        self.mediaView = adMediaView
        self.iconView = adIconImageView
        self.headlineView = adHeadlineLabel
        self.advertiserView = adSponsorLabel
        self.bodyView = adBodyLabel
        self.callToActionView = actionButton
    }

    private func updateVisibility(for nativeAd: NativeAd) {
        let mediaContent = nativeAd.mediaContent
        let hasMedia = mediaContent.hasVideoContent || mediaContent.aspectRatio > 0
        adMediaView.isHidden = !hasMedia
        adIconImageView.isHidden = nativeAd.icon == nil
        adHeadlineLabel.isHidden = nativeAd.headline == nil
        adSponsorLabel.isHidden = nativeAd.advertiser == nil
        adBodyLabel.isHidden = nativeAd.body == nil
        actionButton.isHidden = nativeAd.callToAction == nil
    }
}

// MARK: - Helpers

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: weight]
        ])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
#endif

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
//    │  [×]              [Ad]            │   close + ad chip, 16pt above safe-top
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
            // Title must never be truncated (Google native policy: ≤25 chars, no
            // truncation). Allow it to wrap rather than clip with an ellipsis.
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            return label
        }()

        private lazy var adSponsorLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Full Screen Native Sponsor"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 1
            return label
        }()

        private lazy var adBodyLabel: UILabel = {
            let label = UILabel()
            label.accessibilityIdentifier = "Full Screen Native Body"
            label.translatesAutoresizingMaskIntoConstraints = false
            // Body must not be truncated (Google native policy: ≤90 chars, no
            // truncation). Wrap to as many lines as the text needs.
            label.numberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            return label
        }()

        private lazy var adAttributionLabel: PaddedLabel = {
            let label = PaddedLabel(padding: UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6))
            label.accessibilityIdentifier = "Full Screen Native Attribution"
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "Ad"
            label.textAlignment = .center
            label.layer.cornerRadius = 4
            label.layer.masksToBounds = true
            return label
        }()

        private lazy var actionButton: UIButton = {
            let button = UIButton(type: .system)
            // Use `UIButton.Configuration` (iOS 15+) so `contentInsets` — the
            // modern replacement for the deprecated `contentEdgeInsets` — takes
            // effect. Background, foreground, font, and corner radius are all
            // driven via the same configuration in `applyStyle()` / `applyButtonShape()`.
            var config = UIButton.Configuration.plain()
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14)
            button.configuration = config
            button.accessibilityIdentifier = "Full Screen Native CTA"
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle("Install Now", for: .normal)
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

                adIconImageView.widthAnchor.constraint(equalToConstant: metrics.iconSize.width)
                    .priority(UILayoutPriority(999)),
                adIconImageView.heightAnchor.constraint(equalToConstant: metrics.iconSize.height)
                    .priority(UILayoutPriority(999)),

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
            adHeadlineLabel.font = style.text.headlineFont.resolved
            adBodyLabel.textColor = style.text.body
            adBodyLabel.font = style.text.bodyFont.resolved
            adSponsorLabel.textColor = style.text.sponsor
            adSponsorLabel.font = style.text.sponsorFont.resolved
            adAttributionLabel.backgroundColor = style.attribution.background
            adAttributionLabel.textColor = style.attribution.text
            adAttributionLabel.font = style.attribution.font.resolved
            var buttonConfig = actionButton.configuration ?? UIButton.Configuration.plain()
            buttonConfig.contentInsets = NSDirectionalEdgeInsets(style.actionButton.contentInsets)
            buttonConfig.background.backgroundColor = style.actionButton.background
            buttonConfig.baseForegroundColor = style.actionButton.title
            let titleFont = style.actionButton.font.resolved
            buttonConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { container in
                var updated = container
                updated.font = titleFont
                return updated
            }
            actionButton.configuration = buttonConfig
            // `closeButton.text` doubles as the icon tint color for the close button.
            closeButton.tintColor = style.closeButton.text
            closeButton.backgroundColor = style.closeButton.background
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

    extension FullScreenNativeAdView {
        public func configure(with nativeAd: NativeAd) {
            updateUI(with: nativeAd)
            updateViewBindings()
            updateVisibility(for: nativeAd)

            self.nativeAd = nativeAd

            // The Google SDK rebinds the registered `iconView` when `nativeAd`
            // is assigned and may reset its image-rendering knobs. Re-assert
            // them here so the icon stays cropped-and-filled inside its slot
            // instead of being letterboxed at the asset's native aspect ratio.
            adIconImageView.contentMode = .scaleAspectFill
            adIconImageView.clipsToBounds = true
            adIconImageView.layer.masksToBounds = true

            setNeedsLayout()
            layoutIfNeeded()
        }
    }

    // MARK: - Private Helpers

    extension FullScreenNativeAdView {
        private func updateUI(with nativeAd: NativeAd) {
            adMediaView.mediaContent = nativeAd.mediaContent
            adIconImageView.image = nativeAd.icon?.image
            adHeadlineLabel.text = nativeAd.headline?.capitalizingFirstLetter()
            adSponsorLabel.text = nativeAd.advertiser?.capitalizingFirstLetter()
            adBodyLabel.text = nativeAd.body?.capitalizingFirstLetter()
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
            adIconImageView.isHidden = nativeAd.icon?.image == nil
            adHeadlineLabel.isHidden = nativeAd.headline == nil
            adSponsorLabel.isHidden = nativeAd.advertiser == nil
            adBodyLabel.isHidden = nativeAd.body == nil
            actionButton.isHidden = nativeAd.callToAction == nil
        }
    }

#endif

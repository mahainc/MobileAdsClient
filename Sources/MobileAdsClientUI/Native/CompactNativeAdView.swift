//
//  CompactNativeAdView.swift
//  MobileAdsClient
//

#if canImport(UIKit)
import GoogleMobileAds
import UIKit

public class CompactNativeAdView: NativeAdView {

    public struct Style: Sendable, Equatable {
        /// Shape applied to the CTA button's background.
        /// `.capsule` computes the radius at layout time from the button's
        /// current height, so it stays a pill regardless of Dynamic Type.
        public enum CTAShape: Sendable, Equatable {
            case rect(cornerRadius: CGFloat)
            case capsule
        }

        public var backgroundColor: UIColor
        public var actionButtonBackgroundColor: UIColor
        public var actionButtonTitleColor: UIColor
        public var ctaShape: CTAShape
        public var attributionBackgroundColor: UIColor
        public var attributionTextColor: UIColor
        public var storeBackgroundColor: UIColor
        public var storeTextColor: UIColor
        public var priceBackgroundColor: UIColor
        public var priceTextColor: UIColor

        public init(
            backgroundColor: UIColor = .secondarySystemBackground,
            actionButtonBackgroundColor: UIColor = .systemBlue,
            actionButtonTitleColor: UIColor = .white,
            ctaShape: CTAShape = .rect(cornerRadius: 8),
            attributionBackgroundColor: UIColor = .systemBlue,
            attributionTextColor: UIColor = .white,
            storeBackgroundColor: UIColor = .systemGreen,
            storeTextColor: UIColor = .white,
            priceBackgroundColor: UIColor = .systemGreen,
            priceTextColor: UIColor = .white
        ) {
            self.backgroundColor = backgroundColor
            self.actionButtonBackgroundColor = actionButtonBackgroundColor
            self.actionButtonTitleColor = actionButtonTitleColor
            self.ctaShape = ctaShape
            self.attributionBackgroundColor = attributionBackgroundColor
            self.attributionTextColor = attributionTextColor
            self.storeBackgroundColor = storeBackgroundColor
            self.storeTextColor = storeTextColor
            self.priceBackgroundColor = priceBackgroundColor
            self.priceTextColor = priceTextColor
        }

        public static let `default`: Style = .init()
    }

    public var style: Style {
        didSet { applyStyle() }
    }

    private let fixedHeight: CGFloat = 300
    private let defaultSpacing: CGFloat = 8
    private let containerPadding: CGFloat = 10

    private lazy var adContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        return view
    }()

    private lazy var adMediaView: MediaView = {
        let view = MediaView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFill
        view.layer.cornerRadius = 8
        view.layer.masksToBounds = true
        view.clipsToBounds = true
        view.setContentHuggingPriority(.defaultHigh, for: .vertical)
        return view
    }()

    private lazy var adIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.accessibilityIdentifier = "Ad Icon Image View"
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 8
        imageView.layer.masksToBounds = true
        return imageView
    }()

    private lazy var adHeadlineLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Ad Headline Label"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .label
        return label
    }()

    private lazy var adSponsorLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Ad Sponsor Label"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.textColor = .secondaryLabel
        label.font = Self.sponsorFont
        return label
    }()

    private lazy var adAttributionLabel: PaddedLabel = {
        let label = PaddedLabel(padding: UIEdgeInsets(top: 3, left: 5, bottom: 3, right: 5))
        label.accessibilityIdentifier = "Ad Attribution Label"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Sponsored"
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.font = .preferredFont(forTextStyle: .caption2)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private lazy var adRatingImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.accessibilityIdentifier = "Ad Rating Image View"
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .left
        return imageView
    }()

    private lazy var adBodyLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Ad Body Label"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.font = .preferredFont(forTextStyle: .footnote)
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var adStoreLabel: PaddedLabel = {
        let label = PaddedLabel(padding: UIEdgeInsets(top: 3, left: 5, bottom: 3, right: 5))
        label.accessibilityIdentifier = "Ad Store Label"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.textAlignment = .center
        label.font = Self.chipFont
        label.text = "App Store"
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        // Low hugging lets the parent stack's `.fill` alignment stretch the
        // chip to the stack's width (= widest chip's intrinsic width). High
        // compression resistance keeps the text from being clipped narrower
        // than it needs.
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private lazy var adPriceLabel: PaddedLabel = {
        let label = PaddedLabel(padding: UIEdgeInsets(top: 3, left: 5, bottom: 3, right: 5))
        label.accessibilityIdentifier = "Ad Price Label"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.textAlignment = .center
        label.font = Self.chipFont
        label.text = "Free"
        label.layer.cornerRadius = 4
        label.layer.masksToBounds = true
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    /// Caption1-scaled semibold system font. Shared by the store + price chips
    /// so they render at the same point size and weight, and `UIFontMetrics`
    /// keeps them matched as Dynamic Type scales.
    private static let chipFont: UIFont = {
        let base = UIFont.systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption1).pointSize,
            weight: .semibold
        )
        return UIFontMetrics(forTextStyle: .caption1).scaledFont(for: base)
    }()

    /// Caption2-scaled semibold — smaller than `chipFont` so the sponsor line
    /// reads as tertiary metadata under the headline while still being
    /// emphasized against the body copy.
    private static let sponsorFont: UIFont = {
        let base = UIFont.systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .caption2).pointSize,
            weight: .semibold
        )
        return UIFontMetrics(forTextStyle: .caption2).scaledFont(for: base)
    }()

    private lazy var actionButton: UIButton = {
        let button = UIButton()
        button.accessibilityIdentifier = "Ad Action Button"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Install Now", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        // Corner radius is driven by `Style.ctaShape` via `applyCTAShape()` /
        // `layoutSubviews`, not a fixed value here.
        button.layer.masksToBounds = true
        button.isUserInteractionEnabled = false
        return button
    }()

    public init(frame: CGRect = .zero, style: Style = .default) {
        self.style = style
        super.init(frame: frame)
        setupViews()
        applyStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: fixedHeight)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // Capsule shape depends on the button's laid-out height, which is only
        // known after Auto Layout resolves. Re-apply every pass; no-op for rect.
        if case .capsule = style.ctaShape {
            applyCTAShape()
        }
    }
}

// MARK: - Setup

extension CompactNativeAdView {
    private func setupViews() {
        layer.cornerRadius = 12
        layer.masksToBounds = true
        clipsToBounds = true

        let attributionRow = UIStackView()
        attributionRow.axis = .horizontal
        attributionRow.spacing = 8
        attributionRow.alignment = .center
        attributionRow.distribution = .fill
        attributionRow.translatesAutoresizingMaskIntoConstraints = false
        attributionRow.addArrangedSubview(adAttributionLabel)
        attributionRow.addArrangedSubview(adRatingImageView)

        let headlineTextStack = AutoHidingStackView()
        headlineTextStack.accessibilityIdentifier = "Headline Text Stack"
        headlineTextStack.axis = .vertical
        headlineTextStack.spacing = 4
        headlineTextStack.alignment = .leading
        headlineTextStack.distribution = .fill
        headlineTextStack.translatesAutoresizingMaskIntoConstraints = false
        headlineTextStack.addArrangedSubview(adHeadlineLabel)
        headlineTextStack.addArrangedSubview(adSponsorLabel)
        headlineTextStack.addArrangedSubview(attributionRow)

        let headlineStack = AutoHidingStackView()
        headlineStack.accessibilityIdentifier = "Headline Stack"
        headlineStack.axis = .horizontal
        headlineStack.spacing = 12
        headlineStack.alignment = .center
        headlineStack.distribution = .fill
        headlineStack.translatesAutoresizingMaskIntoConstraints = false
        headlineStack.addArrangedSubview(adIconImageView)
        headlineStack.addArrangedSubview(headlineTextStack)

        let priceStack = AutoHidingStackView()
        priceStack.accessibilityIdentifier = "Price Stack"
        priceStack.axis = .vertical
        priceStack.spacing = 4
        // `.fill` stretches both chips to the stack's width, which the stack
        // hugs to the wider chip — so "App Store" and "Free" render at
        // matching width even though their text is different.
        priceStack.alignment = .fill
        priceStack.distribution = .fill
        priceStack.translatesAutoresizingMaskIntoConstraints = false
        priceStack.setContentHuggingPriority(.required, for: .horizontal)
        priceStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        priceStack.addArrangedSubview(adStoreLabel)
        priceStack.addArrangedSubview(adPriceLabel)

        adBodyLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        adBodyLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let middleStack = AutoHidingStackView()
        middleStack.accessibilityIdentifier = "Middle Stack"
        middleStack.axis = .horizontal
        middleStack.spacing = 12
        middleStack.alignment = .center
        middleStack.distribution = .fill
        middleStack.translatesAutoresizingMaskIntoConstraints = false
        middleStack.addArrangedSubview(adBodyLabel)
        middleStack.addArrangedSubview(priceStack)

        adContainerView.addSubview(adMediaView)
        adContainerView.addSubview(headlineStack)
        adContainerView.addSubview(middleStack)
        adContainerView.addSubview(actionButton)

        addSubview(adContainerView)

        let mediaHeightConstraint = adMediaView.heightAnchor.constraint(equalToConstant: 160)
        mediaHeightConstraint.priority = .required

        NSLayoutConstraint.activate([
            adContainerView.topAnchor.constraint(equalTo: topAnchor, constant: containerPadding),
            adContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            adContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            adContainerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -containerPadding),

            adMediaView.topAnchor.constraint(equalTo: adContainerView.topAnchor),
            adMediaView.leadingAnchor.constraint(equalTo: adContainerView.leadingAnchor),
            adMediaView.trailingAnchor.constraint(equalTo: adContainerView.trailingAnchor),
            mediaHeightConstraint,

            headlineStack.topAnchor.constraint(equalTo: adMediaView.bottomAnchor, constant: defaultSpacing),
            headlineStack.leadingAnchor.constraint(equalTo: adContainerView.leadingAnchor),
            headlineStack.trailingAnchor.constraint(equalTo: adContainerView.trailingAnchor),

            middleStack.topAnchor.constraint(equalTo: headlineStack.bottomAnchor, constant: defaultSpacing),
            middleStack.leadingAnchor.constraint(equalTo: adContainerView.leadingAnchor),
            middleStack.trailingAnchor.constraint(equalTo: adContainerView.trailingAnchor),
            middleStack.bottomAnchor.constraint(lessThanOrEqualTo: actionButton.topAnchor, constant: -defaultSpacing),

            actionButton.leadingAnchor.constraint(equalTo: adContainerView.leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: adContainerView.trailingAnchor),
            actionButton.bottomAnchor.constraint(equalTo: adContainerView.bottomAnchor),
            actionButton.heightAnchor.constraint(equalToConstant: 40),

            adIconImageView.widthAnchor.constraint(equalToConstant: 36),
            adIconImageView.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    private func applyStyle() {
        self.backgroundColor = style.backgroundColor

        actionButton.backgroundColor = style.actionButtonBackgroundColor
        actionButton.setTitleColor(style.actionButtonTitleColor, for: .normal)
        applyCTAShape()

        adAttributionLabel.backgroundColor = style.attributionBackgroundColor
        adAttributionLabel.textColor = style.attributionTextColor

        adStoreLabel.backgroundColor = style.storeBackgroundColor
        adStoreLabel.textColor = style.storeTextColor

        adPriceLabel.backgroundColor = style.priceBackgroundColor
        adPriceLabel.textColor = style.priceTextColor
    }

    private func applyCTAShape() {
        switch style.ctaShape {
        case let .rect(cornerRadius):
            actionButton.layer.cornerRadius = cornerRadius
        case .capsule:
            // Height is 0 during first applyStyle() (pre-layout); `layoutSubviews`
            // re-applies once the frame settles. Fall back to half the constraint
            // height (40) so the first layout pass is already round.
            let h = actionButton.bounds.height > 0 ? actionButton.bounds.height : 40
            actionButton.layer.cornerRadius = h / 2
        }
    }
}

// MARK: - Public API

extension CompactNativeAdView {
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

extension CompactNativeAdView {
    private func updateUI(with nativeAd: NativeAd) {
        adMediaView.mediaContent = nativeAd.mediaContent
        adIconImageView.image = nativeAd.icon?.image
        adHeadlineLabel.text = nativeAd.headline?.capitalized
        adSponsorLabel.text = nativeAd.advertiser
        adRatingImageView.image = imageOfStars(from: nativeAd.starRating)
        adBodyLabel.text = nativeAd.body
        adStoreLabel.text = nativeAd.store?.capitalized
        adPriceLabel.text = nativeAd.price?.capitalized
        actionButton.setTitle(nativeAd.callToAction?.uppercased(), for: .normal)
    }

    private func updateViewBindings() {
        self.mediaView = adMediaView
        self.iconView = adIconImageView
        self.headlineView = adHeadlineLabel
        self.advertiserView = adSponsorLabel
        self.starRatingView = adRatingImageView
        self.storeView = adStoreLabel
        self.priceView = adPriceLabel
        self.callToActionView = actionButton
        self.bodyView = adBodyLabel
    }

    private func updateVisibility(for nativeAd: NativeAd) {
        // `MediaView` shows image ads via the SDK once `mediaContent` is set.
        // Hide the slot when the creative has neither a video nor a meaningful
        // aspect ratio (rare; most served creatives include at least one).
        let mediaContent = nativeAd.mediaContent
        let hasMedia = mediaContent.hasVideoContent || mediaContent.aspectRatio > 0
        adMediaView.isHidden = !hasMedia
        adIconImageView.isHidden = nativeAd.icon == nil
        adHeadlineLabel.isHidden = nativeAd.headline == nil
        adSponsorLabel.isHidden = nativeAd.advertiser == nil
        adRatingImageView.isHidden = nativeAd.starRating == nil
        adBodyLabel.isHidden = nativeAd.body == nil
        adStoreLabel.isHidden = nativeAd.store == nil
        adPriceLabel.isHidden = nativeAd.price == nil
        actionButton.isHidden = nativeAd.callToAction == nil
    }

    private func imageOfStars(from starRating: NSDecimalNumber?) -> UIImage? {
        guard let rating = starRating?.doubleValue else {
            return nil
        }

        if rating >= 5 {
            return UIImage.fromSPM(named: "stars_5")
        } else if rating >= 4.5 {
            return UIImage.fromSPM(named: "stars_4_5")
        } else if rating >= 4 {
            return UIImage.fromSPM(named: "stars_4")
        } else if rating >= 3.5 {
            return UIImage.fromSPM(named: "stars_3_5")
        } else {
            return nil
        }
    }
}
#endif

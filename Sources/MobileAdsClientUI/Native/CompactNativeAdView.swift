//
//  CompactNativeAdView.swift
//  MobileAdsClient
//

#if canImport(UIKit)
import GoogleMobileAds
import UIKit

public class CompactNativeAdView: NativeAdView {

    public struct Style: Sendable, Equatable {
        public var actionButtonBackgroundColor: UIColor
        public var actionButtonTitleColor: UIColor
        public var attributionBackgroundColor: UIColor
        public var attributionTextColor: UIColor
        public var storeBackgroundColor: UIColor
        public var storeTextColor: UIColor
        public var priceBackgroundColor: UIColor
        public var priceTextColor: UIColor

        public init(
            actionButtonBackgroundColor: UIColor = .systemBlue,
            actionButtonTitleColor: UIColor = .white,
            attributionBackgroundColor: UIColor = .systemBlue,
            attributionTextColor: UIColor = .white,
            storeBackgroundColor: UIColor = .systemGreen,
            storeTextColor: UIColor = .white,
            priceBackgroundColor: UIColor = .systemGreen,
            priceTextColor: UIColor = .white
        ) {
            self.actionButtonBackgroundColor = actionButtonBackgroundColor
            self.actionButtonTitleColor = actionButtonTitleColor
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
    private let defaultSpacing: CGFloat = 12

    private lazy var adContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
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
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .label
        return label
    }()

    private lazy var adSponsorLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Ad Sponsor Label"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.textColor = .secondaryLabel
        label.font = .preferredFont(forTextStyle: .subheadline)
        return label
    }()

    private lazy var adAttributionLabel: PaddedLabel = {
        let label = PaddedLabel(padding: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6))
        label.accessibilityIdentifier = "Ad Attribution Label"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Sponsored"
        label.textAlignment = .center
        label.layer.cornerRadius = 5
        label.layer.masksToBounds = true
        label.font = .preferredFont(forTextStyle: .footnote)
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
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        label.font = .preferredFont(forTextStyle: .callout)
        label.textAlignment = .left
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var adStoreLabel: PaddedLabel = {
        let label = PaddedLabel(padding: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6))
        label.accessibilityIdentifier = "Ad Store Label"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.text = "App Store"
        label.layer.cornerRadius = 5
        label.layer.masksToBounds = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private lazy var adPriceLabel: PaddedLabel = {
        let label = PaddedLabel(padding: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6))
        label.accessibilityIdentifier = "Ad Price Label"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.textAlignment = .center
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.text = "Free"
        label.layer.cornerRadius = 5
        label.layer.masksToBounds = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private lazy var actionButton: UIButton = {
        let button = UIButton()
        button.accessibilityIdentifier = "Ad Action Button"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Install Now", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.layer.cornerRadius = 8
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

        let storeSpacer = UIView()
        storeSpacer.translatesAutoresizingMaskIntoConstraints = false
        storeSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        storeSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let storeStack = UIStackView()
        storeStack.accessibilityIdentifier = "Store Stack"
        storeStack.axis = .horizontal
        storeStack.spacing = 8
        storeStack.alignment = .center
        storeStack.distribution = .fill
        storeStack.translatesAutoresizingMaskIntoConstraints = false
        storeStack.addArrangedSubview(adStoreLabel)
        storeStack.addArrangedSubview(adPriceLabel)
        storeStack.addArrangedSubview(storeSpacer)

        let middleStack = AutoHidingStackView()
        middleStack.accessibilityIdentifier = "Middle Stack"
        middleStack.axis = .vertical
        middleStack.spacing = 8
        middleStack.alignment = .fill
        middleStack.distribution = .fill
        middleStack.translatesAutoresizingMaskIntoConstraints = false
        middleStack.addArrangedSubview(adBodyLabel)
        middleStack.addArrangedSubview(storeStack)

        adContainerView.addSubview(headlineStack)
        adContainerView.addSubview(middleStack)
        adContainerView.addSubview(actionButton)

        addSubview(adContainerView)

        NSLayoutConstraint.activate([
            adContainerView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            adContainerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            adContainerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            adContainerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            headlineStack.topAnchor.constraint(equalTo: adContainerView.topAnchor),
            headlineStack.leadingAnchor.constraint(equalTo: adContainerView.leadingAnchor),
            headlineStack.trailingAnchor.constraint(equalTo: adContainerView.trailingAnchor),

            middleStack.topAnchor.constraint(equalTo: headlineStack.bottomAnchor, constant: defaultSpacing),
            middleStack.leadingAnchor.constraint(equalTo: adContainerView.leadingAnchor),
            middleStack.trailingAnchor.constraint(equalTo: adContainerView.trailingAnchor),
            middleStack.bottomAnchor.constraint(lessThanOrEqualTo: actionButton.topAnchor, constant: -defaultSpacing),

            actionButton.leadingAnchor.constraint(equalTo: adContainerView.leadingAnchor),
            actionButton.trailingAnchor.constraint(equalTo: adContainerView.trailingAnchor),
            actionButton.bottomAnchor.constraint(equalTo: adContainerView.bottomAnchor),
            actionButton.heightAnchor.constraint(equalToConstant: 44),

            adIconImageView.widthAnchor.constraint(equalToConstant: 60),
            adIconImageView.heightAnchor.constraint(equalToConstant: 60),
        ])
    }

    private func applyStyle() {
        actionButton.backgroundColor = style.actionButtonBackgroundColor
        actionButton.setTitleColor(style.actionButtonTitleColor, for: .normal)

        adAttributionLabel.backgroundColor = style.attributionBackgroundColor
        adAttributionLabel.textColor = style.attributionTextColor

        adStoreLabel.backgroundColor = style.storeBackgroundColor
        adStoreLabel.textColor = style.storeTextColor

        adPriceLabel.backgroundColor = style.priceBackgroundColor
        adPriceLabel.textColor = style.priceTextColor
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

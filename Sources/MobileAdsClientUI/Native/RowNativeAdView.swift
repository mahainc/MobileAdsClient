//
//  RowNativeAdView.swift
//  MobileAdsClient
//
//  Row-shaped native ad renderer suitable for in-feed / list insertion.
//  Two layouts (`.inline` = CTA on the right, `.stacked` = CTA below) share
//  the same NativeAd bindings and `NativeAdClient.AdStyle` theming.
//

#if canImport(UIKit)
import GoogleMobileAds
import NativeAdClient
import UIKit

public class RowNativeAdView: NativeAdView {

    public enum Layout: Sendable, Equatable {
        case inline
        case stacked
    }

    public typealias Style = NativeAdClient.AdStyle

    public let layout: Layout
    public var style: Style {
        didSet { applyStyle() }
    }

    // MARK: - Subviews

    private lazy var adIconImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.accessibilityIdentifier = "Row Native Icon"
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.layer.cornerRadius = 10
        imageView.layer.masksToBounds = true
        imageView.setContentHuggingPriority(.required, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.required, for: .horizontal)
        return imageView
    }()

    private lazy var adHeadlineLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Row Native Headline"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        return label
    }()

    private lazy var adAdvertiserLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Row Native Advertiser"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.font = .preferredFont(forTextStyle: .caption1)
        return label
    }()

    private lazy var adAttributionLabel: PaddedLabel = {
        let label = PaddedLabel(padding: UIEdgeInsets(top: 2, left: 5, bottom: 2, right: 5))
        label.accessibilityIdentifier = "Row Native Attribution"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Sponsored"
        label.textAlignment = .center
        label.layer.cornerRadius = 3
        label.layer.masksToBounds = true
        label.font = .preferredFont(forTextStyle: .caption2).withWeight(.semibold)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private lazy var adBodyLabel: UILabel = {
        let label = UILabel()
        label.accessibilityIdentifier = "Row Native Body"
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        label.lineBreakMode = .byTruncatingTail
        label.font = .preferredFont(forTextStyle: .footnote)
        return label
    }()

    private lazy var actionButton: UIButton = {
        let button = UIButton(type: .system)
        // On iOS 15+, `UIButton(type: .system)` ships with a default
        // `UIButton.Configuration`, which makes the legacy `contentEdgeInsets`
        // a no-op and collapses the button to text-only height. Clear it so
        // the legacy padding API below takes effect.
        button.configuration = nil
        button.accessibilityIdentifier = "Row Native CTA"
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Install", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline).withWeight(.semibold)
        // Corner radius is driven by `style.buttonShape` via `applyButtonShape()`.
        button.layer.masksToBounds = true
        // CTA is not user-interactive at the UIKit level — GoogleMobileAds'
        // NativeAdView proxies taps through `callToActionView` binding.
        button.isUserInteractionEnabled = false
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }()

    // MARK: - Init

    public init(frame: CGRect = .zero, style: Style = .row, layout: Layout = .inline) {
        self.layout = layout
        self.style = style
        super.init(frame: frame)
        setupViews()
        updateViewBindings()
        applyStyle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        if case .capsule = style.buttonShape {
            applyButtonShape()
        }
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Dynamic Type changes invalidate the intrinsic content; force a re-layout
        // so the next `updateUIView` pass measures and dispatches a fresh height.
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            setNeedsLayout()
        }
    }
}

// MARK: - Setup

extension RowNativeAdView {
    private func setupViews() {
        layer.cornerRadius = 12
        layer.masksToBounds = true

        let advertiserRow = UIStackView(arrangedSubviews: [adAdvertiserLabel, adAttributionLabel])
        advertiserRow.axis = .horizontal
        advertiserRow.spacing = 6
        advertiserRow.alignment = .center
        advertiserRow.translatesAutoresizingMaskIntoConstraints = false

        let bodyContainer = AutoHidingStackView(arrangedSubviews: [adBodyLabel])
        bodyContainer.axis = .vertical
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [adHeadlineLabel, advertiserRow, bodyContainer])
        textStack.axis = .vertical
        textStack.spacing = 4
        // `.fill` (vs `.leading`) lets multi-line `adBodyLabel` wrap to the
        // stack's full width and, in `.stacked`, lets the appended CTA stretch.
        textStack.alignment = .fill
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        switch layout {
        case .inline:
            setupInlineLayout(textStack: textStack)
        case .stacked:
            setupStackedLayout(textStack: textStack)
        }
    }

    private func setupInlineLayout(textStack: UIStackView) {
        let row = UIStackView(arrangedSubviews: [adIconImageView, textStack, actionButton])
        row.axis = .horizontal
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            adIconImageView.widthAnchor.constraint(equalToConstant: 56),
            adIconImageView.heightAnchor.constraint(equalToConstant: 56),

            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])
    }

    private func setupStackedLayout(textStack: UIStackView) {
        // CTA lives inside the inner text column and must stretch to its full
        // width — lower the button's horizontal hugging so `.fill` alignment wins.
        actionButton.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Append CTA below body inside the inner VStack and give it a little
        // breathing room. When `bodyContainer` is hidden (no body), UIStackView
        // ignores this custom spacing and falls back to the stack's default.
        let tailBeforeCTA = textStack.arrangedSubviews.last
        textStack.addArrangedSubview(actionButton)
        if let tail = tailBeforeCTA {
            textStack.setCustomSpacing(10, after: tail)
        }

        let outer = UIStackView(arrangedSubviews: [adIconImageView, textStack])
        outer.axis = .horizontal
        outer.spacing = 12
        outer.alignment = .top
        outer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outer)

        NSLayoutConstraint.activate([
            outer.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            adIconImageView.widthAnchor.constraint(equalToConstant: 64),
            adIconImageView.heightAnchor.constraint(equalToConstant: 64),

            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }
}

// MARK: - Styling

extension RowNativeAdView {
    private func applyStyle() {
        backgroundColor = style.backgroundColor

        adHeadlineLabel.textColor = style.headlineTextColor
        adAdvertiserLabel.textColor = style.sponsorTextColor
        adBodyLabel.textColor = style.bodyTextColor

        adAttributionLabel.backgroundColor = style.attributionBackgroundColor
        adAttributionLabel.textColor = style.attributionTextColor

        actionButton.backgroundColor = style.actionButtonBackgroundColor
        actionButton.setTitleColor(style.actionButtonTitleColor, for: .normal)
        applyButtonShape()
    }

    private func applyButtonShape() {
        switch style.buttonShape {
        case let .rect(cornerRadius):
            actionButton.layer.cornerRadius = cornerRadius
        case .capsule:
            // Height is 0 during first applyStyle() (pre-layout); `layoutSubviews`
            // re-applies once the frame settles.
            let fallback: CGFloat = layout == .stacked ? 44 : 36
            let h = actionButton.bounds.height > 0 ? actionButton.bounds.height : fallback
            actionButton.layer.cornerRadius = h / 2
        }
    }
}

// MARK: - Public API

extension RowNativeAdView {
    public func configure(with nativeAd: NativeAd) {
        updateUI(with: nativeAd)
        updateVisibility(for: nativeAd)
        self.nativeAd = nativeAd
        setNeedsLayout()
        layoutIfNeeded()
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

extension RowNativeAdView {
    private func updateUI(with nativeAd: NativeAd) {
        adIconImageView.image = nativeAd.icon?.image
        adHeadlineLabel.text = nativeAd.headline
        adAdvertiserLabel.text = nativeAd.advertiser ?? nativeAd.store
        adBodyLabel.text = nativeAd.body
        actionButton.setTitle(nativeAd.callToAction, for: .normal)
    }

    private func updateViewBindings() {
        self.iconView = adIconImageView
        self.headlineView = adHeadlineLabel
        self.advertiserView = adAdvertiserLabel
        self.bodyView = adBodyLabel
        self.callToActionView = actionButton
    }

    private func updateVisibility(for nativeAd: NativeAd) {
        adIconImageView.isHidden = nativeAd.icon == nil
        adHeadlineLabel.isHidden = nativeAd.headline == nil
        adAdvertiserLabel.isHidden = (nativeAd.advertiser ?? nativeAd.store) == nil
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

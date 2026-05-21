//
//  NativeAdvancedView.swift
//  MobileAdsClient
//
//  Created by Thanh Hai Khong on 24/6/25.
//

#if canImport(UIKit)
import GoogleMobileAds
import NativeAdClient
import UIKit

public class NativeAdvancedView: NativeAdView {

	public typealias Style = NativeAdClient.Configuration.Style

	public var style: Style {
		didSet { applyStyle() }
	}

	private let metrics: NativeAdClient.Configuration.Metrics

	public init(
		frame: CGRect = .zero,
		style: Style = .advanced,
		metrics: NativeAdClient.Configuration.Metrics = .advanced
	) {
		self.style = style
		self.metrics = metrics
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
		if case .capsule = style.buttonShape.mode {
			applyButtonShape()
		}
	}

	// MARK: - SetupViews

	private lazy var contentView: UIView = {
		let view = UIView()
		view.translatesAutoresizingMaskIntoConstraints = false
		view.accessibilityIdentifier = "Ad Content View"
		view.layer.cornerRadius = 5
		view.layer.masksToBounds = true
		return view
	}()

	public lazy var containerView: UIImageView = {
		let imageView = UIImageView()
		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.accessibilityIdentifier = "Ad Container View"
		imageView.contentMode = .scaleAspectFill
		imageView.layer.cornerRadius = 5
		imageView.layer.masksToBounds = true
		imageView.image = UIImage.fromSPM(named: "placeholder_image")

		return imageView
	}()

	public lazy var headlineLabel: UILabel = {
		let label = UILabel()
		label.accessibilityIdentifier = "Ad Headline Label"
		label.translatesAutoresizingMaskIntoConstraints = false
		label.numberOfLines = 0
		label.font = .boldSystemFont(ofSize: 16)
		label.text = "Ad Headline"

		return label
	}()

	public lazy var sponsorLabel: UILabel = {
		let label = UILabel()
		label.accessibilityIdentifier = "Ad Sponsor Label"
		label.translatesAutoresizingMaskIntoConstraints = false
		label.numberOfLines = 0
		label.text = "Ad Sponsor"
		label.font = .systemFont(ofSize: 14, weight: .medium)

		return label
	}()

	public lazy var attributionLabel: PaddedLabel = {
		let label = PaddedLabel(padding: UIEdgeInsets(top: 2, left: 6, bottom: 2, right: 6))
		label.accessibilityIdentifier = "Ad Attribution Label"
		label.translatesAutoresizingMaskIntoConstraints = false
		label.text = "Sponsored"
		label.textAlignment = .center
		label.layer.cornerRadius = 4
		label.layer.masksToBounds = true
		// Border width is structural; color tracks `style.attributionTextColor`
		// via `applyStyle()` so outlined-chip presets (e.g. `.advanced`) work.
		label.layer.borderWidth = 1.4
		label.font = .systemFont(ofSize: 13, weight: .semibold)

		return label
	}()
	
	public lazy var iconImageView: UIImageView = {
		let imageView = UIImageView()
		imageView.accessibilityIdentifier = "Ad Icon Image View"
		imageView.image = UIImage.fromSPM(named: "placeholder_image")
		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.contentMode = .scaleAspectFill
		// Corner radius is driven by `metrics.iconCornerRadius` and applied in `setupViews()`.
		imageView.layer.masksToBounds = true

		return imageView
	}()
	
	public lazy var ratingImageView: UIImageView = {
		let imageView = UIImageView()
		imageView.accessibilityIdentifier = "Ad Rating Image View"
		imageView.translatesAutoresizingMaskIntoConstraints = false
		imageView.contentMode = .left
		
		return imageView
	}()
	
	public lazy var actionButton: UIButton = {
		let button = UIButton()
		button.accessibilityIdentifier = "Ad Action Button"
		button.translatesAutoresizingMaskIntoConstraints = false
		button.setTitle("Install Now", for: .normal)
		button.titleLabel?.font = .boldSystemFont(ofSize: 15)
		// Corner radius is driven by `style.buttonShape` via `applyButtonShape()`.
		button.layer.masksToBounds = true
		button.isUserInteractionEnabled = false

		return button
	}()

	public lazy var bodyLabel: UILabel = {
		let label = UILabel()
		label.accessibilityIdentifier = "Ad Body Label"
		label.translatesAutoresizingMaskIntoConstraints = false
		label.numberOfLines = 0
		label.font = .systemFont(ofSize: 13, weight: .regular)
		label.textAlignment = .left

		return label
	}()

	public lazy var storeLabel: PaddedLabel = {
		let label = PaddedLabel(padding: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6))
		label.accessibilityIdentifier = "Ad Store Label"
		label.translatesAutoresizingMaskIntoConstraints = false
		label.numberOfLines = 0
		label.textAlignment = .center
		label.font = .boldSystemFont(ofSize: 15)
		label.text = "App Store"
		label.layer.cornerRadius = 5
		label.layer.masksToBounds = true

		return label
	}()

	public lazy var priceLabel: PaddedLabel = {
		let label = PaddedLabel(padding: UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6))
		label.accessibilityIdentifier = "Ad Price Label"
		label.translatesAutoresizingMaskIntoConstraints = false
		label.numberOfLines = 0
		label.textAlignment = .center
		label.font = .boldSystemFont(ofSize: 15)
		label.text = "Free"
		label.layer.cornerRadius = 5
		label.layer.masksToBounds = true

		return label
	}()
	
	public lazy var mediaContentView: MediaView = {
		let view = MediaView()
		view.translatesAutoresizingMaskIntoConstraints = false
		view.contentMode = .scaleAspectFill
		view.backgroundColor = .systemGray6
		view.layer.cornerRadius = 5
		view.layer.masksToBounds = true
		
		return view
	}()
}

// MARK: - Supporting Methods

extension NativeAdvancedView {
	
	private func setupViews() {
		addBlur(style: .dark)

		iconImageView.layer.cornerRadius = metrics.iconCornerRadius

		let storeStack = AutoHidingStackView(arrangedSubviews: [actionButton, storeLabel, priceLabel])
		storeStack.accessibilityIdentifier = "Store Stack"
		storeStack.axis = .horizontal
		storeStack.spacing = metrics.horizontalSpacing
		storeStack.alignment = .fill
		storeStack.distribution = .fillEqually
		storeStack.translatesAutoresizingMaskIntoConstraints = false
		
		let attributionStack = AutoHidingStackView(arrangedSubviews: [attributionLabel, sponsorLabel])
		attributionStack.accessibilityIdentifier = "Attribution Stack"
		attributionStack.axis = .horizontal
		attributionStack.spacing = 8
		attributionStack.alignment = .center
		attributionStack.distribution = .fill
		attributionStack.translatesAutoresizingMaskIntoConstraints = false
		
		let labelStack = AutoHidingStackView(arrangedSubviews: [headlineLabel, attributionStack, ratingImageView])
		labelStack.translatesAutoresizingMaskIntoConstraints = false
		labelStack.accessibilityIdentifier = "Label Stack"
		labelStack.axis = .vertical
		labelStack.spacing = metrics.verticalSpacing
		labelStack.alignment = .leading
		labelStack.distribution = .fillProportionally
		
		let headerStack = AutoHidingStackView(arrangedSubviews: [iconImageView, labelStack])
		headerStack.translatesAutoresizingMaskIntoConstraints = false
		headerStack.accessibilityIdentifier = "Header Stack"
		headerStack.axis = .horizontal
		headerStack.spacing = metrics.horizontalSpacing
		headerStack.alignment = .center
		headerStack.distribution = .fill
		
		let stackView = AutoHidingStackView(arrangedSubviews: [containerView, headerStack, bodyLabel, storeStack])
		stackView.translatesAutoresizingMaskIntoConstraints = false
		stackView.accessibilityIdentifier = "Main Stack"
		stackView.axis = .vertical
		stackView.spacing = metrics.verticalSpacing
		stackView.alignment = .fill
		stackView.distribution = .fill
		
		/*
		ratingImageView.image = UIImage.fromSPM(named: "stars_5")
		headlineLabel.text = "The new era of fashion is here"
		sponsorLabel.text = "Polo Ralph Lauren"
		bodyLabel.text = "This is a sample body text for the ad. It provides additional information about the product or service being advertised."
		*/
		
		containerView.setContentHuggingPriority(.defaultHigh, for: .vertical)
		containerView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
		
		bodyLabel.setContentHuggingPriority(.required, for: .vertical)
		bodyLabel.setContentCompressionResistancePriority(.required, for: .vertical)
		
		headlineLabel.setContentHuggingPriority(.required, for: .vertical)
				
		containerView.addSubview(mediaContentView)
		contentView.addSubview(stackView)
		
		addSubview(contentView)
		
		NSLayoutConstraint.activate([
			contentView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
			contentView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
			contentView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
			contentView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
			
			stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
			stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
			stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
			stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
			
			containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
			
			mediaContentView.topAnchor.constraint(equalTo: containerView.topAnchor),
			mediaContentView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
			mediaContentView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
			mediaContentView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
			
			storeStack.heightAnchor.constraint(equalToConstant: metrics.ctaMinHeight),

			iconImageView.widthAnchor.constraint(equalToConstant: metrics.iconSize.width),
			iconImageView.heightAnchor.constraint(equalToConstant: metrics.iconSize.height),
		])
	}
	
	private func updateUI(with nativeAd: NativeAd) {
		let viewsToAnimate: [UIView] = [
			iconImageView,
			headlineLabel,
			ratingImageView,
			sponsorLabel,
			storeLabel,
			priceLabel,
			bodyLabel,
			actionButton
		]
		
		for view in viewsToAnimate {
			UIView.transition(with: view, duration: 0.3, options: .transitionFlipFromLeft) {
				DispatchQueue.main.async {
					switch view {
					case self.iconImageView:
						self.iconImageView.image = nativeAd.icon?.image
						
					case self.headlineLabel:
						self.headlineLabel.text = nativeAd.headline?.capitalized
						
					case self.ratingImageView:
						self.ratingImageView.image = self.imageOfStars(from: nativeAd.starRating)
						
					case self.sponsorLabel:
						self.sponsorLabel.text = nativeAd.advertiser
						
					case self.storeLabel:
						self.storeLabel.text = nativeAd.store?.uppercased()
						
					case self.priceLabel:
						self.priceLabel.text = nativeAd.price?.uppercased()
						
					case self.bodyLabel:
						self.bodyLabel.text = nativeAd.body?.capitalized
						
					case self.actionButton:
						self.actionButton.setTitle(nativeAd.callToAction?.uppercased(), for: .normal)
						
					default:
						break
					}
				}
			}
		}
		
		UIView.transition(with: mediaContentView, duration: 0.3, options: [.curveEaseOut]) {
			DispatchQueue.main.async {
				self.mediaContentView.mediaContent = nativeAd.mediaContent
			}
		}
	}
	
	private func updateViewBindings() {
		self.iconView = iconImageView
		self.headlineView = headlineLabel
		self.advertiserView = sponsorLabel
		self.starRatingView = ratingImageView
		self.storeView = storeLabel
		self.priceView = priceLabel
		self.callToActionView = actionButton
		self.bodyView = bodyLabel
		self.mediaView = mediaContentView
	}
	
	private func updateVisibility(for nativeAd: NativeAd) {
		let views: [(UIView?, Any?)] = [
			(iconView, nativeAd.icon?.image),
			(headlineView, nativeAd.headline),
			(advertiserView, nativeAd.advertiser),
			(starRatingView, nativeAd.starRating),
			(bodyView, nativeAd.body),
			(callToActionView, nativeAd.callToAction),
			(storeView, nativeAd.store),
			(priceView, nativeAd.price)
		]
		
		func isVisibleData(_ data: Any?) -> Bool {
			guard let data = data else { return false }
			
			if let string = data as? String {
				return !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			}
			
			if let nsString = data as? NSString {
				return !nsString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			}
			
			if let number = data as? NSDecimalNumber {
				return number.doubleValue > 0
			}
			
			return true
		}
		
		let validViews: [(UIView, Bool)] = views.map { view, data in
			guard let view = view else { return nil }
			return (view, isVisibleData(data))
		}.compactMap { $0 }
		
		UIView.animate(withDuration: 0.3) {
			validViews.forEach { view, isVisible in
				view.isHidden = !isVisible
			}
		}
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

// MARK: - Styling

extension NativeAdvancedView {

	private func applyStyle() {
		backgroundColor = style.backgroundColor
		contentView.backgroundColor = style.containerBackgroundColor
		containerView.backgroundColor = style.containerBackgroundColor

		headlineLabel.textColor = style.headlineTextColor
		sponsorLabel.textColor = style.sponsorTextColor
		bodyLabel.textColor = style.bodyTextColor

		attributionLabel.textColor = style.attributionTextColor
		attributionLabel.backgroundColor = style.attributionBackgroundColor
		attributionLabel.layer.borderColor = style.attributionTextColor.cgColor

		actionButton.backgroundColor = style.actionButtonBackgroundColor
		actionButton.setTitleColor(style.actionButtonTitleColor, for: .normal)
		applyButtonShape()

		storeLabel.backgroundColor = style.storeBackgroundColor
		storeLabel.textColor = style.storeTextColor

		priceLabel.backgroundColor = style.priceBackgroundColor
		priceLabel.textColor = style.priceTextColor
	}

	private func applyButtonShape() {
		switch style.buttonShape.mode {
		case let .rect(cornerRadius):
			actionButton.layer.cornerRadius = cornerRadius
		case .capsule:
			let h = actionButton.bounds.height > 0 ? actionButton.bounds.height : metrics.ctaMinHeight
			actionButton.layer.cornerRadius = h / 2
		}
	}
}

// MARK: - Public Methods

extension NativeAdvancedView {

	public func configure(with nativeAd: NativeAd) {
		self.nativeAd = nativeAd

		updateUI(with: nativeAd)
		updateVisibility(for: nativeAd)
	}
}
#endif

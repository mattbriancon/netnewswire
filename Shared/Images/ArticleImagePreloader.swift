//
//  ArticleImagePreloader.swift
//  NetNewsWire
//
//  Created for NetNewsWire image preloading feature.
//  Copyright © 2025 Ranchero Software. All rights reserved.
//

import Foundation
import os.log
import RSCore
import Articles
import Account

#if os(iOS)
import UIKit
#endif

/// Policy for when to preload article images
public enum ArticleImagePreloadPolicy: Int, Sendable {
	case never = 0
	case wifiOnly = 1
	case always = 2
}

/// Service that preloads images from articles in the background
@MainActor final class ArticleImagePreloader {

	public static let shared = ArticleImagePreloader()

	nonisolated static private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ArticleImagePreloader")

	private var preloadingInProgress = false
	private var pendingArticles = Set<Article>()

	init() {
		NotificationCenter.default.addObserver(self, selector: #selector(accountDidDownloadArticles(_:)), name: .AccountDidDownloadArticles, object: nil)
	}

	@objc func accountDidDownloadArticles(_ notification: Notification) {
		guard shouldPreloadImages() else {
			return
		}

		guard let userInfo = notification.userInfo else {
			return
		}

		var articlesToPreload = Set<Article>()

		if let newArticles = userInfo[UserInfoKey.newArticles] as? Set<Article> {
			articlesToPreload.formUnion(newArticles)
		}

		if let updatedArticles = userInfo[UserInfoKey.updatedArticles] as? Set<Article> {
			articlesToPreload.formUnion(updatedArticles)
		}

		guard !articlesToPreload.isEmpty else {
			return
		}

		Self.logger.info("Preloading images for \(articlesToPreload.count) articles")
		preloadImages(for: articlesToPreload)
	}

	private func shouldPreloadImages() -> Bool {
		let policy = getPreloadPolicy()

		switch policy {
		case .never:
			return false
		case .always:
			return true
		case .wifiOnly:
			return isOnWiFi()
		}
	}

	private func getPreloadPolicy() -> ArticleImagePreloadPolicy {
		#if os(macOS)
		return AppDefaults.shared.articleImagePreloadPolicy
		#elseif os(iOS)
		return AppDefaults.shared.articleImagePreloadPolicy
		#else
		return .never
		#endif
	}

	private func isOnWiFi() -> Bool {
		#if os(iOS)
		// Check network status on iOS
		// For now, we'll use a simplified approach via reachability
		// In production, you might want to use NWPathMonitor for more accurate results
		return true // TODO: Implement proper WiFi detection
		#else
		// On macOS, assume always connected (typically desktop)
		return true
		#endif
	}

	private func preloadImages(for articles: Set<Article>) {
		pendingArticles.formUnion(articles)

		// If already preloading, the pending articles will be processed
		guard !preloadingInProgress else {
			return
		}

		Task {
			await processPreloadQueue()
		}
	}

	private func processPreloadQueue() async {
		preloadingInProgress = true
		defer { preloadingInProgress = false }

		while !pendingArticles.isEmpty {
			let article = pendingArticles.removeFirst()
			await preloadImagesForArticle(article)
		}
	}

	private func preloadImagesForArticle(_ article: Article) async {
		var imageURLs = Set<String>()

		// Extract images from contentHTML
		if let contentHTML = article.contentHTML {
			let urls = contentHTML.extractImageURLs(baseURL: article.baseURL)
			imageURLs.formUnion(urls)
		}

		// Extract images from summary
		if let summary = article.summary {
			let urls = summary.extractImageURLs(baseURL: article.baseURL)
			imageURLs.formUnion(urls)
		}

		// Add the featured image
		if let imageLink = article.rawImageLink {
			imageURLs.insert(imageLink)
		}

		guard !imageURLs.isEmpty else {
			return
		}

		Self.logger.debug("Preloading \(imageURLs.count) images for article: \(article.title ?? article.articleID)")

		// Download images using ImageDownloader
		// This will cache them automatically
		for imageURL in imageURLs {
			_ = ImageDownloader.shared.image(for: imageURL)

			// Add a small delay between downloads to avoid overwhelming the system
			try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
		}
	}
}

private extension Article {
	/// Attempts to create a base URL for resolving relative image URLs
	var baseURL: URL? {
		// Try the article link first
		if let link = rawLink, let url = URL(string: link) {
			return url
		}

		// Try the external link
		if let externalLink = rawExternalLink, let url = URL(string: externalLink) {
			return url
		}

		// Try to get it from the feed URL
		if let feedURL = URL(string: feedID) {
			return feedURL
		}

		return nil
	}
}

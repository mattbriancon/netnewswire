//
//  HTMLImageURLExtractor.swift
//  RSCore
//
//  Created for NetNewsWire image preloading feature.
//  Copyright © 2025 Ranchero Software, LLC. All rights reserved.
//

import Foundation

public extension String {

	/// Extracts all image URLs from HTML content.
	///
	/// This function parses HTML and finds all `<img>` tags, extracting their `src` attributes.
	/// It handles various HTML formats and malformed HTML gracefully.
	///
	/// - Parameter baseURL: Optional base URL to resolve relative image URLs against.
	/// - Returns: An array of absolute image URL strings.
	func extractImageURLs(baseURL: URL? = nil) -> [String] {
		guard self.contains("<img") else {
			return []
		}

		var imageURLs = [String]()
		let html = self.lowercased()
		var searchRange = self.startIndex..<self.endIndex

		// Find all <img tags
		while let imgTagRange = html.range(of: "<img", options: [], range: searchRange) {
			// Find the end of this img tag
			let afterImgStart = imgTagRange.upperBound
			guard let tagEndRange = html.range(of: ">", options: [], range: afterImgStart..<self.endIndex) else {
				break
			}

			// Extract the tag content
			let tagContent = String(self[afterImgStart..<tagEndRange.lowerBound])

			// Extract src attribute using regex
			if let srcURL = extractSrcAttribute(from: tagContent, baseURL: baseURL) {
				imageURLs.append(srcURL)
			}

			// Move search range past this tag
			searchRange = tagEndRange.upperBound..<self.endIndex
		}

		return imageURLs
	}

	/// Extracts the src attribute value from an img tag's content.
	private func extractSrcAttribute(from tagContent: String, baseURL: URL?) -> String? {
		// Match src="..." or src='...' or src=...
		let patterns = [
			"src\\s*=\\s*\"([^\"]+)\"",
			"src\\s*=\\s*'([^']+)'",
			"src\\s*=\\s*([^\\s>]+)"
		]

		for pattern in patterns {
			if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
				let nsString = tagContent as NSString
				if let match = regex.firstMatch(in: tagContent, options: [], range: NSRange(location: 0, length: nsString.length)) {
					if match.numberOfRanges > 1 {
						let urlString = nsString.substring(with: match.range(at: 1))
						return resolveURL(urlString, baseURL: baseURL)
					}
				}
			}
		}

		return nil
	}

	/// Resolves a potentially relative URL against a base URL.
	private func resolveURL(_ urlString: String, baseURL: URL?) -> String? {
		let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

		// Skip data URLs, they're already embedded
		if trimmed.hasPrefix("data:") {
			return nil
		}

		// If it's already absolute, use it
		if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
			return trimmed
		}

		// Try to resolve relative URL
		if let base = baseURL {
			if let resolved = URL(string: trimmed, relativeTo: base) {
				return resolved.absoluteString
			}
		}

		// If we can't resolve it and it looks like a relative path, skip it
		// Otherwise, assume it's absolute
		if trimmed.hasPrefix("/") || trimmed.hasPrefix("../") || trimmed.hasPrefix("./") {
			return nil
		}

		return trimmed
	}
}

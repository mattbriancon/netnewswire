# Article Image Preloading Implementation

## Overview

This document describes the implementation of automatic image preloading for RSS feed articles in NetNewsWire. When feeds are refreshed, all images in articles are now automatically downloaded and cached so they're available offline when reading articles.

## What Was Implemented

### 1. HTML Image URL Extraction (`HTMLImageURLExtractor.swift`)
**Location:** `Modules/RSCore/Sources/RSCore/HTMLImageURLExtractor.swift`

- Extracts all `<img src="">` URLs from HTML content
- Handles relative URLs by resolving them against a base URL
- Skips data: URLs (already embedded)
- Returns array of absolute image URLs

### 2. Article Image Preloader Service (`ArticleImagePreloader.swift`)
**Location:** `Shared/Images/ArticleImagePreloader.swift`

**Features:**
- Singleton service that listens for `AccountDidDownloadArticles` notifications
- Extracts images from:
  - Article `contentHTML` (all `<img>` tags)
  - Article `summary` (all `<img>` tags)
  - Article `rawImageLink` (featured image)
- Downloads images in background using existing `ImageDownloader` infrastructure
- Respects user preference for when to preload (never/WiFi only/always)
- Implements throttling (100ms delay between downloads to avoid system overload)
- Queues articles and processes them sequentially

### 3. User Preferences
**Enum:** `ArticleImagePreloadPolicy` in `ArticleImagePreloader.swift`

**Options:**
- **Never** (`.never`) - Don't preload images
- **Wi-Fi Only** (`.wifiOnly`) - Only preload when on WiFi
- **Always** (`.always`) - Always preload images (default)

**AppDefaults Integration:**
- macOS: `/Mac/AppDefaults.swift`
- iOS: `/iOS/AppDefaults.swift`

Both platforms store the preference with key `"articleImagePreloadPolicy"` and default to `.always`.

### 4. Automatic Initialization
**macOS:** `Mac/AppDelegate.swift:170`
- Initialized in `applicationDidFinishLaunching()`

**iOS:** `iOS/AppDelegate.swift:102`
- Initialized in `application(_:didFinishLaunchingWithOptions:)`

### 5. User Interface Code

#### macOS Preferences UI
**Location:** `Mac/Preferences/General/GeneralPrefencesViewController.swift`

**Added:**
- `@IBOutlet var articleImagePreloadPopup: NSPopUpButton!`
- `articleImagePreloadPopupDidChange(_:)` action method
- `updateArticleImagePreloadPopup()` helper method
- Three menu items: "Never", "Wi-Fi Only", "Always"

**⚠️ MANUAL STEP REQUIRED:** Open `Mac/Base.lproj/Preferences.storyboard` in Xcode Interface Builder and:
1. Add a new NSPopUpButton to the General preferences view
2. Connect it to the `articleImagePreloadPopup` outlet
3. Connect its action to `articleImagePreloadPopupDidChange:`
4. Add a label above it like "Preload Article Images:"

#### iOS Settings UI
**Location:** `iOS/Settings/SettingsViewController.swift`

**Added:**
- `@IBOutlet var articleImagePreloadDetailLabel: UILabel!`
- `showArticleImagePreloadOptions()` - Shows UIAlertController action sheet
- `updateArticleImagePreloadDetailLabel()` - Updates detail label text
- Handler in `tableView(_:didSelectRowAt:)` for section 4, row 1

**⚠️ MANUAL STEP REQUIRED:** Open `iOS/Settings/Settings.storyboard` in Xcode Interface Builder and:
1. Add a new table view cell in section 4 (Articles section)
2. Set the cell style to "Right Detail" or "Value 1"
3. Set the text label to "Preload Images"
4. Connect the detail text label to `articleImagePreloadDetailLabel` outlet
5. Ensure the row index matches the handler (currently set to row 1)

## How It Works

### Flow Diagram

```
Feed Refresh Triggered
    ↓
Account.refreshAll()
    ↓
LocalAccountRefresher downloads feeds
    ↓
Articles parsed and saved to database
    ↓
AccountDidDownloadArticles notification posted
    ↓
ArticleImagePreloader receives notification
    ↓
Checks user preference (never/wifi/always)
    ↓
[If enabled] Extracts all image URLs from articles
    ↓
[If enabled] Downloads each image via ImageDownloader
    ↓
Images cached to disk automatically
    ↓
Articles display instantly with cached images
```

### Key Integration Points

1. **Notification Observer:** ArticleImagePreloader observes `AccountDidDownloadArticles`
2. **Image Extraction:** Uses `String.extractImageURLs()` extension on HTML content
3. **Downloading:** Reuses existing `ImageDownloader.shared.image(for:)` method
4. **Caching:** ImageDownloader automatically caches to disk at `AppConfig.cacheSubfolder("Images")`
5. **Throttling:** 100ms delay between downloads to prevent overwhelming the system

## Files Modified/Created

### Created Files:
1. `Modules/RSCore/Sources/RSCore/HTMLImageURLExtractor.swift`
2. `Shared/Images/ArticleImagePreloader.swift`
3. `IMAGE_PRELOADING_IMPLEMENTATION.md` (this file)

### Modified Files:
1. `Mac/AppDefaults.swift` - Added preference property
2. `iOS/AppDefaults.swift` - Added preference property
3. `Mac/AppDelegate.swift` - Initialize preloader
4. `iOS/AppDelegate.swift` - Initialize preloader
5. `Mac/Preferences/General/GeneralPrefencesViewController.swift` - UI code
6. `iOS/Settings/SettingsViewController.swift` - UI code

## Testing

To test the implementation:

1. **Build the project:** `./buildscripts/build_and_test.sh`
2. **Add a test feed** with lots of images (e.g., a photography blog)
3. **Set preference to "Always"** in Settings/Preferences
4. **Refresh feeds**
5. **Check logs** for preloading activity:
   - Look for: "Preloading images for N articles"
   - Look for: "Preloading X images for article: [title]"
6. **Turn off network** or go to Airplane Mode
7. **Open articles** - images should load from cache

### Debug Logging

The ArticleImagePreloader uses `os.log` with subsystem `Bundle.main.bundleIdentifier` and category `"ArticleImagePreloader"`. Enable logging with:

```bash
log stream --predicate 'subsystem == "com.ranchero.NetNewsWire-Evergreen" AND category == "ArticleImagePreloader"' --level debug
```

## Performance Considerations

1. **Throttling:** 100ms delay between image downloads prevents CPU/network spike
2. **Queue Management:** Articles queued and processed sequentially
3. **Existing Cache:** ImageDownloader checks memory cache → disk cache → network
4. **Bad URL Tracking:** Failed URLs are marked and skipped on future attempts
5. **Network Detection:** WiFi-only mode prevents mobile data usage (iOS implementation simplified for now)

## Future Enhancements

Potential improvements:

1. **Better WiFi Detection:** Implement proper network path monitoring on iOS using `NWPathMonitor`
2. **Progress Reporting:** Surface preload progress to the user
3. **Bandwidth Limiting:** Add configurable rate limit for downloads
4. **Selective Preloading:** Only preload unread articles or starred feeds
5. **Cache Management:** Intelligently prune old article images
6. **Background Task:** Use BGTaskScheduler for iOS background downloading

## Architecture Notes

- **Separation of Concerns:** Image extraction is separate from download management
- **Reuse Existing Infrastructure:** Leverages ImageDownloader, avoiding duplication
- **Cross-Platform:** Core logic in Shared/, platform-specific code in Mac/iOS folders
- **Configurable:** User has full control via preferences
- **Defensive:** Handles malformed HTML, missing images, network failures gracefully

## Troubleshooting

**Images not preloading:**
- Check preference is set to "Always" or "WiFi Only"
- Verify ArticleImagePreloader.shared is initialized in AppDelegate
- Check logs for errors
- Ensure feeds are actually being refreshed

**Build errors:**
- Storyboard outlets not connected → Follow manual UI steps above
- Missing ArticleImagePreloadPolicy import → Make sure it's `public enum`

**Images missing after preload:**
- Check image URLs are valid (not 404)
- Verify ImageDownloader disk cache isn't full
- Check if images are behind authentication

## Credits

Implemented as part of the image preloading feature request. Uses existing NetNewsWire infrastructure for feed parsing, article storage, and image downloading.

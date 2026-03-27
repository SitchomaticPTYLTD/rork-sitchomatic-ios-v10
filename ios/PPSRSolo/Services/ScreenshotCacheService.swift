import Foundation
import UIKit

@MainActor
class ScreenshotCacheService {
    static let shared = ScreenshotCacheService()

    private let fullDirectory: URL
    private let thumbDirectory: URL
    private let metadataURL: URL
    private let checkMapURL: URL
    private let maxMemoryCacheCount = 80
    private let maxThumbCacheCount = 100
    private var memoryCache: [String: UIImage] = [:]
    private var thumbCache: [String: UIImage] = [:]
    private var accessOrder: [String] = []
    private var thumbAccessOrder: [String] = []
    private let thumbSize: CGFloat = 160
    private var checkScreenshotMap: [String: [String]] = [:]

    init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        fullDirectory = cachesDir.appendingPathComponent("ScreenshotCache/full", isDirectory: true)
        thumbDirectory = cachesDir.appendingPathComponent("ScreenshotCache/thumb", isDirectory: true)
        metadataURL = cachesDir.appendingPathComponent("ScreenshotCache/metadata.json")
        checkMapURL = cachesDir.appendingPathComponent("ScreenshotCache/check_map.json")
        try? FileManager.default.createDirectory(at: fullDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbDirectory, withIntermediateDirectories: true)
        loadCheckMap()
    }

    func store(_ image: UIImage, forKey key: String) {
        memoryCache[key] = image
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
        evictMemoryCacheIfNeeded()

        let thumb = generateThumbnail(image)
        thumbCache[key] = thumb

        Task.detached(priority: .utility) {
            let fullURL = self.fullFileURL(for: key)
            let thumbURL = self.thumbFileURL(for: key)
            if let data = image.jpegData(compressionQuality: 0.45) {
                try? data.write(to: fullURL, options: .atomic)
            }
            if let thumbData = thumb.jpegData(compressionQuality: 0.4) {
                try? thumbData.write(to: thumbURL, options: .atomic)
            }
        }
    }

    func retrieveFull(forKey key: String) -> UIImage? {
        if let cached = memoryCache[key] {
            touchAccess(key)
            return cached
        }
        let fileURL = fullFileURL(for: key)
        guard FileManager.default.fileExists(atPath: fileURL.path()),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }
        memoryCache[key] = image
        touchAccess(key)
        evictMemoryCacheIfNeeded()
        return image
    }

    func retrieveThumbnail(forKey key: String) -> UIImage? {
        if let cached = thumbCache[key] {
            touchThumbAccess(key)
            return cached
        }
        let fileURL = thumbFileURL(for: key)
        guard FileManager.default.fileExists(atPath: fileURL.path()),
              let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            if let full = retrieveFull(forKey: key) {
                let thumb = generateThumbnail(full)
                thumbCache[key] = thumb
                return thumb
            }
            return nil
        }
        thumbCache[key] = image
        touchThumbAccess(key)
        evictThumbCacheIfNeeded()
        return image
    }

    func storeDebugScreenshot(_ screenshot: PPSRDebugScreenshot) {
        store(screenshot.image, forKey: "debug_\(screenshot.id)")
        if let cropped = screenshot.croppedImage {
            store(cropped, forKey: "debug_\(screenshot.id)_crop")
        }
    }

    func storeDebugScreenshot(_ screenshot: PPSRDebugScreenshot, forCheckId checkId: String) {
        storeDebugScreenshot(screenshot)
        var ids = checkScreenshotMap[checkId] ?? []
        if !ids.contains(screenshot.id) {
            ids.append(screenshot.id)
            checkScreenshotMap[checkId] = ids
            persistCheckMap()
        }
    }

    func screenshotIds(forCheckId checkId: String) -> [String] {
        checkScreenshotMap[checkId] ?? []
    }

    func screenshotCount(forCheckId checkId: String) -> Int {
        checkScreenshotMap[checkId]?.count ?? 0
    }

    func loadScreenshots(forCheckId checkId: String) -> [UIImage] {
        screenshotIds(forCheckId: checkId).compactMap { retrieveFull(forKey: "debug_\($0)") }
    }

    func loadThumbnails(forCheckId checkId: String) -> [UIImage] {
        screenshotIds(forCheckId: checkId).compactMap { retrieveThumbnail(forKey: "debug_\($0)") }
    }

    func batchSaveDebugScreenshots(_ screenshots: [PPSRDebugScreenshot]) {
        for screenshot in screenshots {
            storeDebugScreenshot(screenshot)
        }
        saveDebugScreenshotMetadata(screenshots)
    }

    func removeScreenshots(forCheckId checkId: String) {
        guard let ids = checkScreenshotMap.removeValue(forKey: checkId) else { return }
        for id in ids {
            let fullKey = "debug_\(id)"
            let cropKey = "debug_\(id)_crop"
            memoryCache.removeValue(forKey: fullKey)
            memoryCache.removeValue(forKey: cropKey)
            thumbCache.removeValue(forKey: fullKey)
            thumbCache.removeValue(forKey: cropKey)
            accessOrder.removeAll { $0 == fullKey || $0 == cropKey }
            try? FileManager.default.removeItem(at: fullFileURL(for: fullKey))
            try? FileManager.default.removeItem(at: thumbFileURL(for: fullKey))
            try? FileManager.default.removeItem(at: fullFileURL(for: cropKey))
            try? FileManager.default.removeItem(at: thumbFileURL(for: cropKey))
        }
        persistCheckMap()
    }

    func loadDebugScreenshotImage(id: String) -> UIImage? {
        retrieveFull(forKey: "debug_\(id)")
    }

    func loadDebugScreenshotThumbnail(id: String) -> UIImage? {
        retrieveThumbnail(forKey: "debug_\(id)")
    }

    func loadDebugScreenshotCrop(id: String) -> UIImage? {
        retrieveFull(forKey: "debug_\(id)_crop")
    }

    nonisolated struct ScreenshotMetadataEntry: Codable, Sendable {
        let id: String
        let timestamp: Date
        let stepName: String
        let cardDisplayNumber: String
        let cardId: String
        let vin: String
        let email: String
        let note: String
        let autoDetectedResult: String
        let userOverride: String
        let userNote: String
        let hasCrop: Bool
        var checkId: String?
    }

    func saveDebugScreenshotMetadata(_ screenshots: [PPSRDebugScreenshot]) {
        let reverseMap = buildReverseCheckMap()
        let entries = screenshots.map { s in
            ScreenshotMetadataEntry(
                id: s.id, timestamp: s.timestamp, stepName: s.stepName,
                cardDisplayNumber: s.cardDisplayNumber, cardId: s.cardId,
                vin: s.vin, email: s.email, note: s.note,
                autoDetectedResult: s.autoDetectedResult.rawValue,
                userOverride: s.userOverride.rawValue,
                userNote: s.userNote,
                hasCrop: s.croppedImage != nil,
                checkId: reverseMap[s.id]
            )
        }
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(entries) {
                try? data.write(to: self.metadataURL, options: .atomic)
            }
        }
    }

    func loadDebugScreenshotMetadata() -> [PPSRDebugScreenshot] {
        guard FileManager.default.fileExists(atPath: metadataURL.path()),
              let data = try? Data(contentsOf: metadataURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let entries = try? decoder.decode([ScreenshotMetadataEntry].self, from: data) else { return [] }

        var results: [PPSRDebugScreenshot] = []
        for entry in entries.prefix(200) {
            guard let image = retrieveFull(forKey: "debug_\(entry.id)") else { continue }
            var crop: UIImage?
            if entry.hasCrop {
                crop = retrieveFull(forKey: "debug_\(entry.id)_crop")
            }
            let autoResult = PPSRDebugScreenshot.AutoDetectedResult(rawValue: entry.autoDetectedResult) ?? .unknown
            let screenshot = PPSRDebugScreenshot(
                restoredId: entry.id,
                restoredTimestamp: entry.timestamp,
                stepName: entry.stepName,
                cardDisplayNumber: entry.cardDisplayNumber,
                cardId: entry.cardId,
                vin: entry.vin,
                email: entry.email,
                image: image,
                croppedImage: crop,
                note: entry.note,
                autoDetectedResult: autoResult
            )
            screenshot.userOverride = UserResultOverride(rawValue: entry.userOverride) ?? .none
            screenshot.userNote = entry.userNote
            results.append(screenshot)

            if let checkId = entry.checkId, !checkId.isEmpty {
                var ids = checkScreenshotMap[checkId] ?? []
                if !ids.contains(entry.id) {
                    ids.append(entry.id)
                    checkScreenshotMap[checkId] = ids
                }
            }
        }
        return results
    }

    func clearAll() {
        memoryCache.removeAll()
        thumbCache.removeAll()
        accessOrder.removeAll()
        checkScreenshotMap.removeAll()
        try? FileManager.default.removeItem(at: fullDirectory)
        try? FileManager.default.removeItem(at: thumbDirectory)
        try? FileManager.default.removeItem(at: metadataURL)
        try? FileManager.default.removeItem(at: checkMapURL)
        try? FileManager.default.createDirectory(at: fullDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbDirectory, withIntermediateDirectories: true)
    }

    var diskCacheSize: String {
        let fm = FileManager.default
        var totalSize: Int64 = 0
        for dir in [fullDirectory, thumbDirectory] {
            guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for file in files {
                if let values = try? file.resourceValues(forKeys: [.fileSizeKey]),
                   let size = values.fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalSize)
    }

    var screenshotCount: Int {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: fullDirectory, includingPropertiesForKeys: nil)) ?? []
        return files.count
    }

    private func generateThumbnail(_ image: UIImage) -> UIImage {
        let maxDim = thumbSize
        let size = image.size
        let scale: CGFloat
        if size.width > size.height {
            scale = maxDim / size.width
        } else {
            scale = maxDim / size.height
        }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    var memoryCacheCount: Int { memoryCache.count }
    var thumbCacheCount: Int { thumbCache.count }

    func purgeStaleScreenshots(olderThan cutoff: Date, keepOverrides: Set<String>) {
        guard FileManager.default.fileExists(atPath: metadataURL.path()),
              let data = try? Data(contentsOf: metadataURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var entries = try? decoder.decode([ScreenshotMetadataEntry].self, from: data) else { return }
        let before = entries.count
        entries.removeAll { entry in
            entry.timestamp < cutoff && !keepOverrides.contains(entry.id)
        }
        if entries.count < before {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let updated = try? encoder.encode(entries) {
                try? updated.write(to: metadataURL, options: .atomic)
            }
            let removed = before - entries.count
            let remainingIds = Set(entries.map(\.id))
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(at: fullDirectory, includingPropertiesForKeys: nil) {
                for file in files {
                    let name = file.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "debug_", with: "")
                    if !remainingIds.contains(name) && !name.hasSuffix("_crop") {
                        try? fm.removeItem(at: file)
                        try? fm.removeItem(at: thumbFileURL(for: "debug_\(name)"))
                    }
                }
            }
            _ = removed
        }
    }

    private func touchAccess(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func touchThumbAccess(_ key: String) {
        thumbAccessOrder.removeAll { $0 == key }
        thumbAccessOrder.append(key)
    }

    private func evictMemoryCacheIfNeeded() {
        while memoryCache.count > maxMemoryCacheCount, let oldest = accessOrder.first {
            memoryCache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
        }
    }

    private func evictThumbCacheIfNeeded() {
        while thumbCache.count > maxThumbCacheCount, let oldest = thumbAccessOrder.first {
            thumbCache.removeValue(forKey: oldest)
            thumbAccessOrder.removeFirst()
        }
    }

    private nonisolated func fullFileURL(for key: String) -> URL {
        let safeKey = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDir.appendingPathComponent("ScreenshotCache/full/\(safeKey).jpg")
    }

    private nonisolated func thumbFileURL(for key: String) -> URL {
        let safeKey = key.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cachesDir.appendingPathComponent("ScreenshotCache/thumb/\(safeKey).jpg")
    }

    private func persistCheckMap() {
        let mapCopy = checkScreenshotMap
        let url = checkMapURL
        Task.detached(priority: .utility) {
            let encoder = JSONEncoder()
            if let data = try? encoder.encode(mapCopy) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func loadCheckMap() {
        guard FileManager.default.fileExists(atPath: checkMapURL.path()),
              let data = try? Data(contentsOf: checkMapURL),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        checkScreenshotMap = map
    }

    private func buildReverseCheckMap() -> [String: String] {
        var reverse: [String: String] = [:]
        for (checkId, ssIds) in checkScreenshotMap {
            for ssId in ssIds {
                reverse[ssId] = checkId
            }
        }
        return reverse
    }
}

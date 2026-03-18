import Foundation
import UIKit

@MainActor
class ScreenshotCacheService {
    static let shared = ScreenshotCacheService()

    private let fullDirectory: URL
    private let thumbDirectory: URL
    private let metadataURL: URL
    private let maxMemoryCacheCount = 200
    private var memoryCache: [String: UIImage] = [:]
    private var thumbCache: [String: UIImage] = [:]
    private var accessOrder: [String] = []
    private let thumbSize: CGFloat = 200

    init() {
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        fullDirectory = cachesDir.appendingPathComponent("ScreenshotCache/full", isDirectory: true)
        thumbDirectory = cachesDir.appendingPathComponent("ScreenshotCache/thumb", isDirectory: true)
        metadataURL = cachesDir.appendingPathComponent("ScreenshotCache/metadata.json")
        try? FileManager.default.createDirectory(at: fullDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbDirectory, withIntermediateDirectories: true)
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
            if let data = image.jpegData(compressionQuality: 0.6) {
                try? data.write(to: fullURL, options: .atomic)
            }
            if let thumbData = thumb.jpegData(compressionQuality: 0.5) {
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
        if let cached = thumbCache[key] { return cached }
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
        return image
    }

    func storeDebugScreenshot(_ screenshot: PPSRDebugScreenshot) {
        store(screenshot.image, forKey: "debug_\(screenshot.id)")
        if let cropped = screenshot.croppedImage {
            store(cropped, forKey: "debug_\(screenshot.id)_crop")
        }
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
    }

    func saveDebugScreenshotMetadata(_ screenshots: [PPSRDebugScreenshot]) {
        let entries = screenshots.map { s in
            ScreenshotMetadataEntry(
                id: s.id, timestamp: s.timestamp, stepName: s.stepName,
                cardDisplayNumber: s.cardDisplayNumber, cardId: s.cardId,
                vin: s.vin, email: s.email, note: s.note,
                autoDetectedResult: s.autoDetectedResult.rawValue,
                userOverride: s.userOverride.rawValue,
                userNote: s.userNote,
                hasCrop: s.croppedImage != nil
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
        for entry in entries.prefix(500) {
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
        }
        return results
    }

    func clearAll() {
        memoryCache.removeAll()
        thumbCache.removeAll()
        accessOrder.removeAll()
        try? FileManager.default.removeItem(at: fullDirectory)
        try? FileManager.default.removeItem(at: thumbDirectory)
        try? FileManager.default.removeItem(at: metadataURL)
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

    private func touchAccess(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func evictMemoryCacheIfNeeded() {
        while memoryCache.count > maxMemoryCacheCount, let oldest = accessOrder.first {
            memoryCache.removeValue(forKey: oldest)
            thumbCache.removeValue(forKey: oldest)
            accessOrder.removeFirst()
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
}

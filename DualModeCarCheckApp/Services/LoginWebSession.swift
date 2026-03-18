import Foundation
import WebKit
import UIKit

@MainActor
class LoginWebSession: NSObject {
    static let targetURL = URL(string: "https://transact.ppsr.gov.au/CarCheck/")!

    var stealthEnabled: Bool = false
    var onFingerprintLog: ((String, PPSRLogEntry.Level) -> Void)?
    var lastNavigationError: String?
    var lastHTTPStatusCode: Int?

    private var webView: WKWebView?
    private let pool = WebViewPool.shared
    private let logger = DebugLogger.shared

    func setUp() {
        webView = pool.acquire(stealthEnabled: stealthEnabled)
    }

    func tearDown() {
        if let wv = webView {
            pool.release(wv)
            webView = nil
        }
    }

    func loadPage(timeout: TimeInterval = 30) async -> Bool {
        guard let wv = webView else { return false }
        lastNavigationError = nil
        lastHTTPStatusCode = nil

        return await withCheckedContinuation { continuation in
            let delegate = NavigationDelegate(timeout: timeout) { success, error, statusCode in
                self.lastNavigationError = error
                self.lastHTTPStatusCode = statusCode
                continuation.resume(returning: success)
            }
            wv.navigationDelegate = delegate
            objc_setAssociatedObject(wv, "navDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            wv.load(URLRequest(url: Self.targetURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout))
        }
    }

    func getPageTitle() async -> String {
        guard let wv = webView else { return "" }
        return (try? await wv.evaluateJavaScript("document.title")) as? String ?? ""
    }

    func getPageContent() async -> String {
        guard let wv = webView else { return "" }
        return (try? await wv.evaluateJavaScript("document.body?.innerText || ''")) as? String ?? ""
    }

    func dumpPageStructure() async -> String {
        guard let wv = webView else { return "" }
        let js = """
        (function() {
            var inputs = document.querySelectorAll('input, select, button, textarea');
            var result = [];
            inputs.forEach(function(el) {
                result.push(el.tagName + ' type=' + (el.type||'') + ' id=' + (el.id||'') + ' name=' + (el.name||'') + ' placeholder=' + (el.placeholder||''));
            });
            return result.join('\\n');
        })()
        """
        return (try? await wv.evaluateJavaScript(js)) as? String ?? ""
    }

    struct AppReadyResult {
        let ready: Bool
        let fieldsFound: Int
        let detail: String
    }

    func waitForAppReady(timeout: TimeInterval = 25) async -> AppReadyResult {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            let verification = await verifyFieldsExist()
            if verification.found >= 4 {
                return AppReadyResult(ready: true, fieldsFound: verification.found, detail: "Found \(verification.found)/6 fields")
            }
            try? await Task.sleep(for: .seconds(1))
        }
        let final_ = await verifyFieldsExist()
        return AppReadyResult(ready: final_.found >= 4, fieldsFound: final_.found, detail: "Timeout — found \(final_.found)/6 fields")
    }

    struct FieldVerification {
        let found: Int
        let missing: [String]
    }

    func verifyFieldsExist() async -> FieldVerification {
        guard let wv = webView else { return FieldVerification(found: 0, missing: ["all"]) }
        let js = """
        (function() {
            var fields = {
                'VIN': document.querySelector('input[name*="vin" i], input[id*="vin" i], input[placeholder*="vin" i]'),
                'Email': document.querySelector('input[type="email"], input[name*="email" i], input[id*="email" i]'),
                'CardNumber': document.querySelector('input[name*="card" i], input[id*="card" i], input[autocomplete="cc-number"]'),
                'ExpMonth': document.querySelector('select[name*="month" i], input[name*="month" i], select[id*="month" i]'),
                'ExpYear': document.querySelector('select[name*="year" i], input[name*="year" i], select[id*="year" i]'),
                'CVV': document.querySelector('input[name*="cvv" i], input[name*="cvc" i], input[name*="security" i], input[id*="cvv" i]')
            };
            var found = [];
            var missing = [];
            for (var key in fields) {
                if (fields[key]) { found.push(key); } else { missing.push(key); }
            }
            return JSON.stringify({found: found, missing: missing});
        })()
        """
        guard let result = try? await wv.evaluateJavaScript(js) as? String,
              let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else {
            return FieldVerification(found: 0, missing: ["unknown"])
        }
        let found = json["found"] ?? []
        let missing = json["missing"] ?? []
        return FieldVerification(found: found.count, missing: missing)
    }

    func fillVIN(_ vin: String) async -> (success: Bool, detail: String) {
        await fillField(selectors: ["input[name*='vin' i]", "input[id*='vin' i]", "input[placeholder*='vin' i]"], value: vin, fieldName: "VIN")
    }

    func fillEmail(_ email: String) async -> (success: Bool, detail: String) {
        await fillField(selectors: ["input[type='email']", "input[name*='email' i]", "input[id*='email' i]"], value: email, fieldName: "Email")
    }

    func fillCardNumber(_ number: String) async -> (success: Bool, detail: String) {
        await fillField(selectors: ["input[name*='card' i]", "input[id*='card' i]", "input[autocomplete='cc-number']"], value: number, fieldName: "Card")
    }

    func fillExpMonth(_ month: String) async -> (success: Bool, detail: String) {
        await selectOrFillField(selectors: ["select[name*='month' i]", "select[id*='month' i]", "input[name*='month' i]"], value: month, fieldName: "ExpMonth")
    }

    func fillExpYear(_ year: String) async -> (success: Bool, detail: String) {
        await selectOrFillField(selectors: ["select[name*='year' i]", "select[id*='year' i]", "input[name*='year' i]"], value: year, fieldName: "ExpYear")
    }

    func fillCVV(_ cvv: String) async -> (success: Bool, detail: String) {
        await fillField(selectors: ["input[name*='cvv' i]", "input[name*='cvc' i]", "input[name*='security' i]", "input[id*='cvv' i]"], value: cvv, fieldName: "CVV")
    }

    func clickShowMyResults() async -> (success: Bool, detail: String) {
        guard let wv = webView else { return (false, "No webview") }
        let js = """
        (function() {
            var btn = document.querySelector('button[type="submit"], input[type="submit"], button.btn-primary, button[id*="submit" i]');
            if (!btn) {
                var allBtns = document.querySelectorAll('button');
                for (var i = 0; i < allBtns.length; i++) {
                    if (allBtns[i].textContent.toLowerCase().includes('show') || allBtns[i].textContent.toLowerCase().includes('result') || allBtns[i].textContent.toLowerCase().includes('search')) {
                        btn = allBtns[i]; break;
                    }
                }
            }
            if (btn) { btn.click(); return 'clicked: ' + btn.textContent.trim().substring(0, 50); }
            return 'no_button_found';
        })()
        """
        guard let result = try? await wv.evaluateJavaScript(js) as? String else {
            return (false, "JS execution failed")
        }
        if result.hasPrefix("clicked:") {
            return (true, result)
        }
        return (false, result)
    }

    func waitForNavigation(timeout: TimeInterval = 10) async -> Bool {
        guard let wv = webView else { return false }
        let initialURL = wv.url?.absoluteString ?? ""
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            try? await Task.sleep(for: .milliseconds(500))
            let currentURL = wv.url?.absoluteString ?? ""
            if currentURL != initialURL { return true }
            let loading = wv.isLoading
            if !loading && Date().timeIntervalSince(start) > 2 { return true }
        }
        return false
    }

    struct ScreenshotResult {
        let full: UIImage?
        let cropped: UIImage?
    }

    func captureScreenshotWithCrop(cropRect: CGRect?) async -> ScreenshotResult {
        guard let wv = webView else { return ScreenshotResult(full: nil, cropped: nil) }
        let config = WKSnapshotConfiguration()
        do {
            let image = try await wv.takeSnapshot(configuration: config)
            var cropped: UIImage?
            if let rect = cropRect, rect != .zero {
                let scale = image.scale
                let scaledRect = CGRect(x: rect.origin.x * scale, y: rect.origin.y * scale, width: rect.size.width * scale, height: rect.size.height * scale)
                if let cgCropped = image.cgImage?.cropping(to: scaledRect) {
                    cropped = UIImage(cgImage: cgCropped, scale: scale, orientation: image.imageOrientation)
                }
            }
            return ScreenshotResult(full: image, cropped: cropped)
        } catch {
            return ScreenshotResult(full: nil, cropped: nil)
        }
    }

    private func fillField(selectors: [String], value: String, fieldName: String) async -> (success: Bool, detail: String) {
        guard let wv = webView else { return (false, "No webview") }
        let escapedValue = value.replacingOccurrences(of: "'", with: "\\'")
        for selector in selectors {
            let js = """
            (function() {
                var el = document.querySelector('\(selector)');
                if (el) {
                    el.focus();
                    el.value = '\(escapedValue)';
                    el.dispatchEvent(new Event('input', {bubbles: true}));
                    el.dispatchEvent(new Event('change', {bubbles: true}));
                    return 'filled via ' + '\(selector)';
                }
                return null;
            })()
            """
            if let result = try? await wv.evaluateJavaScript(js) as? String {
                return (true, "\(fieldName) \(result)")
            }
        }
        return (false, "\(fieldName) field not found")
    }

    private func selectOrFillField(selectors: [String], value: String, fieldName: String) async -> (success: Bool, detail: String) {
        guard let wv = webView else { return (false, "No webview") }
        let escapedValue = value.replacingOccurrences(of: "'", with: "\\'")
        for selector in selectors {
            let js = """
            (function() {
                var el = document.querySelector('\(selector)');
                if (!el) return null;
                if (el.tagName === 'SELECT') {
                    for (var i = 0; i < el.options.length; i++) {
                        if (el.options[i].value === '\(escapedValue)' || el.options[i].text.includes('\(escapedValue)')) {
                            el.selectedIndex = i; el.dispatchEvent(new Event('change', {bubbles: true}));
                            return 'selected via ' + '\(selector)';
                        }
                    }
                }
                el.focus(); el.value = '\(escapedValue)';
                el.dispatchEvent(new Event('input', {bubbles: true}));
                el.dispatchEvent(new Event('change', {bubbles: true}));
                return 'filled via ' + '\(selector)';
            })()
            """
            if let result = try? await wv.evaluateJavaScript(js) as? String {
                return (true, "\(fieldName) \(result)")
            }
        }
        return (false, "\(fieldName) field not found")
    }
}

private class NavigationDelegate: NSObject, WKNavigationDelegate {
    let timeout: TimeInterval
    let completion: (Bool, String?, Int?) -> Void
    private var completed = false
    private var timeoutTask: Task<Void, Never>?

    init(timeout: TimeInterval, completion: @escaping (Bool, String?, Int?) -> Void) {
        self.timeout = timeout
        self.completion = completion
        super.init()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            self?.finish(success: false, error: "Timeout after \(Int(timeout))s", statusCode: nil)
        }
    }

    @MainActor
    private func finish(success: Bool, error: String?, statusCode: Int?) {
        guard !completed else { return }
        completed = true
        timeoutTask?.cancel()
        completion(success, error, statusCode)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            finish(success: true, error: nil, statusCode: 200)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            finish(success: false, error: error.localizedDescription, statusCode: nil)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            finish(success: false, error: error.localizedDescription, statusCode: nil)
        }
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let statusCode = (navigationResponse.response as? HTTPURLResponse)?.statusCode
        if let statusCode {
            await MainActor.run {
                self.completion(false, nil, statusCode)
            }
        }
        return .allow
    }
}

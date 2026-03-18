import Foundation
@preconcurrency import WebKit
import UIKit

@MainActor
class LoginWebSession: NSObject {
    static let targetURL = URL(string: "https://transact.ppsr.gov.au/CarCheck/")!

    var stealthEnabled: Bool = false
    var onFingerprintLog: ((String, PPSRLogEntry.Level) -> Void)?
    var lastNavigationError: String?
    var lastHTTPStatusCode: Int?
    var lastFieldMap: SmartFieldMap?

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
        lastFieldMap = nil

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
            var els = document.querySelectorAll('input, select, button, textarea, a[role="button"]');
            var result = [];
            els.forEach(function(el, idx) {
                var label = '';
                if (el.id) {
                    var lbl = document.querySelector('label[for="' + el.id + '"]');
                    if (lbl) label = lbl.textContent.trim().substring(0, 60);
                }
                if (!label) {
                    var parent = el.closest('label, .form-group, .field, [class*="field"], [class*="form"]');
                    if (parent) label = parent.textContent.trim().substring(0, 60);
                }
                var vis = el.offsetParent !== null || el.offsetWidth > 0;
                result.push(
                    idx + ': ' + el.tagName +
                    ' type=' + (el.type||'') +
                    ' id=' + (el.id||'') +
                    ' name=' + (el.name||'') +
                    ' placeholder=' + (el.placeholder||'') +
                    ' autocomplete=' + (el.autocomplete||'') +
                    ' aria=' + (el.getAttribute('aria-label')||'') +
                    ' label=' + label +
                    ' vis=' + vis +
                    ' val=' + (el.value||'').substring(0,20)
                );
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
            let map = await runSmartFieldDetection()
            let count = map.foundCount
            if count >= 4 {
                lastFieldMap = map
                return AppReadyResult(ready: true, fieldsFound: count, detail: "Smart detection: \(count)/6 fields [\(map.summary)]")
            }
            try? await Task.sleep(for: .seconds(1))
        }
        let finalMap = await runSmartFieldDetection()
        lastFieldMap = finalMap
        return AppReadyResult(ready: finalMap.foundCount >= 4, fieldsFound: finalMap.foundCount, detail: "Timeout — smart detection: \(finalMap.foundCount)/6 fields [\(finalMap.summary)]")
    }

    struct FieldVerification {
        let found: Int
        let missing: [String]
    }

    func verifyFieldsExist() async -> FieldVerification {
        let map = await runSmartFieldDetection()
        lastFieldMap = map
        return FieldVerification(found: map.foundCount, missing: map.missingFields)
    }

    struct SmartFieldMap {
        var vinIndex: Int?
        var emailIndex: Int?
        var cardNumberIndex: Int?
        var expMonthIndex: Int?
        var expYearIndex: Int?
        var cvvIndex: Int?
        var vinConfidence: Int = 0
        var emailConfidence: Int = 0
        var cardNumberConfidence: Int = 0
        var expMonthConfidence: Int = 0
        var expYearConfidence: Int = 0
        var cvvConfidence: Int = 0
        var totalElements: Int = 0

        var foundCount: Int {
            [vinIndex, emailIndex, cardNumberIndex, expMonthIndex, expYearIndex, cvvIndex].compactMap { $0 }.count
        }

        var missingFields: [String] {
            var m: [String] = []
            if vinIndex == nil { m.append("VIN") }
            if emailIndex == nil { m.append("Email") }
            if cardNumberIndex == nil { m.append("CardNumber") }
            if expMonthIndex == nil { m.append("ExpMonth") }
            if expYearIndex == nil { m.append("ExpYear") }
            if cvvIndex == nil { m.append("CVV") }
            return m
        }

        var summary: String {
            var parts: [String] = []
            if let v = vinIndex { parts.append("VIN=#\(v)@\(vinConfidence)") }
            if let v = emailIndex { parts.append("Email=#\(v)@\(emailConfidence)") }
            if let v = cardNumberIndex { parts.append("Card=#\(v)@\(cardNumberConfidence)") }
            if let v = expMonthIndex { parts.append("ExpM=#\(v)@\(expMonthConfidence)") }
            if let v = expYearIndex { parts.append("ExpY=#\(v)@\(expYearConfidence)") }
            if let v = cvvIndex { parts.append("CVV=#\(v)@\(cvvConfidence)") }
            return parts.joined(separator: " ")
        }
    }

    private static let smartDetectionJS: String = """
    (function() {
        var els = document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="checkbox"]):not([type="radio"]), select, textarea');
        var items = [];
        els.forEach(function(el, idx) {
            if (el.offsetParent === null && el.offsetWidth === 0 && el.offsetHeight === 0) return;
            if (el.disabled) return;

            var labelText = '';
            if (el.id) {
                var lbl = document.querySelector('label[for="' + CSS.escape(el.id) + '"]');
                if (lbl) labelText = lbl.textContent.trim().toLowerCase();
            }
            if (!labelText) {
                var parent = el.closest('label');
                if (parent) labelText = parent.textContent.trim().toLowerCase();
            }
            if (!labelText) {
                var prev = el.previousElementSibling;
                if (prev && (prev.tagName === 'LABEL' || prev.tagName === 'SPAN' || prev.tagName === 'DIV')) {
                    labelText = prev.textContent.trim().toLowerCase();
                }
            }
            if (!labelText) {
                var wrapper = el.closest('.form-group, .field, [class*="field"], [class*="form-row"], [class*="input"]');
                if (wrapper) {
                    var wrapLabel = wrapper.querySelector('label, .label, [class*="label"]');
                    if (wrapLabel) labelText = wrapLabel.textContent.trim().toLowerCase();
                }
            }

            items.push({
                i: idx,
                tag: el.tagName,
                type: (el.type || '').toLowerCase(),
                id: (el.id || '').toLowerCase(),
                name: (el.name || '').toLowerCase(),
                placeholder: (el.placeholder || '').toLowerCase(),
                autocomplete: (el.autocomplete || '').toLowerCase(),
                aria: (el.getAttribute('aria-label') || '').toLowerCase(),
                label: labelText.substring(0, 100),
                maxLength: el.maxLength || 0,
                pattern: el.pattern || '',
                className: (el.className || '').toLowerCase(),
                inputMode: (el.inputMode || '').toLowerCase()
            });
        });

        function score(item, keywords, negKeywords) {
            var s = 0;
            var all = item.id + ' ' + item.name + ' ' + item.placeholder + ' ' + item.autocomplete + ' ' + item.aria + ' ' + item.label + ' ' + item.className;
            for (var k = 0; k < keywords.length; k++) {
                var kw = keywords[k];
                if (item.autocomplete.indexOf(kw) >= 0) s += 30;
                if (item.name === kw || item.id === kw) s += 25;
                if (item.name.indexOf(kw) >= 0) s += 15;
                if (item.id.indexOf(kw) >= 0) s += 12;
                if (item.placeholder.indexOf(kw) >= 0) s += 10;
                if (item.aria.indexOf(kw) >= 0) s += 10;
                if (item.label.indexOf(kw) >= 0) s += 8;
                if (item.className.indexOf(kw) >= 0) s += 3;
            }
            if (negKeywords) {
                for (var n = 0; n < negKeywords.length; n++) {
                    if (all.indexOf(negKeywords[n]) >= 0) s -= 20;
                }
            }
            return s;
        }

        function bestMatch(items, keywords, negKeywords, tagFilter, minScore) {
            var best = null, bestScore = minScore || 5;
            for (var j = 0; j < items.length; j++) {
                if (tagFilter && items[j].tag !== tagFilter) continue;
                var s = score(items[j], keywords, negKeywords);
                if (s > bestScore) { bestScore = s; best = items[j]; }
            }
            return best ? { index: best.i, confidence: bestScore, tag: best.tag } : null;
        }

        var vin = bestMatch(items, ['vin', 'vehicle', 'identification', 'chassis', 'frame'], ['email', 'card', 'cvv', 'expir'], 'INPUT');
        var email = bestMatch(items, ['email', 'e-mail', 'mail'], ['card', 'cvv', 'vin'], 'INPUT');
        if (!email) {
            for (var e = 0; e < items.length; e++) {
                if (items[e].type === 'email') { email = { index: items[e].i, confidence: 25, tag: 'INPUT' }; break; }
            }
        }

        var cardNum = bestMatch(items, ['cc-number', 'card-number', 'cardnumber', 'card_number', 'ccnum', 'creditcard', 'cc_number', 'pan', 'card number', 'card no'], ['cvv', 'cvc', 'expir', 'month', 'year', 'email'], 'INPUT');
        if (!cardNum) {
            for (var c = 0; c < items.length; c++) {
                var ci = items[c];
                if (ci.tag === 'INPUT' && (ci.autocomplete === 'cc-number' || ci.inputMode === 'numeric') && (ci.maxLength >= 13 || ci.maxLength === 0 || ci.maxLength === -1)) {
                    var labelHint = ci.label.indexOf('card') >= 0 || ci.label.indexOf('number') >= 0 || ci.placeholder.indexOf('card') >= 0;
                    if (labelHint || ci.autocomplete === 'cc-number') { cardNum = { index: ci.i, confidence: 20, tag: 'INPUT' }; break; }
                }
            }
        }

        var expMonth = bestMatch(items, ['cc-exp-month', 'exp-month', 'expmonth', 'expirymonth', 'exp_month', 'card_month', 'ccmonth', 'month'], ['year', 'vin', 'email'], null);
        var expYear = bestMatch(items, ['cc-exp-year', 'exp-year', 'expyear', 'expiryyear', 'exp_year', 'card_year', 'ccyear', 'year'], ['month', 'vin', 'email'], null);

        if (!expMonth || !expYear) {
            var selects = items.filter(function(x) { return x.tag === 'SELECT'; });
            if (selects.length >= 2) {
                var s1 = selects[0], s2 = selects[1];
                if (!expMonth && (s1.name.indexOf('month') >= 0 || s1.id.indexOf('month') >= 0 || s1.label.indexOf('month') >= 0 || s1.autocomplete.indexOf('month') >= 0)) {
                    expMonth = { index: s1.i, confidence: 20, tag: 'SELECT' };
                }
                if (!expYear && (s2.name.indexOf('year') >= 0 || s2.id.indexOf('year') >= 0 || s2.label.indexOf('year') >= 0 || s2.autocomplete.indexOf('year') >= 0)) {
                    expYear = { index: s2.i, confidence: 20, tag: 'SELECT' };
                }
                if (!expMonth && !expYear) {
                    expMonth = { index: s1.i, confidence: 8, tag: 'SELECT' };
                    expYear = { index: s2.i, confidence: 8, tag: 'SELECT' };
                }
            }
        }

        var cvv = bestMatch(items, ['cvv', 'cvc', 'cv2', 'cvv2', 'csc', 'security-code', 'securitycode', 'security code', 'cc-csc', 'card-cvc', 'verification'], ['email', 'vin', 'card number', 'expir'], 'INPUT');
        if (!cvv) {
            for (var v = 0; v < items.length; v++) {
                var vi = items[v];
                if (vi.tag === 'INPUT' && vi.type === 'password' && (vi.maxLength === 3 || vi.maxLength === 4)) {
                    cvv = { index: vi.i, confidence: 15, tag: 'INPUT' }; break;
                }
                if (vi.tag === 'INPUT' && vi.inputMode === 'numeric' && (vi.maxLength === 3 || vi.maxLength === 4) && vi.autocomplete.indexOf('cc-csc') >= 0) {
                    cvv = { index: vi.i, confidence: 25, tag: 'INPUT' }; break;
                }
            }
        }

        return JSON.stringify({
            vin: vin, email: email, cardNum: cardNum,
            expMonth: expMonth, expYear: expYear, cvv: cvv,
            total: items.length
        });
    })()
    """

    func runSmartFieldDetection() async -> SmartFieldMap {
        guard let wv = webView else { return SmartFieldMap() }
        guard let result = try? await wv.evaluateJavaScript(Self.smartDetectionJS) as? String,
              let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SmartFieldMap()
        }

        var map = SmartFieldMap()
        map.totalElements = json["total"] as? Int ?? 0

        if let v = json["vin"] as? [String: Any] {
            map.vinIndex = v["index"] as? Int
            map.vinConfidence = v["confidence"] as? Int ?? 0
        }
        if let v = json["email"] as? [String: Any] {
            map.emailIndex = v["index"] as? Int
            map.emailConfidence = v["confidence"] as? Int ?? 0
        }
        if let v = json["cardNum"] as? [String: Any] {
            map.cardNumberIndex = v["index"] as? Int
            map.cardNumberConfidence = v["confidence"] as? Int ?? 0
        }
        if let v = json["expMonth"] as? [String: Any] {
            map.expMonthIndex = v["index"] as? Int
            map.expMonthConfidence = v["confidence"] as? Int ?? 0
        }
        if let v = json["expYear"] as? [String: Any] {
            map.expYearIndex = v["index"] as? Int
            map.expYearConfidence = v["confidence"] as? Int ?? 0
        }
        if let v = json["cvv"] as? [String: Any] {
            map.cvvIndex = v["index"] as? Int
            map.cvvConfidence = v["confidence"] as? Int ?? 0
        }

        return map
    }

    private static let smartFillJS: String = """
    (function(targetIndex, value, isSelect) {
        var els = document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="checkbox"]):not([type="radio"]), select, textarea');
        var visible = [];
        els.forEach(function(el) {
            if (el.offsetParent === null && el.offsetWidth === 0 && el.offsetHeight === 0) return;
            if (el.disabled) return;
            visible.push(el);
        });

        if (targetIndex < 0 || targetIndex >= els.length) return JSON.stringify({ok: false, reason: 'index_out_of_range', count: visible.length});

        var allEls = [];
        els.forEach(function(el) { allEls.push(el); });
        var el = allEls[targetIndex];
        if (!el) return JSON.stringify({ok: false, reason: 'element_null'});

        if (el.tagName === 'SELECT' || isSelect) {
            var matched = false;
            for (var i = 0; i < el.options.length; i++) {
                var optVal = el.options[i].value;
                var optText = el.options[i].text.trim();
                if (optVal === value || optText === value || optVal.indexOf(value) >= 0 || optText.indexOf(value) >= 0) {
                    el.selectedIndex = i;
                    matched = true;
                    break;
                }
            }
            if (!matched) {
                var numVal = parseInt(value, 10);
                for (var j = 0; j < el.options.length; j++) {
                    var ov = parseInt(el.options[j].value, 10);
                    var ot = parseInt(el.options[j].text.trim(), 10);
                    if (ov === numVal || ot === numVal) {
                        el.selectedIndex = j;
                        matched = true;
                        break;
                    }
                }
            }
            if (!matched && el.options.length > 1) {
                el.selectedIndex = 1;
                matched = true;
            }
            el.dispatchEvent(new Event('change', {bubbles: true}));
            el.dispatchEvent(new Event('input', {bubbles: true}));
            return JSON.stringify({ok: matched, reason: matched ? 'selected' : 'no_matching_option', tag: el.tagName, id: el.id, name: el.name});
        }

        el.focus();

        var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
        if (nativeInputValueSetter && nativeInputValueSetter.set) {
            nativeInputValueSetter.set.call(el, value);
        } else {
            el.value = value;
        }

        el.dispatchEvent(new Event('input', {bubbles: true}));
        el.dispatchEvent(new Event('change', {bubbles: true}));
        el.dispatchEvent(new KeyboardEvent('keydown', {bubbles: true, key: 'a'}));
        el.dispatchEvent(new KeyboardEvent('keyup', {bubbles: true, key: 'a'}));
        el.dispatchEvent(new Event('blur', {bubbles: true}));

        var actualValue = el.value;
        var fillOk = actualValue === value || actualValue.replace(/\\s/g, '') === value.replace(/\\s/g, '');

        return JSON.stringify({ok: fillOk, reason: fillOk ? 'filled' : 'value_mismatch', expected: value.substring(0, 10), actual: actualValue.substring(0, 10), tag: el.tagName, id: el.id, name: el.name});
    })
    """

    private func smartFill(index: Int?, value: String, fieldName: String, isSelect: Bool = false) async -> (success: Bool, detail: String) {
        guard let wv = webView else { return (false, "No webview") }
        guard let idx = index else { return (false, "\(fieldName) not detected by smart scan") }

        let escapedValue = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\"", with: "\\\"")
        let js = Self.smartFillJS + "(\(idx), '\(escapedValue)', \(isSelect))"

        guard let result = try? await wv.evaluateJavaScript(js) as? String,
              let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return await legacyFill(fieldName: fieldName, value: value, isSelect: isSelect)
        }

        let ok = json["ok"] as? Bool ?? false
        let reason = json["reason"] as? String ?? "unknown"
        let elId = json["id"] as? String ?? ""
        let elName = json["name"] as? String ?? ""

        if ok {
            return (true, "\(fieldName) smart-filled via #\(idx) [\(reason)] id=\(elId) name=\(elName)")
        }

        logger.log("Smart fill \(fieldName) partial: \(reason) — trying legacy fallback", category: .automation, level: .debug)
        return await legacyFill(fieldName: fieldName, value: value, isSelect: isSelect)
    }

    private func legacyFill(fieldName: String, value: String, isSelect: Bool) async -> (success: Bool, detail: String) {
        let selectors: [String]
        switch fieldName {
        case "VIN":
            selectors = [
                "input[name*='vin' i]", "input[id*='vin' i]", "input[placeholder*='vin' i]",
                "input[placeholder*='vehicle' i]", "input[name*='vehicle' i]",
                "input[aria-label*='vin' i]", "input[aria-label*='vehicle' i]",
                "input[autocomplete*='vin' i]"
            ]
        case "Email":
            selectors = [
                "input[type='email']", "input[name*='email' i]", "input[id*='email' i]",
                "input[placeholder*='email' i]", "input[autocomplete='email']",
                "input[aria-label*='email' i]"
            ]
        case "Card":
            selectors = [
                "input[autocomplete='cc-number']", "input[name*='cardnumber' i]",
                "input[name*='card_number' i]", "input[name*='card-number' i]",
                "input[name*='ccnum' i]", "input[id*='card' i]", "input[name*='card' i]",
                "input[placeholder*='card number' i]", "input[placeholder*='card no' i]",
                "input[aria-label*='card number' i]", "input[inputmode='numeric'][maxlength='16']",
                "input[inputmode='numeric'][maxlength='19']"
            ]
        case "ExpMonth":
            selectors = [
                "select[autocomplete='cc-exp-month']", "select[name*='month' i]", "select[id*='month' i]",
                "input[autocomplete='cc-exp-month']", "input[name*='month' i]",
                "select[aria-label*='month' i]", "input[placeholder*='mm' i]"
            ]
        case "ExpYear":
            selectors = [
                "select[autocomplete='cc-exp-year']", "select[name*='year' i]", "select[id*='year' i]",
                "input[autocomplete='cc-exp-year']", "input[name*='year' i]",
                "select[aria-label*='year' i]", "input[placeholder*='yy' i]"
            ]
        case "CVV":
            selectors = [
                "input[autocomplete='cc-csc']", "input[name*='cvv' i]", "input[name*='cvc' i]",
                "input[name*='csc' i]", "input[name*='security' i]", "input[id*='cvv' i]",
                "input[id*='cvc' i]", "input[placeholder*='cvv' i]", "input[placeholder*='cvc' i]",
                "input[placeholder*='security' i]", "input[aria-label*='cvv' i]",
                "input[aria-label*='security' i]", "input[maxlength='3'][inputmode='numeric']",
                "input[maxlength='4'][inputmode='numeric']"
            ]
        default:
            selectors = []
        }

        if isSelect {
            return await selectOrFillFieldLegacy(selectors: selectors, value: value, fieldName: fieldName)
        }
        return await fillFieldLegacy(selectors: selectors, value: value, fieldName: fieldName)
    }

    func fillVIN(_ vin: String) async -> (success: Bool, detail: String) {
        await smartFill(index: lastFieldMap?.vinIndex, value: vin, fieldName: "VIN")
    }

    func fillEmail(_ email: String) async -> (success: Bool, detail: String) {
        await smartFill(index: lastFieldMap?.emailIndex, value: email, fieldName: "Email")
    }

    func fillCardNumber(_ number: String) async -> (success: Bool, detail: String) {
        await smartFill(index: lastFieldMap?.cardNumberIndex, value: number, fieldName: "Card")
    }

    func fillExpMonth(_ month: String) async -> (success: Bool, detail: String) {
        let isSelect = lastFieldMap.map { $0.expMonthConfidence > 0 } ?? false
        return await smartFill(index: lastFieldMap?.expMonthIndex, value: month, fieldName: "ExpMonth", isSelect: isSelect)
    }

    func fillExpYear(_ year: String) async -> (success: Bool, detail: String) {
        let isSelect = lastFieldMap.map { $0.expYearConfidence > 0 } ?? false
        return await smartFill(index: lastFieldMap?.expYearIndex, value: year, fieldName: "ExpYear", isSelect: isSelect)
    }

    func fillCVV(_ cvv: String) async -> (success: Bool, detail: String) {
        await smartFill(index: lastFieldMap?.cvvIndex, value: cvv, fieldName: "CVV")
    }

    func clickShowMyResults() async -> (success: Bool, detail: String) {
        guard let wv = webView else { return (false, "No webview") }
        let js = """
        (function() {
            var btn = document.querySelector('button[type="submit"], input[type="submit"], button.btn-primary, button[id*="submit" i]');
            if (!btn) {
                var candidates = document.querySelectorAll('button, input[type="submit"], a.btn, a[role="button"]');
                var keywords = ['show', 'result', 'search', 'submit', 'pay', 'check', 'go', 'continue', 'next'];
                var bestBtn = null, bestScore = 0;
                candidates.forEach(function(c) {
                    var txt = c.textContent.toLowerCase().trim();
                    var score = 0;
                    keywords.forEach(function(kw) { if (txt.indexOf(kw) >= 0) score += 10; });
                    if (c.type === 'submit') score += 15;
                    if (c.classList.contains('btn-primary') || c.classList.contains('primary')) score += 5;
                    if (score > bestScore) { bestScore = score; bestBtn = c; }
                });
                btn = bestBtn;
            }
            if (btn) {
                btn.scrollIntoView({block: 'center'});
                btn.focus();
                btn.click();
                return 'clicked: ' + btn.textContent.trim().substring(0, 50);
            }
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

    func captureScreenshotWithCrop(cropRect: CGRect?, maxRetries: Int = 3) async -> ScreenshotResult {
        guard let wv = webView else {
            logger.log("Screenshot: no webview available", category: .screenshot, level: .error)
            return ScreenshotResult(full: nil, cropped: nil)
        }

        try? await Task.sleep(for: .milliseconds(300))

        var lastError: Error?
        for attempt in 1...maxRetries {
            let config = WKSnapshotConfiguration()
            do {
                let image = try await wv.takeSnapshot(configuration: config)

                if BlankScreenshotDetector.isBlank(image) && attempt < maxRetries {
                    logger.log("Screenshot attempt \(attempt)/\(maxRetries): blank image detected, retrying...", category: .screenshot, level: .warning)
                    try? await Task.sleep(for: .milliseconds(500 * attempt))
                    continue
                }

                let dims = "\(Int(image.size.width))x\(Int(image.size.height))@\(Int(image.scale))x"
                logger.log("Screenshot captured: \(dims) on attempt \(attempt)", category: .screenshot, level: .debug)

                var cropped: UIImage?
                if let rect = cropRect, rect != .zero, let cgImage = image.cgImage {
                    let imgW = CGFloat(cgImage.width)
                    let imgH = CGFloat(cgImage.height)
                    let viewW = image.size.width
                    let viewH = image.size.height
                    let scaleX = imgW / viewW
                    let scaleY = imgH / viewH
                    let pixelRect = CGRect(
                        x: rect.origin.x * scaleX,
                        y: rect.origin.y * scaleY,
                        width: rect.size.width * scaleX,
                        height: rect.size.height * scaleY
                    ).intersection(CGRect(x: 0, y: 0, width: imgW, height: imgH))

                    if pixelRect.width > 1, pixelRect.height > 1,
                       let cgCropped = cgImage.cropping(to: pixelRect) {
                        cropped = UIImage(cgImage: cgCropped, scale: image.scale, orientation: image.imageOrientation)
                    }
                }
                return ScreenshotResult(full: image, cropped: cropped)
            } catch {
                lastError = error
                logger.log("Screenshot attempt \(attempt)/\(maxRetries) failed: \(error.localizedDescription)", category: .screenshot, level: .warning)
                if attempt < maxRetries {
                    try? await Task.sleep(for: .milliseconds(300 * attempt))
                }
            }
        }

        logger.log("Screenshot FAILED after \(maxRetries) attempts: \(lastError?.localizedDescription ?? "unknown")", category: .screenshot, level: .error)
        return ScreenshotResult(full: nil, cropped: nil)
    }

    func checkForIframes() async -> Int {
        guard let wv = webView else { return 0 }
        let js = "document.querySelectorAll('iframe').length"
        guard let count = try? await wv.evaluateJavaScript(js) as? Int else { return 0 }
        return count
    }

    func verifyFieldValue(fieldName: String) async -> (filled: Bool, value: String) {
        guard let wv = webView else { return (false, "") }
        let idx: Int?
        switch fieldName {
        case "VIN": idx = lastFieldMap?.vinIndex
        case "Email": idx = lastFieldMap?.emailIndex
        case "Card": idx = lastFieldMap?.cardNumberIndex
        case "ExpMonth": idx = lastFieldMap?.expMonthIndex
        case "ExpYear": idx = lastFieldMap?.expYearIndex
        case "CVV": idx = lastFieldMap?.cvvIndex
        default: idx = nil
        }
        guard let i = idx else { return (false, "") }

        let js = """
        (function() {
            var els = document.querySelectorAll('input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="checkbox"]):not([type="radio"]), select, textarea');
            var allEls = [];
            els.forEach(function(el) { allEls.push(el); });
            if (\(i) >= allEls.length) return JSON.stringify({filled: false, value: ''});
            var el = allEls[\(i)];
            var val = el.tagName === 'SELECT' ? el.options[el.selectedIndex]?.value || '' : el.value;
            return JSON.stringify({filled: val.length > 0, value: val.substring(0, 30)});
        })()
        """
        guard let result = try? await wv.evaluateJavaScript(js) as? String,
              let data = result.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (false, "")
        }
        let filled = json["filled"] as? Bool ?? false
        let value = json["value"] as? String ?? ""
        return (filled, value)
    }

    private func fillFieldLegacy(selectors: [String], value: String, fieldName: String) async -> (success: Bool, detail: String) {
        guard let wv = webView else { return (false, "No webview") }
        let escapedValue = value.replacingOccurrences(of: "'", with: "\\'")
        for selector in selectors {
            let js = """
            (function() {
                var el = document.querySelector('\(selector)');
                if (el) {
                    el.focus();
                    var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
                    if (setter && setter.set) { setter.set.call(el, '\(escapedValue)'); } else { el.value = '\(escapedValue)'; }
                    el.dispatchEvent(new Event('input', {bubbles: true}));
                    el.dispatchEvent(new Event('change', {bubbles: true}));
                    el.dispatchEvent(new Event('blur', {bubbles: true}));
                    return 'legacy-filled via ' + '\(selector)';
                }
                return null;
            })()
            """
            if let result = try? await wv.evaluateJavaScript(js) as? String {
                return (true, "\(fieldName) \(result)")
            }
        }
        return (false, "\(fieldName) field not found (legacy fallback exhausted)")
    }

    private func selectOrFillFieldLegacy(selectors: [String], value: String, fieldName: String) async -> (success: Bool, detail: String) {
        guard let wv = webView else { return (false, "No webview") }
        let escapedValue = value.replacingOccurrences(of: "'", with: "\\'")
        for selector in selectors {
            let js = """
            (function() {
                var el = document.querySelector('\(selector)');
                if (!el) return null;
                if (el.tagName === 'SELECT') {
                    var numVal = parseInt('\(escapedValue)', 10);
                    for (var i = 0; i < el.options.length; i++) {
                        var ov = el.options[i].value;
                        var ot = el.options[i].text.trim();
                        if (ov === '\(escapedValue)' || ot === '\(escapedValue)' || ov.indexOf('\(escapedValue)') >= 0 || ot.indexOf('\(escapedValue)') >= 0 || parseInt(ov, 10) === numVal || parseInt(ot, 10) === numVal) {
                            el.selectedIndex = i;
                            el.dispatchEvent(new Event('change', {bubbles: true}));
                            return 'legacy-selected via ' + '\(selector)';
                        }
                    }
                }
                el.focus();
                var setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value');
                if (setter && setter.set) { setter.set.call(el, '\(escapedValue)'); } else { el.value = '\(escapedValue)'; }
                el.dispatchEvent(new Event('input', {bubbles: true}));
                el.dispatchEvent(new Event('change', {bubbles: true}));
                el.dispatchEvent(new Event('blur', {bubbles: true}));
                return 'legacy-filled via ' + '\(selector)';
            })()
            """
            if let result = try? await wv.evaluateJavaScript(js) as? String {
                return (true, "\(fieldName) \(result)")
            }
        }
        return (false, "\(fieldName) field not found (legacy fallback exhausted)")
    }
}

private class NavigationDelegate: NSObject, WKNavigationDelegate {
    let timeout: TimeInterval
    let completion: (Bool, String?, Int?) -> Void
    private var completed = false
    private var timeoutTask: Task<Void, Never>?
    var lastStatusCode: Int?

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
        completion(success, error, statusCode ?? lastStatusCode)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            finish(success: true, error: nil, statusCode: nil)
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

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let response = navigationResponse.response
        if let httpResponse = response as? HTTPURLResponse {
            let code = httpResponse.statusCode
            Task { @MainActor in
                self.lastStatusCode = code
            }
        }
        decisionHandler(.allow)
    }
}

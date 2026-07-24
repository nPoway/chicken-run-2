import SwiftUI
import UIKit
import WebKit

struct RoadToHeavenWebView: UIViewRepresentable {
    let url: URL
    let requestID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.userContentController.addUserScript(Self.inputZoomPreventionScript)
        configuration.userContentController.addUserScript(Self.casinoDiagnosticsScript)
        configuration.userContentController.add(context.coordinator, name: Self.diagnosticsHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = Self.userAgent
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.scrollView.keyboardDismissMode = .interactive
        webView.inputAssistantItem.leadingBarButtonGroups = []
        webView.inputAssistantItem.trailingBarButtonGroups = []
        context.coordinator.webView = webView
        context.coordinator.log("initial-load", url: url, details: "requestID=\(requestID.uuidString)")
        context.coordinator.logCasinoNative(
            "initial-load",
            url: url,
            details: ["requestID=\(requestID.uuidString)"]
        )
        context.coordinator.resetHTTPUpgradeAttempts()
        let request = URLRequest(url: url)
        context.coordinator.prepareForExplicitNavigation(request, in: webView)
        webView.load(request)
        context.coordinator.loadedURL = url
        context.coordinator.loadedRequestID = requestID
        return webView
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(
            forName: Self.diagnosticsHandlerName
        )
        coordinator.webView = nil
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedURL != url || context.coordinator.loadedRequestID != requestID else {
            context.coordinator.log(
                "update-skip",
                url: url,
                details: [
                    "requestID=\(requestID.uuidString)",
                    "webViewURL=\(webView.url?.absoluteString ?? "nil")"
                ].joined(separator: " ")
            )
            return
        }

        context.coordinator.log(
            "update-load",
            url: url,
            details: [
                "requestID=\(requestID.uuidString)",
                "previousRequestID=\(context.coordinator.loadedRequestID?.uuidString ?? "nil")",
                "webViewURL=\(webView.url?.absoluteString ?? "nil")"
            ].joined(separator: " ")
        )
        context.coordinator.logCasinoNative(
            "update-load",
            url: url,
            details: [
                "requestID=\(requestID.uuidString)",
                "previousRequestID=\(context.coordinator.loadedRequestID?.uuidString ?? "nil")",
                "webViewURL=\(webView.url?.absoluteString ?? "nil")"
            ]
        )
        context.coordinator.resetHTTPUpgradeAttempts()
        let request = URLRequest(url: url)
        context.coordinator.prepareForExplicitNavigation(request, in: webView)
        webView.load(request)
        context.coordinator.loadedURL = url
        context.coordinator.loadedRequestID = requestID
    }

    private static var userAgent: String {
        let systemVersion = UIDevice.current.systemVersion.replacingOccurrences(of: ".", with: "_")
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(systemVersion) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    }

    private static let diagnosticsHandlerName = "duperDiagnostics"

    private static let inputZoomPreventionScript = WKUserScript(
        source: """
        (function() {
            function applyInputZoomFix() {
                var head = document.head || document.getElementsByTagName('head')[0] || document.documentElement;
                if (!head) { return; }

                var viewport = document.querySelector('meta[name="viewport"]');
                if (!viewport) {
                    viewport = document.createElement('meta');
                    viewport.name = 'viewport';
                    head.appendChild(viewport);
                }
                viewport.setAttribute('content', 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover');

                if (!document.getElementById('duper-input-zoom-fix')) {
                    var style = document.createElement('style');
                    style.id = 'duper-input-zoom-fix';
                    style.textContent = 'input, textarea, select { font-size: 16px !important; }';
                    head.appendChild(style);
                }
            }

            applyInputZoomFix();
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', applyInputZoomFix);
            }
        })();
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: false
    )

    private static let casinoDiagnosticsScript = WKUserScript(
        source: """
        (function() {
            if (window.__duperCasinoDiagnosticsInstalled) { return; }
            window.__duperCasinoDiagnosticsInstalled = true;

            var lastViewportLogAt = 0;
            var lastInputLogAt = 0;

            function post(type, data) {
                try {
                    var payload = data || {};
                    payload.type = type;
                    payload.href = String(location.href || '');
                    payload.title = String(document.title || '');
                    payload.readyState = String(document.readyState || '');
                    payload.visibility = String(document.visibilityState || '');
                    window.webkit.messageHandlers.duperDiagnostics.postMessage(payload);
                } catch (e) {}
            }

            function compactText(value) {
                value = String(value || '').replace(/\\s+/g, ' ').trim();
                return value.length > 120 ? value.slice(0, 120) : value;
            }

            function selectorFor(element) {
                if (!element || !element.tagName) { return 'nil'; }
                var parts = [String(element.tagName).toLowerCase()];
                if (element.id) { parts.push('#' + element.id); }
                if (element.name) { parts.push('[name=' + element.name + ']'); }
                if (element.type) { parts.push('[type=' + element.type + ']'); }
                if (element.className && typeof element.className === 'string') {
                    var classes = element.className.trim().split(/\\s+/).slice(0, 3).join('.');
                    if (classes) { parts.push('.' + classes); }
                }
                return parts.join('');
            }

            function rectFor(element) {
                if (!element || !element.getBoundingClientRect) { return 'nil'; }
                var rect = element.getBoundingClientRect();
                return [
                    'x=' + Math.round(rect.x),
                    'y=' + Math.round(rect.y),
                    'w=' + Math.round(rect.width),
                    'h=' + Math.round(rect.height),
                    'top=' + Math.round(rect.top),
                    'bottom=' + Math.round(rect.bottom)
                ].join(',');
            }

            function viewportData() {
                var vv = window.visualViewport;
                return {
                    inner: Math.round(window.innerWidth || 0) + 'x' + Math.round(window.innerHeight || 0),
                    screen: Math.round(screen.width || 0) + 'x' + Math.round(screen.height || 0),
                    scroll: Math.round(window.scrollX || 0) + ',' + Math.round(window.scrollY || 0),
                    visual: vv ? [
                        Math.round(vv.width || 0) + 'x' + Math.round(vv.height || 0),
                        'offset=' + Math.round(vv.offsetLeft || 0) + ',' + Math.round(vv.offsetTop || 0),
                        'pageTop=' + Math.round(vv.pageTop || 0),
                        'scale=' + Number(vv.scale || 1).toFixed(2)
                    ].join(' ') : 'nil',
                    orientation: Math.round((screen.orientation && screen.orientation.angle) || window.orientation || 0),
                    active: selectorFor(document.activeElement)
                };
            }

            function eventElement(event) {
                var target = event.target;
                if (!target || target.nodeType !== 1) {
                    target = target && target.parentElement;
                }
                return target;
            }

            function closestInteractive(element) {
                if (!element || !element.closest) { return null; }
                return element.closest('a,button,input,textarea,select,[role="button"],[onclick],form');
            }

            function inputInfo(element) {
                var data = viewportData();
                data.element = selectorFor(element);
                data.rect = rectFor(element);
                data.valueLength = element && typeof element.value === 'string' ? element.value.length : -1;
                data.placeholder = compactText(element && element.placeholder);
                data.autocomplete = String((element && element.autocomplete) || '');
                data.inputMode = String((element && element.inputMode) || '');
                data.readOnly = !!(element && element.readOnly);
                data.disabled = !!(element && element.disabled);
                return data;
            }

            document.addEventListener('focusin', function(event) {
                post('focusin', inputInfo(eventElement(event)));
            }, true);

            document.addEventListener('focusout', function(event) {
                post('focusout', inputInfo(eventElement(event)));
            }, true);

            document.addEventListener('input', function(event) {
                var now = Date.now();
                if (now - lastInputLogAt < 250) { return; }
                lastInputLogAt = now;
                post('input', inputInfo(eventElement(event)));
            }, true);

            document.addEventListener('click', function(event) {
                var target = eventElement(event);
                var interactive = closestInteractive(target) || target;
                var link = interactive && interactive.closest ? interactive.closest('a') : null;
                post('click', Object.assign(viewportData(), {
                    element: selectorFor(target),
                    interactive: selectorFor(interactive),
                    rect: rectFor(interactive),
                    text: compactText((interactive && (interactive.innerText || interactive.textContent || interactive.value)) || ''),
                    link: link ? String(link.href || '') : ''
                }));
            }, true);

            document.addEventListener('submit', function(event) {
                var form = event.target;
                post('submit', Object.assign(viewportData(), {
                    element: selectorFor(form),
                    action: String((form && form.action) || ''),
                    method: String((form && form.method) || '')
                }));
            }, true);

            function logViewport(type) {
                var now = Date.now();
                if (type !== 'orientationchange' && now - lastViewportLogAt < 250) { return; }
                lastViewportLogAt = now;
                post(type, viewportData());
            }

            window.addEventListener('resize', function() { logViewport('window-resize'); }, true);
            window.addEventListener('orientationchange', function() { logViewport('orientationchange'); }, true);
            if (window.visualViewport) {
                window.visualViewport.addEventListener('resize', function() { logViewport('visual-viewport-resize'); }, true);
                window.visualViewport.addEventListener('scroll', function() { logViewport('visual-viewport-scroll'); }, true);
            }

            ['pagehide', 'pageshow', 'beforeunload'].forEach(function(name) {
                window.addEventListener(name, function(event) {
                    post(name, Object.assign(viewportData(), {
                        persisted: !!event.persisted
                    }));
                }, true);
            });

            document.addEventListener('visibilitychange', function() {
                post('visibilitychange', viewportData());
            }, true);

            ['pushState', 'replaceState'].forEach(function(method) {
                var original = history[method];
                if (typeof original !== 'function') { return; }
                history[method] = function() {
                    var targetURL = arguments.length > 2 && arguments[2] !== undefined ? String(arguments[2]) : '';
                    post('history-' + method, Object.assign(viewportData(), {
                        targetURL: targetURL
                    }));
                    return original.apply(this, arguments);
                };
            });

            window.addEventListener('popstate', function() { post('popstate', viewportData()); }, true);
            window.addEventListener('hashchange', function() { post('hashchange', viewportData()); }, true);

            post('diagnostics-installed', viewportData());
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        weak var webView: WKWebView?
        var loadedURL: URL?
        var loadedRequestID: UUID?
        private var lastRequestedURL: URL?
        private var lastRequestedRequest: URLRequest?
        private var redirectRecoveryAttempts = 0
        private var redirectRecoveryCheckpoints: Set<String> = []
        private var focusedInputWorkItem: DispatchWorkItem?
        private var focusedInputCheckGeneration = 0
        private var keyboardIsVisible = false
        private var keyboardSessionGeneration = 0
        private var pendingRestoreSessionID: Int?
        private var keyboardRestoreWorkItem: DispatchWorkItem?
        private var httpUpgradeAttempts: [String: Int] = [:]
        private var shouldRestoreInteractionAfterBackground = false

        private static let maxHTTPUpgradeAttemptsPerURL = 3
        private static let maxRedirectRecoveryAttempts = 5

        private enum HTTPUpgradeDecision {
            case notNeeded
            case loaded
            case blocked
        }

        override init() {
            super.init()
            registerKeyboardDiagnostics()
            registerApplicationLifecycleRecovery()
        }

        deinit {
            focusedInputWorkItem?.cancel()
            keyboardRestoreWorkItem?.cancel()
            NotificationCenter.default.removeObserver(self)
        }

        func log(_ event: String, url: URL?, details: String? = nil) {
            #if DEBUG
            var components = ["[DuperWebRedirect]", event]
            if let url {
                components.append(Self.compactLogComponent("url=\(url.absoluteString)"))
            }
            if let details, !details.isEmpty {
                components.append(Self.compactLogComponent(details))
            }

            NSLog("%@", components.joined(separator: " | "))
            #endif
        }

        func logCasinoNative(_ event: String, url: URL?, details: [String] = []) {
            #if DEBUG
            var components = ["[DuperCasinoNav]", "native-\(event)"]
            if let url {
                components.append(Self.compactLogComponent("url=\(url.absoluteString)"))
            }
            components.append(contentsOf: details.map(Self.compactLogComponent))

            NSLog("%@", components.joined(separator: " | "))
            #endif
        }

        func resetHTTPUpgradeAttempts() {
            httpUpgradeAttempts.removeAll()
        }

        private func logCasinoKeyboard(_ event: String, details: [String] = []) {
            #if DEBUG
            var components = ["[DuperCasinoKeyboard]", event]
            components.append(contentsOf: details.map(Self.compactLogComponent))

            NSLog("%@", components.joined(separator: " | "))
            #endif
        }

        private func logCasinoInput(_ event: String, details: [String] = []) {
            #if DEBUG
            var components = ["[DuperCasinoInput]", event]
            components.append(contentsOf: details.map(Self.compactLogComponent))

            NSLog("%@", components.joined(separator: " | "))
            #endif
        }

        #if DEBUG
        private static func compactLogComponent(_ value: String) -> String {
            guard value.count > 600 else { return value }
            return "\(value.prefix(600))..."
        }
        #endif

        func prepareForExplicitNavigation(_ request: URLRequest, in webView: WKWebView) {
            resetRedirectRecoveryState()
            recordMainFrameRequest(request)
            setNavigationInteractionBlocked(true, in: webView)
        }

        private func recordMainFrameRequest(_ request: URLRequest) {
            lastRequestedRequest = request
            lastRequestedURL = request.url
        }

        private func setNavigationInteractionBlocked(_ blocked: Bool, in webView: WKWebView) {
            let shouldEnableInteraction = !blocked
            guard webView.isUserInteractionEnabled != shouldEnableInteraction else { return }
            webView.isUserInteractionEnabled = shouldEnableInteraction
        }

        private func finishTopLevelNavigation(in webView: WKWebView) {
            setNavigationInteractionBlocked(false, in: webView)
            resetRedirectRecoveryState()
        }

        private func registerApplicationLifecycleRecovery() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidEnterBackground),
                name: UIApplication.didEnterBackgroundNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applicationDidBecomeActive),
                name: UIApplication.didBecomeActiveNotification,
                object: nil
            )
        }

        @objc private func applicationDidEnterBackground() {
            guard let webView else { return }
            shouldRestoreInteractionAfterBackground = !webView.isUserInteractionEnabled
            guard shouldRestoreInteractionAfterBackground else { return }

            log(
                "backgrounded-with-navigation-interaction-blocked",
                url: webView.url ?? lastRequestedURL
            )
        }

        @objc private func applicationDidBecomeActive() {
            guard shouldRestoreInteractionAfterBackground else { return }
            shouldRestoreInteractionAfterBackground = false
            guard let webView else { return }

            log(
                "restore-navigation-interaction-after-background",
                url: webView.url ?? lastRequestedURL,
                details: "isLoading=\(webView.isLoading)"
            )
            setNavigationInteractionBlocked(false, in: webView)
        }

        private func resetRedirectRecoveryState() {
            redirectRecoveryAttempts = 0
            redirectRecoveryCheckpoints.removeAll(keepingCapacity: true)
        }

        private func registerKeyboardDiagnostics() {
            let notifications: [(Notification.Name, Selector)] = [
                (UIResponder.keyboardWillShowNotification, #selector(keyboardWillShow(_:))),
                (UIResponder.keyboardDidShowNotification, #selector(keyboardDidShow(_:))),
                (UIResponder.keyboardWillHideNotification, #selector(keyboardWillHide(_:))),
                (UIResponder.keyboardDidHideNotification, #selector(keyboardDidHide(_:))),
                (UIResponder.keyboardWillChangeFrameNotification, #selector(keyboardWillChangeFrame(_:))),
                (UIResponder.keyboardDidChangeFrameNotification, #selector(keyboardDidChangeFrame(_:)))
            ]

            for (name, selector) in notifications {
                NotificationCenter.default.addObserver(
                    self,
                    selector: selector,
                    name: name,
                    object: nil
                )
            }
        }

        @objc private func keyboardWillShow(_ notification: Notification) {
            activateKeyboardSessionIfNeeded()
            logKeyboardNotification("will-show", notification: notification)
        }

        @objc private func keyboardDidShow(_ notification: Notification) {
            activateKeyboardSessionIfNeeded()
            logKeyboardNotification("did-show", notification: notification)
            scheduleFocusedInputVisibilityCheck(source: "keyboard-did-show")
        }

        @objc private func keyboardWillHide(_ notification: Notification) {
            let sessionID = keyboardSessionGeneration
            pendingRestoreSessionID = sessionID
            keyboardIsVisible = false
            cancelFocusedInputVisibilityCheck()
            deactivateKeyboardScrollSession(sessionID: sessionID)
            logKeyboardNotification("will-hide", notification: notification)
        }

        @objc private func keyboardDidHide(_ notification: Notification) {
            logKeyboardNotification("did-hide", notification: notification)
            guard !keyboardIsVisible else { return }
            cancelFocusedInputVisibilityCheck()

            if let sessionID = pendingRestoreSessionID {
                scheduleKeyboardScrollSessionRestore(sessionID: sessionID)
            }
        }

        @objc private func keyboardWillChangeFrame(_ notification: Notification) {
            logKeyboardNotification("will-change-frame", notification: notification)
        }

        @objc private func keyboardDidChangeFrame(_ notification: Notification) {
            logKeyboardNotification("did-change-frame", notification: notification)
        }

        private func logKeyboardNotification(_ event: String, notification: Notification) {
            let userInfo = notification.userInfo ?? [:]
            let beginFrame = (userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect) ?? .null
            let endFrame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect) ?? .null
            let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue ?? -1
            let curve = (userInfo[UIResponder.keyboardAnimationCurveUserInfoKey] as? NSNumber)?.intValue ?? -1

            logCasinoKeyboard(
                event,
                details: [
                    "begin=\(Self.rectDescription(beginFrame))",
                    "end=\(Self.rectDescription(endFrame))",
                    "duration=\(String(format: "%.3f", duration))",
                    "curve=\(curve)",
                    "orientation=\(UIDevice.current.orientation.debugLabel)"
                ]
            )
        }

        private func activateKeyboardSessionIfNeeded() {
            if !keyboardIsVisible {
                keyboardSessionGeneration += 1
            }
            keyboardIsVisible = true
            keyboardRestoreWorkItem?.cancel()
            keyboardRestoreWorkItem = nil
            pendingRestoreSessionID = nil
            captureKeyboardScrollSessionIfNeeded(sessionID: keyboardSessionGeneration)
        }

        private func scheduleKeyboardScrollSessionRestore(sessionID: Int) {
            keyboardRestoreWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard
                    !self.keyboardIsVisible,
                    self.pendingRestoreSessionID == sessionID
                else { return }

                self.restoreKeyboardScrollSession(sessionID: sessionID)
                self.pendingRestoreSessionID = nil
                self.keyboardRestoreWorkItem = nil
            }
            keyboardRestoreWorkItem = workItem

            // iOS emits a zero-duration hide/show pair when changing input types.
            // Waiting here prevents the old field from restoring scroll while the
            // next field and keyboard are still settling.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32, execute: workItem)
        }

        private func cancelFocusedInputVisibilityCheck() {
            focusedInputWorkItem?.cancel()
            focusedInputWorkItem = nil
            focusedInputCheckGeneration += 1
            webView?.evaluateJavaScript(
                "window.__duperKeyboardLatestCheck = \(focusedInputCheckGeneration);"
            )
        }

        private func scheduleFocusedInputVisibilityCheck(
            source: String,
            delay: TimeInterval = 0.08
        ) {
            guard
                keyboardIsVisible,
                let webView,
                webView.bounds.width > webView.bounds.height
            else { return }

            focusedInputWorkItem?.cancel()
            focusedInputCheckGeneration += 1
            let checkID = focusedInputCheckGeneration
            let sessionID = keyboardSessionGeneration
            webView.evaluateJavaScript("window.__duperKeyboardLatestCheck = \(checkID);")

            let workItem = DispatchWorkItem { [weak self] in
                self?.ensureFocusedInputVisible(
                    source: source,
                    checkID: checkID,
                    sessionID: sessionID
                )
            }
            focusedInputWorkItem = workItem

            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        private func captureKeyboardScrollSessionIfNeeded(sessionID: Int) {
            guard
                let webView,
                webView.bounds.width > webView.bounds.height
            else { return }

            let script = """
            (function() {
                var element = document.activeElement;
                if (!element || !element.matches || !element.matches('input, textarea, select, [contenteditable=""], [contenteditable="true"]')) {
                    return { status: 'not-editable' };
                }

                var existing = window.__duperKeyboardScrollSession;
                if (existing && existing.active && existing.id === \(sessionID)) {
                    return { status: 'existing', session: existing.id };
                }
                if (existing) {
                    existing.id = \(sessionID);
                    existing.active = true;
                    return {
                        status: 'resumed',
                        session: existing.id,
                        entries: existing.entries.length,
                        scroll: Math.round(window.scrollX || 0) + ',' + Math.round(window.scrollY || 0)
                    };
                }

                var entries = [];
                function addNode(node) {
                    if (!node || entries.some(function(entry) { return entry.node === node; })) { return; }
                    entries.push({
                        node: node,
                        top: Number(node.scrollTop || 0),
                        left: Number(node.scrollLeft || 0),
                        programmaticTop: 0,
                        programmaticLeft: 0
                    });
                }

                addNode(document.scrollingElement || document.documentElement);
                var current = element.parentElement;
                while (current && current !== document.body && current !== document.documentElement) {
                    if (current.scrollHeight > current.clientHeight + 1 || current.scrollWidth > current.clientWidth + 1) {
                        addNode(current);
                    }
                    current = current.parentElement;
                }

                window.__duperKeyboardScrollSession = {
                    id: \(sessionID),
                    active: true,
                    userInteracted: false,
                    windowX: Number(window.scrollX || 0),
                    windowY: Number(window.scrollY || 0),
                    entries: entries
                };

                if (!window.__duperKeyboardInteractionTrackerInstalled) {
                    var markUserInteraction = function() {
                        var session = window.__duperKeyboardScrollSession;
                        if (session && session.active) {
                            session.userInteracted = true;
                        }
                    };
                    document.addEventListener('touchmove', markUserInteraction, { capture: true, passive: true });
                    document.addEventListener('wheel', markUserInteraction, { capture: true, passive: true });
                    window.__duperKeyboardInteractionTrackerInstalled = true;
                }

                return {
                    status: 'captured',
                    session: \(sessionID),
                    entries: entries.length,
                    scroll: Math.round(window.scrollX || 0) + ',' + Math.round(window.scrollY || 0)
                };
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] result, error in
                if let error {
                    self?.logCasinoInput(
                        "keyboard-session-capture",
                        details: ["session=\(sessionID)", "error=\(error.localizedDescription)"]
                    )
                    return
                }

                guard let result = result as? [String: Any] else { return }
                let status = result["status"] as? String
                guard status == "captured" || status == "resumed" else { return }

                self?.logCasinoInput(
                    "keyboard-session-capture",
                    details: [
                        "session=\(sessionID)",
                        "status=\(status ?? "unknown")",
                        "entries=\(Self.shortValueDescription(result["entries"] ?? 0))",
                        "scroll=\(Self.shortValueDescription(result["scroll"] ?? ""))"
                    ]
                )
            }
        }

        private func deactivateKeyboardScrollSession(sessionID: Int) {
            webView?.evaluateJavaScript(
                """
                (function() {
                    var session = window.__duperKeyboardScrollSession;
                    if (session && session.id === \(sessionID)) {
                        session.active = false;
                    }
                })();
                """
            )
        }

        private func restoreKeyboardScrollSession(sessionID: Int) {
            guard let webView else { return }

            let script = """
            (function() {
                var session = window.__duperKeyboardScrollSession;
                if (!session || session.id !== \(sessionID)) {
                    return { status: 'no-matching-session', session: \(sessionID) };
                }

                var restoreID = Number(session.id);
                session.active = false;

                function clamp(value, minimum, maximum) {
                    return Math.max(minimum, Math.min(maximum, value));
                }

                function restoreIfCurrent() {
                    if (window.__duperKeyboardScrollSession !== session
                        || Number(session.id) !== restoreID
                        || session.active) {
                        return false;
                    }

                    for (var index = 0; index < session.entries.length; index++) {
                        var entry = session.entries[index];
                        var node = entry.node;
                        if (!node || !node.isConnected) { continue; }

                        var maxTop = Math.max(0, node.scrollHeight - node.clientHeight);
                        var maxLeft = Math.max(0, node.scrollWidth - node.clientWidth);
                        var targetTop = session.userInteracted
                            ? Number(node.scrollTop || 0) - Number(entry.programmaticTop || 0)
                            : Number(entry.top || 0);
                        var targetLeft = session.userInteracted
                            ? Number(node.scrollLeft || 0) - Number(entry.programmaticLeft || 0)
                            : Number(entry.left || 0);

                        node.scrollTop = clamp(targetTop, 0, maxTop);
                        node.scrollLeft = clamp(targetLeft, 0, maxLeft);
                    }

                    if (!session.userInteracted) {
                        window.scrollTo(session.windowX, session.windowY);
                    }
                    return true;
                }

                restoreIfCurrent();
                setTimeout(restoreIfCurrent, 80);
                setTimeout(function() {
                    restoreIfCurrent();
                    if (window.__duperKeyboardScrollSession === session
                        && Number(session.id) === restoreID
                        && !session.active) {
                        window.__duperKeyboardScrollSession = null;
                    }
                }, 220);

                return {
                    status: 'restoring',
                    session: session.id,
                    userInteracted: session.userInteracted ? 1 : 0,
                    target: Math.round(session.windowX) + ',' + Math.round(session.windowY)
                };
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] result, error in
                var details = ["session=\(sessionID)"]
                if let error {
                    details.append("error=\(error.localizedDescription)")
                } else if let result = result as? [String: Any] {
                    for key in ["status", "userInteracted", "target"] {
                        if let value = result[key] {
                            details.append("\(key)=\(Self.shortValueDescription(value))")
                        }
                    }
                }
                self?.logCasinoInput("keyboard-session-restore", details: details)
            }
        }

        private func ensureFocusedInputVisible(
            source: String,
            checkID: Int,
            sessionID: Int
        ) {
            guard let webView, webView.bounds.width > webView.bounds.height else { return }

            let script = """
            function editable(element) {
                return element && element.matches && element.matches('input, textarea, select, [contenteditable=""], [contenteditable="true"]');
            }

            function labelFor(node) {
                if (!node || !node.tagName) { return 'unknown'; }
                return [
                    node.tagName.toLowerCase(),
                    node.id ? ('#' + node.id) : '',
                    node.className && typeof node.className === 'string' ? ('.' + node.className.trim().split(/\\s+/).slice(0, 2).join('.')) : ''
                ].join('');
            }

            function elementLabel(element) {
                return [
                    element.tagName ? element.tagName.toLowerCase() : 'unknown',
                    element.id ? ('#' + element.id) : '',
                    element.name ? ('[name=' + element.name + ']') : '',
                    element.type ? ('[type=' + element.type + ']') : ''
                ].join('');
            }

            function measure(element, viewport) {
                var rect = element.getBoundingClientRect();
                return {
                    width: Number(viewport.width),
                    height: Number(viewport.height),
                    offsetLeft: Number(viewport.offsetLeft),
                    offsetTop: Number(viewport.offsetTop),
                    pageLeft: Number(viewport.pageLeft),
                    pageTop: Number(viewport.pageTop),
                    scrollX: Number(window.scrollX || 0),
                    scrollY: Number(window.scrollY || 0),
                    rectTop: Number(rect.top),
                    rectBottom: Number(rect.bottom)
                };
            }

            function nearlyEqual(left, right) {
                return Math.abs(left - right) < 0.75;
            }

            function sameGeometry(left, right) {
                return nearlyEqual(left.width, right.width)
                    && nearlyEqual(left.height, right.height)
                    && nearlyEqual(left.offsetLeft, right.offsetLeft)
                    && nearlyEqual(left.offsetTop, right.offsetTop)
                    && nearlyEqual(left.pageLeft, right.pageLeft)
                    && nearlyEqual(left.pageTop, right.pageTop)
                    && nearlyEqual(left.scrollX, right.scrollX)
                    && nearlyEqual(left.scrollY, right.scrollY)
                    && nearlyEqual(left.rectTop, right.rectTop)
                    && nearlyEqual(left.rectBottom, right.rectBottom);
            }

            function activeSession() {
                var session = window.__duperKeyboardScrollSession;
                if (!session || !session.active || session.id !== Number(sessionID)) { return null; }
                if (window.__duperKeyboardLatestCheck !== Number(checkID)) { return null; }
                return session;
            }

            var session = activeSession();
            if (!session) {
                return { status: 'cancelled-or-no-session', session: Number(sessionID) };
            }

            var element = document.activeElement;
            if (!editable(element)) {
                return { status: 'not-editable' };
            }

            var viewport = window.visualViewport;
            if (!viewport) {
                return { status: 'no-visual-viewport' };
            }

            var previous = measure(element, viewport);
            var stableSamples = 0;
            var attempts = 0;

            for (attempts = 1; attempts <= 15; attempts++) {
                await new Promise(function(resolve) { setTimeout(resolve, 80); });

                if (!activeSession()) {
                    return { status: 'superseded', session: Number(sessionID), stability: attempts };
                }
                if (document.activeElement !== element) {
                    return { status: 'focus-changed', session: Number(sessionID), stability: attempts };
                }

                var current = measure(element, viewport);
                if (sameGeometry(previous, current)) {
                    stableSamples += 1;
                } else {
                    stableSamples = 0;
                }
                previous = current;

                if (stableSamples >= 4) { break; }
            }

            if (stableSamples < 4) {
                return {
                    status: 'viewport-unstable',
                    session: Number(sessionID),
                    stability: attempts,
                    visual: Math.round(viewport.width) + 'x' + Math.round(viewport.height) + ' offset=' + Math.round(viewport.offsetLeft) + ',' + Math.round(viewport.offsetTop) + ' pageTop=' + Math.round(viewport.pageTop),
                    scroll: Math.round(window.scrollX || 0) + ',' + Math.round(window.scrollY || 0)
                };
            }

            var topLimit = 10;
            var bottomLimit = viewport.height - 10;

            function screenRect(rect) {
                var scrollTop = Number(window.scrollY || 0);
                var pageTop = Number(viewport.pageTop);
                if (!Number.isFinite(pageTop)) {
                    pageTop = scrollTop + Number(viewport.offsetTop || 0);
                }

                var layoutToVisualOffset = scrollTop - pageTop;
                return {
                    top: rect.top + layoutToVisualOffset,
                    bottom: rect.bottom + layoutToVisualOffset
                };
            }

            function isVisible(rect) {
                var visualRect = screenRect(rect);
                return visualRect.top >= topLimit && visualRect.bottom <= bottomLimit;
            }

            function visibilityDelta(rect) {
                var visualRect = screenRect(rect);
                if (visualRect.top < topLimit) { return visualRect.top - topLimit; }
                if (visualRect.bottom > bottomLimit) { return visualRect.bottom - bottomLimit; }
                return 0;
            }

            function addCandidate(candidates, node) {
                if (!node || candidates.some(function(candidate) { return candidate === node; })) { return; }
                candidates.push(node);
            }

            var pageScroller = document.scrollingElement || document.documentElement;

            function scrollCandidates(node) {
                var candidates = [];

                var current = node.parentElement;
                while (current && current !== document.body && current !== document.documentElement) {
                    if (current.scrollHeight > current.clientHeight + 1) {
                        addCandidate(candidates, current);
                    }
                    current = current.parentElement;
                }
                return candidates;
            }

            function sessionEntry(node) {
                for (var index = 0; index < session.entries.length; index++) {
                    if (session.entries[index].node === node) { return session.entries[index]; }
                }

                var entry = {
                    node: node,
                    top: Number(node.scrollTop || 0),
                    left: Number(node.scrollLeft || 0),
                    programmaticTop: 0,
                    programmaticLeft: 0
                };
                session.entries.push(entry);
                return entry;
            }

            var rect = element.getBoundingClientRect();
            var wasHidden = !isVisible(rect);
            var actions = [];

            if (wasHidden) {
                var candidates = scrollCandidates(element);
                for (var pass = 0; pass < 4; pass++) {
                    if (!activeSession() || document.activeElement !== element) {
                        return { status: 'superseded-during-scroll', session: Number(sessionID) };
                    }

                    var currentRect = element.getBoundingClientRect();
                    if (isVisible(currentRect)) { break; }

                    var delta = visibilityDelta(currentRect);
                    if (Math.abs(delta) < 0.75) { break; }

                    var moved = false;
                    for (var index = 0; index < candidates.length; index++) {
                        var candidate = candidates[index];
                        var beforeScroll = candidate === pageScroller
                            ? Number(window.scrollY || candidate.scrollTop || 0)
                            : Number(candidate.scrollTop || 0);
                        var maxScroll = Math.max(0, candidate.scrollHeight - candidate.clientHeight);
                        var nextScroll = Math.max(0, Math.min(maxScroll, beforeScroll + delta));
                        if (Math.abs(nextScroll - beforeScroll) < 0.75) { continue; }

                        if (candidate === pageScroller) {
                            window.scrollTo(window.scrollX || 0, nextScroll);
                        } else {
                            candidate.scrollTop = nextScroll;
                        }

                        var actualScroll = candidate === pageScroller
                            ? Number(window.scrollY || candidate.scrollTop || 0)
                            : Number(candidate.scrollTop || 0);
                        if (Math.abs(actualScroll - beforeScroll) < 0.75) { continue; }

                        var entry = sessionEntry(candidate);
                        entry.programmaticTop += actualScroll - beforeScroll;
                        actions.push(labelFor(candidate) + ':' + Math.round(beforeScroll) + '->' + Math.round(actualScroll));
                        moved = true;
                        break;
                    }

                    if (!moved) { break; }
                }
            }

            var updatedRect = element.getBoundingClientRect();
            var finalVisible = isVisible(updatedRect);
            var originalScreenRect = screenRect(rect);
            var updatedScreenRect = screenRect(updatedRect);
            return {
                status: wasHidden ? (finalVisible ? 'scrolled-visible' : 'scrolled-still-hidden') : 'visible',
                session: Number(sessionID),
                stability: attempts,
                element: elementLabel(element),
                before: 'top=' + Math.round(rect.top) + ',bottom=' + Math.round(rect.bottom),
                after: 'top=' + Math.round(updatedRect.top) + ',bottom=' + Math.round(updatedRect.bottom),
                beforeScreen: 'top=' + Math.round(originalScreenRect.top) + ',bottom=' + Math.round(originalScreenRect.bottom),
                afterScreen: 'top=' + Math.round(updatedScreenRect.top) + ',bottom=' + Math.round(updatedScreenRect.bottom),
                actions: actions.join(';'),
                visual: Math.round(viewport.width) + 'x' + Math.round(viewport.height) + ' offset=' + Math.round(viewport.offsetLeft) + ',' + Math.round(viewport.offsetTop) + ' pageTop=' + Math.round(viewport.pageTop),
                scroll: Math.round(window.scrollX || 0) + ',' + Math.round(window.scrollY || 0)
            };
            """

            Task { @MainActor [weak self, weak webView] in
                guard let webView else { return }
                var details = ["source=\(source)"]

                do {
                    let value = try await webView.callAsyncJavaScript(
                        script,
                        arguments: ["checkID": checkID, "sessionID": sessionID],
                        in: nil,
                        contentWorld: .page
                    )

                    if let value = value as? [String: Any] {
                        for key in ["status", "session", "stability", "element", "before", "after", "beforeScreen", "afterScreen", "actions", "visual", "scroll"] {
                            if let item = value[key] {
                                details.append("\(key)=\(Self.shortValueDescription(item))")
                            }
                        }
                    } else if let value {
                        details.append("result=\(Self.shortValueDescription(value))")
                    } else {
                        details.append("result=nil")
                    }
                } catch {
                    details.append("error=\(error.localizedDescription)")
                }

                self?.logCasinoInput("native-focused-input-visibility-check", details: details)
            }
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard
                message.name == RoadToHeavenWebView.diagnosticsHandlerName,
                let body = message.body as? [String: Any],
                let type = body["type"] as? String
            else {
                logCasino("[DuperCasinoJS]", event: "invalid-message", body: [:])
                return
            }

            logCasino(Self.casinoTag(for: type), event: type, body: body)

            guard message.frameInfo.isMainFrame else { return }
            switch type {
            case "focusin":
                captureKeyboardScrollSessionIfNeeded(sessionID: keyboardSessionGeneration)
            case "orientationchange":
                scheduleFocusedInputVisibilityCheck(
                    source: "orientationchange",
                    delay: 0.45
                )
            default:
                break
            }
        }

        private func logCasino(_ tag: String, event: String, body: [String: Any]) {
            #if DEBUG
            let ignoredKeys = Set(["type"])
            var components = [tag, event]

            for key in body.keys.map({ String($0) }).sorted() where !ignoredKeys.contains(key) {
                let value = body[key] ?? ""
                components.append("\(key)=\(Self.shortValueDescription(value))")
            }

            NSLog("%@", components.joined(separator: " | "))
            #endif
        }

        private static func casinoTag(for event: String) -> String {
            switch event {
            case "focusin", "focusout", "input":
                return "[DuperCasinoInput]"
            case "window-resize", "orientationchange", "visual-viewport-resize", "visual-viewport-scroll":
                return "[DuperCasinoViewport]"
            case "click", "submit",
                 "history-pushState", "history-replaceState",
                 "popstate", "hashchange",
                 "pagehide", "pageshow", "beforeunload", "visibilitychange",
                 "diagnostics-installed":
                return "[DuperCasinoNav]"
            default:
                return "[DuperCasinoJS]"
            }
        }

        private static func shortValueDescription(_ value: Any) -> String {
            let description: String
            if let string = value as? String {
                description = string
            } else if let number = value as? NSNumber {
                description = number.stringValue
            } else if let bool = value as? Bool {
                description = bool ? "true" : "false"
            } else {
                description = String(describing: value)
            }

            let sanitized = description
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")

            guard sanitized.count > 500 else { return sanitized }
            return "\(sanitized.prefix(500))..."
        }

        private static func rectDescription(_ rect: CGRect) -> String {
            guard !rect.isNull else { return "null" }

            return [
                "x=\(Int(rect.origin.x.rounded()))",
                "y=\(Int(rect.origin.y.rounded()))",
                "w=\(Int(rect.width.rounded()))",
                "h=\(Int(rect.height.rounded()))"
            ].joined(separator: ",")
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                log(
                    "decide-policy-no-url",
                    url: nil,
                    details: "type=\(navigationAction.navigationType.debugLabel)"
                )
                decisionHandler(.allow)
                return
            }

            let isMainFrameNavigation = navigationAction.targetFrame?.isMainFrame ?? true

            log(
                "decide-policy",
                url: url,
                details: [
                    "type=\(navigationAction.navigationType.debugLabel)",
                    "target=\(navigationAction.targetFrame?.debugLabel ?? "nil")",
                    "mainDocument=\(navigationAction.request.mainDocumentURL?.absoluteString ?? "nil")"
                ].joined(separator: " ")
            )
            logCasinoNative(
                "decide-policy",
                url: url,
                details: [
                    "type=\(navigationAction.navigationType.debugLabel)",
                    "target=\(navigationAction.targetFrame?.debugLabel ?? "nil")",
                    "mainDocument=\(navigationAction.request.mainDocumentURL?.absoluteString ?? "nil")"
                ]
            )

            if url.isWebViewInternalScheme {
                log(
                    "internal-webview-url-allow",
                    url: url,
                    details: "target=\(navigationAction.targetFrame?.debugLabel ?? "nil")"
                )
                logCasinoNative(
                    "internal-webview-url-allow",
                    url: url,
                    details: ["target=\(navigationAction.targetFrame?.debugLabel ?? "nil")"]
                )
                decisionHandler(.allow)
                return
            }

            if url.isAppStoreURL {
                log("app-store-open-cancel-webview", url: url)
                logCasinoNative("app-store-open-cancel-webview", url: url)
                if isMainFrameNavigation {
                    finishTopLevelNavigation(in: webView)
                }
                decisionHandler(.cancel)
                UIApplication.shared.open(url)
                return
            }

            if isMainFrameNavigation {
                switch upgradeHTTPNavigationIfNeeded(
                    request: navigationAction.request,
                    url: url,
                    webView: webView,
                    source: "decide-policy"
                ) {
                case .notNeeded:
                    break
                case .loaded, .blocked:
                    decisionHandler(.cancel)
                    return
                }
            }

            guard url.isHTTPFamily else {
                log("external-open-cancel-webview", url: url)
                logCasinoNative("external-open-cancel-webview", url: url)
                UIApplication.shared.open(url)
                if isMainFrameNavigation {
                    finishTopLevelNavigation(in: webView)
                }
                decisionHandler(.cancel)
                return
            }

            if isMainFrameNavigation {
                recordMainFrameRequest(navigationAction.request)
                setNavigationInteractionBlocked(true, in: webView)
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            guard navigationAction.targetFrame == nil, let url = navigationAction.request.url else {
                log(
                    "create-webview-ignored",
                    url: navigationAction.request.url,
                    details: "target=\(navigationAction.targetFrame?.debugLabel ?? "non-nil")"
                )
                return nil
            }

            log("create-webview-target-blank", url: url)
            logCasinoNative("create-webview-target-blank", url: url)

            if url.isAppStoreURL {
                log("target-blank-app-store-open", url: url)
                logCasinoNative("target-blank-app-store-open", url: url)
                finishTopLevelNavigation(in: webView)
                UIApplication.shared.open(url)
                return nil
            }

            switch upgradeHTTPNavigationIfNeeded(
                request: navigationAction.request,
                url: url,
                webView: webView,
                source: "target-blank"
            ) {
            case .loaded, .blocked:
                return nil
            case .notNeeded:
                break
            }

            if url.isHTTPFamily {
                prepareForExplicitNavigation(navigationAction.request, in: webView)
                webView.load(navigationAction.request)
            } else if url.isWebViewInternalScheme {
                log("target-blank-internal-url-skip-external-open", url: url)
                logCasinoNative("target-blank-internal-url-skip-external-open", url: url)
            } else {
                log("target-blank-external-open", url: url)
                logCasinoNative("target-blank-external-open", url: url)
                UIApplication.shared.open(url)
            }

            return nil
        }

        private func upgradeHTTPNavigationIfNeeded(
            request: URLRequest,
            url: URL,
            webView: WKWebView,
            source: String
        ) -> HTTPUpgradeDecision {
            guard let upgradedURL = url.httpUpgradedToHTTPS else {
                return .notNeeded
            }

            let attemptKey = url.absoluteString
            let attempt = (httpUpgradeAttempts[attemptKey] ?? 0) + 1
            httpUpgradeAttempts[attemptKey] = attempt

            guard attempt <= Self.maxHTTPUpgradeAttemptsPerURL else {
                let details = [
                    "source=\(source)",
                    "attempt=\(attempt)",
                    "maxAttempts=\(Self.maxHTTPUpgradeAttemptsPerURL)",
                    "upgradedURL=\(upgradedURL.absoluteString)",
                    "reason=possible-http-downgrade-loop"
                ].joined(separator: " ")
                log("http-to-https-upgrade-blocked", url: url, details: details)
                logCasinoNative("http-to-https-upgrade-blocked", url: url, details: details.components(separatedBy: " "))
                finishTopLevelNavigation(in: webView)
                return .blocked
            }

            var upgradedRequest = request
            upgradedRequest.url = upgradedURL
            recordMainFrameRequest(upgradedRequest)
            setNavigationInteractionBlocked(true, in: webView)

            let details = [
                "source=\(source)",
                "attempt=\(attempt)",
                "upgradedURL=\(upgradedURL.absoluteString)"
            ].joined(separator: " ")
            log("http-to-https-upgrade-load", url: url, details: details)
            logCasinoNative("http-to-https-upgrade-load", url: url, details: details.components(separatedBy: " "))
            DispatchQueue.main.async { [weak webView] in
                webView?.load(upgradedRequest)
            }
            return .loaded
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            setNavigationInteractionBlocked(true, in: webView)
            log(
                "did-start-provisional",
                url: webView.url ?? lastRequestedURL,
                details: "lastRequested=\(lastRequestedURL?.absoluteString ?? "nil")"
            )
            logCasinoNative(
                "did-start-provisional",
                url: webView.url ?? lastRequestedURL,
                details: ["lastRequested=\(lastRequestedURL?.absoluteString ?? "nil")"]
            )
        }

        func webView(
            _ webView: WKWebView,
            didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!
        ) {
            log(
                "did-receive-server-redirect",
                url: webView.url ?? lastRequestedURL,
                details: "lastRequested=\(lastRequestedURL?.absoluteString ?? "nil")"
            )
            logCasinoNative(
                "did-receive-server-redirect",
                url: webView.url ?? lastRequestedURL,
                details: ["lastRequested=\(lastRequestedURL?.absoluteString ?? "nil")"]
            )
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            log("did-commit", url: webView.url ?? lastRequestedURL)
            logCasinoNative("did-commit", url: webView.url ?? lastRequestedURL)
            finishTopLevelNavigation(in: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            resetHTTPUpgradeAttempts()
            log("did-finish", url: webView.url ?? lastRequestedURL)
            logCasinoNative("did-finish", url: webView.url ?? lastRequestedURL)
            finishTopLevelNavigation(in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            logFailure("did-fail-provisional", webView: webView, error: error)
            logCasinoFailure("did-fail-provisional", webView: webView, error: error)
            guard !error.isCancelledNavigation else { return }
            if !recoverFromTooManyRedirectsIfNeeded(webView: webView, error: error) {
                finishTopLevelNavigation(in: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            logFailure("did-fail", webView: webView, error: error)
            logCasinoFailure("did-fail", webView: webView, error: error)
            guard !error.isCancelledNavigation else { return }
            if !recoverFromTooManyRedirectsIfNeeded(webView: webView, error: error) {
                finishTopLevelNavigation(in: webView)
            }
        }

        private func logFailure(_ event: String, webView: WKWebView, error: Error) {
            let nsError = error as NSError
            log(
                event,
                url: webView.url ?? lastRequestedURL,
                details: [
                    "domain=\(nsError.domain)",
                    "code=\(nsError.code)",
                    "description=\(nsError.localizedDescription)",
                    "failingURL=\(Self.errorURL(nsError, key: NSURLErrorFailingURLErrorKey)?.absoluteString ?? "nil")",
                    "failingURLString=\(Self.errorString(nsError, key: NSURLErrorFailingURLStringErrorKey) ?? "nil")",
                    "lastRequested=\(lastRequestedURL?.absoluteString ?? "nil")"
                ].joined(separator: " ")
            )
        }

        private static func errorURL(_ error: NSError, key: String) -> URL? {
            error.userInfo[key] as? URL
        }

        private static func errorString(_ error: NSError, key: String) -> String? {
            error.userInfo[key] as? String
        }

        private func logCasinoFailure(_ event: String, webView: WKWebView, error: Error) {
            let nsError = error as NSError
            logCasinoNative(
                event,
                url: webView.url ?? lastRequestedURL,
                details: [
                    "domain=\(nsError.domain)",
                    "code=\(nsError.code)",
                    "description=\(nsError.localizedDescription)",
                    "failingURL=\(Self.errorURL(nsError, key: NSURLErrorFailingURLErrorKey)?.absoluteString ?? "nil")",
                    "failingURLString=\(Self.errorString(nsError, key: NSURLErrorFailingURLStringErrorKey) ?? "nil")",
                    "lastRequested=\(lastRequestedURL?.absoluteString ?? "nil")"
                ]
            )
        }

        @discardableResult
        private func recoverFromTooManyRedirectsIfNeeded(webView: WKWebView, error: Error) -> Bool {
            let nsError = error as NSError
            guard
                nsError.domain == NSURLErrorDomain,
                nsError.code == NSURLErrorHTTPTooManyRedirects
            else {
                return false
            }

            guard
                let request = lastRequestedRequest,
                let url = request.url,
                url.isHTTPFamily
            else {
                log("too-many-redirects-recovery-missing-request", url: lastRequestedURL)
                return false
            }

            let checkpoint = "\(request.httpMethod ?? "GET") \(url.absoluteString)"
            log(
                "too-many-redirects",
                url: url,
                details: [
                    "attempt=\(redirectRecoveryAttempts + 1)",
                    "maxAttempts=\(Self.maxRedirectRecoveryAttempts)"
                ].joined(separator: " ")
            )

            guard redirectRecoveryAttempts < Self.maxRedirectRecoveryAttempts else {
                log(
                    "too-many-redirects-recovery-exhausted",
                    url: url,
                    details: "attempts=\(redirectRecoveryAttempts)"
                )
                return false
            }

            guard redirectRecoveryCheckpoints.insert(checkpoint).inserted else {
                log(
                    "too-many-redirects-recovery-loop-detected",
                    url: url,
                    details: "attempts=\(redirectRecoveryAttempts)"
                )
                return false
            }

            redirectRecoveryAttempts += 1
            setNavigationInteractionBlocked(true, in: webView)
            webView.stopLoading()
            log(
                "too-many-redirects-recovery-load",
                url: url,
                details: "attempt=\(redirectRecoveryAttempts)"
            )
            webView.load(request)
            return true
        }
    }
}

private extension WKNavigationType {
    var debugLabel: String {
        switch self {
        case .linkActivated:
            return "linkActivated"
        case .formSubmitted:
            return "formSubmitted"
        case .backForward:
            return "backForward"
        case .reload:
            return "reload"
        case .formResubmitted:
            return "formResubmitted"
        case .other:
            return "other"
        @unknown default:
            return "unknown"
        }
    }
}

private extension WKFrameInfo {
    var debugLabel: String {
        isMainFrame ? "main" : "child"
    }
}

private extension UIDeviceOrientation {
    var debugLabel: String {
        switch self {
        case .unknown:
            return "unknown"
        case .portrait:
            return "portrait"
        case .portraitUpsideDown:
            return "portraitUpsideDown"
        case .landscapeLeft:
            return "landscapeLeft"
        case .landscapeRight:
            return "landscapeRight"
        case .faceUp:
            return "faceUp"
        case .faceDown:
            return "faceDown"
        @unknown default:
            return "unknown"
        }
    }
}

private extension URL {
    var isAppStoreURL: Bool {
        guard let scheme = scheme?.lowercased() else { return false }

        if ["itms", "itmss", "itms-apps", "itms-appss"].contains(scheme) {
            return true
        }

        guard scheme == "http" || scheme == "https", let host = host?.lowercased() else {
            return false
        }

        let appStoreHosts = ["apps.apple.com", "itunes.apple.com", "appsto.re", "appstore.com"]
        return appStoreHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    var isHTTPFamily: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    var httpUpgradedToHTTPS: URL? {
        guard
            scheme?.lowercased() == "http",
            var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        components.scheme = "https"
        return components.url
    }

    var isWebViewInternalScheme: Bool {
        guard let scheme = scheme?.lowercased() else { return false }
        return scheme == "about" || scheme == "blob" || scheme == "data" || scheme == "javascript"
    }
}

private extension Error {
    var isCancelledNavigation: Bool {
        let error = self as NSError
        return error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled
    }
}

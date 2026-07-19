import SwiftUI
import WebKit

struct HCaptchaChallengeView: View {
    let siteKey: String
    let onSolved: (String) -> Void
    let onCancel: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("安全验证")
                        .font(.headline)
                    Text("完成验证后将发送短信验证码")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(18)

            Divider()

            HCaptchaWebView(
                siteKey: siteKey,
                onSolved: onSolved,
                onError: { errorMessage = $0 }
            )
            .frame(minWidth: 420, minHeight: 360)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.error)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
        }
        .background(AppTheme.surface)
    }
}

private struct HCaptchaWebView: NSViewRepresentable {
    let siteKey: String
    let onSolved: (String) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSolved: onSolved, onError: onError)
    }

    func makeNSView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "captchaSolved")
        controller.add(context.coordinator, name: "captchaError")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.underPageBackgroundColor = .clear
        context.coordinator.siteKey = siteKey
        load(in: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSolved = onSolved
        context.coordinator.onError = onError
        if context.coordinator.siteKey != siteKey {
            context.coordinator.siteKey = siteKey
            load(in: webView)
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "captchaSolved")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "captchaError")
        webView.stopLoading()
    }

    private func load(in webView: WKWebView) {
        let encodedSiteKey = (try? String(
            data: JSONEncoder().encode(siteKey),
            encoding: .utf8
        )) ?? "\"\""
        let html = """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            html, body { height: 100%; margin: 0; background: transparent; }
            body { display: grid; place-items: center; font-family: -apple-system, sans-serif; }
            #captcha { min-height: 90px; }
          </style>
          <script>
            function captchaLoaded() {
              try {
                hcaptcha.render('captcha', {
                  sitekey: \(encodedSiteKey),
                  theme: 'light',
                  callback: function(token) {
                    window.webkit.messageHandlers.captchaSolved.postMessage(token);
                  },
                  'error-callback': function(code) {
                    window.webkit.messageHandlers.captchaError.postMessage(String(code || '验证失败'));
                  },
                  'expired-callback': function() {
                    window.webkit.messageHandlers.captchaError.postMessage('验证已过期，请重新完成');
                  }
                });
              } catch (error) {
                window.webkit.messageHandlers.captchaError.postMessage('验证组件加载失败');
              }
            }
          </script>
          <script src="https://js.hcaptcha.com/1/api.js?onload=captchaLoaded&render=explicit&hl=zh-CN"
                  async defer></script>
        </head>
        <body><div id="captcha"></div></body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: APIConfig.socketBaseURL)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onSolved: (String) -> Void
        var onError: (String) -> Void
        var siteKey = ""

        init(onSolved: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.onSolved = onSolved
            self.onError = onError
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let value = message.body as? String else { return }
            if message.name == "captchaSolved", !value.isEmpty {
                onSolved(value)
            } else if message.name == "captchaError" {
                onError("人机验证失败：\(value)")
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            onError("验证组件加载失败，请检查网络后重试")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            onError("验证组件加载失败，请检查网络后重试")
        }
    }
}

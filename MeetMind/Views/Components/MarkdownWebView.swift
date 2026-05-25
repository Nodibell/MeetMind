//
//  MarkdownWebView.swift
//  MeetMind
//
//  Created by Oleksii Chumak on 11.05.2026.
//

import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String
    var dynamicHeight: Binding<CGFloat>? = nil
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownWebView
        
        init(_ parent: MarkdownWebView) {
            self.parent = parent
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "heightHandler",
                  let height = message.body as? CGFloat else { return }
            
            DispatchQueue.main.async {
                let currentHeight = self.parent.dynamicHeight?.wrappedValue ?? 0
                let newHeight = max(height, 40)
                if abs(currentHeight - newHeight) > 2 {
                    self.parent.dynamicHeight?.wrappedValue = newHeight
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight || document.body.scrollHeight") { [weak self] result, error in
                if let height = result as? CGFloat {
                    DispatchQueue.main.async {
                        let currentHeight = self?.parent.dynamicHeight?.wrappedValue ?? 0
                        let newHeight = max(height, 40)
                        if abs(currentHeight - newHeight) > 2 {
                            self?.parent.dynamicHeight?.wrappedValue = newHeight
                        }
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = preferences
        
        if dynamicHeight != nil {
            let controller = WKUserContentController()
            controller.add(context.coordinator, name: "heightHandler")
            config.userContentController = controller
        }
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        webView.navigationDelegate = context.coordinator
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let html = generateHTML(from: markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    private func preprocessMarkdown(_ markdown: String) -> String {
        let clean = markdown.replacingOccurrences(of: "\r", with: "")
        let lines = clean.components(separatedBy: "\n")
        var processedLines: [String] = []
        
        for i in 0..<lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.hasPrefix("|") {
                if i > 0 {
                    let prevLine = processedLines.last ?? ""
                    let prevTrimmed = prevLine.trimmingCharacters(in: .whitespaces)
                    if !prevTrimmed.isEmpty && !prevTrimmed.hasPrefix("|") {
                        processedLines.append("") // Guarantee newline before table
                    }
                }
            }
            processedLines.append(line)
        }
        
        return processedLines.joined(separator: "\n")
    }
    
    private func generateHTML(from markdown: String) -> String {
        let preprocessed = preprocessMarkdown(markdown)
        let escapedMarkdown = preprocessed
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.css">
            <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/katex.min.js"></script>
            <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.9/dist/contrib/auto-render.min.js"></script>
            <style>
                :root {
                    color-scheme: light dark;
                    --text-color: #1d1d1f;
                    --bg-color: transparent;
                    --link-color: #0066cc;
                    --code-bg: #f5f5f7;
                    --border-color: #d2d2d7;
                }
                @media (prefers-color-scheme: dark) {
                    :root {
                        --text-color: #f5f5f7;
                        --link-color: #2997ff;
                        --code-bg: #1d1d1f;
                        --border-color: #424245;
                    }
                }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    color: var(--text-color);
                    background-color: var(--bg-color);
                    line-height: 1.6;
                    padding: 16px;
                    margin: 0;
                    font-size: 15px;
                }
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 16px;
                    font-weight: 600;
                    line-height: 1.25;
                }
                p, ul, ol {
                    margin-top: 0;
                    margin-bottom: 16px;
                }
                ul, ol {
                    padding-left: 20px;
                }
                li {
                    margin-bottom: 6px;
                }
                li::marker {
                    color: var(--link-color);
                    font-weight: bold;
                }
                
                /* Hide bullets for task lists */
                li:has(input[type="checkbox"]) {
                    list-style-type: none;
                    padding-left: 0;
                    margin-left: 0;
                }
                
                /* Checkbox styling */
                input[type="checkbox"] {
                    appearance: none;
                    -webkit-appearance: none;
                    width: 16px;
                    height: 16px;
                    border: 1.5px solid var(--border-color);
                    border-radius: 4px;
                    margin-right: 8px;
                    vertical-align: middle;
                    position: relative;
                    top: -1px;
                    cursor: pointer;
                    background-color: var(--bg-color);
                    transition: all 0.2s ease;
                }
                input[type="checkbox"]:checked {
                    background-color: var(--link-color);
                    border-color: var(--link-color);
                }
                input[type="checkbox"]:checked::after {
                    content: "✓";
                    position: absolute;
                    top: 50%;
                    left: 50%;
                    transform: translate(-50%, -50%);
                    color: white;
                    font-size: 10px;
                    font-weight: bold;
                }
                
                a { color: var(--link-color); text-decoration: none; }
                a:hover { text-decoration: underline; }
                code {
                    font-family: ui-monospace, SFMono-Regular, SF Mono, Menlo, Consolas, Liberation Mono, monospace;
                    background-color: var(--code-bg);
                    padding: 0.2em 0.4em;
                    border-radius: 6px;
                    font-size: 85%;
                }
                pre {
                    background-color: var(--code-bg);
                    padding: 16px;
                    border-radius: 8px;
                    overflow: auto;
                }
                pre code { background-color: transparent; padding: 0; }
                blockquote {
                    margin: 0;
                    padding: 0 1em;
                    color: #86868b;
                    border-left: 0.25em solid var(--border-color);
                }
                table {
                    border-spacing: 0;
                    border-collapse: collapse;
                    margin-bottom: 16px;
                    width: 100%;
                    overflow: auto;
                    display: block;
                }
                th, td {
                    padding: 8px 13px;
                    border: 1px solid var(--border-color);
                }
                th {
                    font-weight: 600;
                    background-color: var(--code-bg);
                }
                tr:nth-child(2n) {
                    background-color: rgba(128, 128, 128, 0.05);
                }
                
                /* Selection styling */
                ::selection {
                    background-color: rgba(0, 102, 204, 0.3);
                }
            </style>
        </head>
        <body>
            <div id="content"></div>
            <script>
                // Render markdown
                document.getElementById('content').innerHTML = marked.parse(`\(escapedMarkdown)`);
                // Render math formulas
                document.addEventListener("DOMContentLoaded", function() {
                    renderMathInElement(document.getElementById('content'), {
                        delimiters: [
                            {left: '$$', right: '$$', display: true},
                            {left: '$', right: '$', display: false},
                            {left: '\\\\(', right: '\\\\)', display: false},
                            {left: '\\\\[', right: '\\\\]', display: true}
                        ],
                        throwOnError : false
                    });
                    sendHeight();
                });

                function sendHeight() {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.heightHandler) {
                        setTimeout(function() {
                            var height = document.documentElement.scrollHeight || document.body.scrollHeight;
                            window.webkit.messageHandlers.heightHandler.postMessage(height);
                        }, 50);
                    }
                }
                
                window.onload = sendHeight;
                
                if (window.ResizeObserver) {
                    const resizeObserver = new ResizeObserver(sendHeight);
                    resizeObserver.observe(document.body);
                }
            </script>
        </body>
        </html>
        """
    }
}

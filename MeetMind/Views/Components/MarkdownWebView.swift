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
    
    func makeNSView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = preferences
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // Transparent background
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = generateHTML(from: markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    private func generateHTML(from markdown: String) -> String {
        // Escape the markdown string for JavaScript
        let escapedMarkdown = markdown
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
                }
                th, td {
                    padding: 6px 13px;
                    border: 1px solid var(--border-color);
                }
                th { font-weight: 600; }
                
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
                });
            </script>
        </body>
        </html>
        """
    }
}

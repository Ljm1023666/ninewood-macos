import SwiftUI

/// ChatGPT 风格：把助手 Markdown 排成可读聊天块（标题 / 列表 / 代码 / 段落）。
struct NWMarkdownChatText: View {
    let markdown: String
    var isUser: Bool = false
    var maxContentWidth: CGFloat = 560

    var body: some View {
        Group {
            if isUser {
                Text(markdown)
                    .font(.body)
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: maxContentWidth, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(Self.parseBlocks(markdown).enumerated()), id: \.offset) { _, block in
                        blockView(block)
                    }
                }
                .frame(maxWidth: maxContentWidth, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineMarkdown(text)
                .font(headingFont(level))
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.top, level <= 2 ? 4 : 0)
                .textSelection(.enabled)

        case .paragraph(let text):
            inlineMarkdown(text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(width: 14, alignment: .center)
                        inlineMarkdown(item)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 22, alignment: .trailing)
                        inlineMarkdown(item)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(AppTheme.primary.opacity(0.55))
                    .frame(width: 3)
                inlineMarkdown(text)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 10)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)

        case .code(let language, let code):
            VStack(alignment: .leading, spacing: 6) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(AppTheme.fill.opacity(0.65), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        case .horizontalRule:
            Divider()
                .padding(.vertical, 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .body.weight(.semibold)
        }
    }

    private func inlineMarkdown(_ raw: String) -> Text {
        let cleaned = raw
            .replacingOccurrences(of: "**", with: "**") // keep
        if let attributed = try? AttributedString(
            markdown: cleaned,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }

    // MARK: - Parse

    private enum MDBlock {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bulletList([String])
        case numberedList([String])
        case quote(String)
        case code(language: String?, code: String)
        case horizontalRule
    }

    private static func parseBlocks(_ source: String) -> [MDBlock] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var blocks: [MDBlock] = []
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Fenced code ```
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                i += 1
                var codeLines: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 } // closing fence
                blocks.append(.code(
                    language: language.isEmpty ? nil : language,
                    code: codeLines.joined(separator: "\n")
                ))
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Heading
            if let heading = matchHeading(trimmed) {
                blocks.append(.heading(level: heading.0, text: heading.1))
                i += 1
                continue
            }

            // Bullet list
            if isBullet(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { break }
                    if isBullet(t) {
                        items.append(stripBullet(t))
                        i += 1
                    } else if t.hasPrefix("  ") || t.hasPrefix("\t"), !items.isEmpty {
                        items[items.count - 1] += " " + t.trimmingCharacters(in: .whitespaces)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items))
                continue
            }

            // Numbered list
            if isNumbered(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { break }
                    if isNumbered(t) {
                        items.append(stripNumbered(t))
                        i += 1
                    } else if t.hasPrefix("  ") || t.hasPrefix("\t"), !items.isEmpty {
                        items[items.count - 1] += " " + t.trimmingCharacters(in: .whitespaces)
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.numberedList(items))
                continue
            }

            // Quote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix(">") {
                        quoteLines.append(String(t.drop(while: { $0 == ">" || $0 == " " })))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.quote(quoteLines.joined(separator: "\n")))
                continue
            }

            // Paragraph (consume until blank / structural)
            var para: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if t.hasPrefix("```") || t.hasPrefix("#") || isBullet(t) || isNumbered(t)
                    || t.hasPrefix(">") || t == "---" || t == "***" || t == "___" {
                    break
                }
                para.append(t)
                i += 1
            }
            blocks.append(.paragraph(para.joined(separator: " ")))
        }

        return blocks
    }

    private static func matchHeading(_ line: String) -> (Int, String)? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level >= 1, level <= 6, line.count > level, line[line.index(line.startIndex, offsetBy: level)] == " " else {
            return nil
        }
        let text = String(line.dropFirst(level + 1)).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ")
    }

    private static func stripBullet(_ line: String) -> String {
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
            return String(line.dropFirst(2))
        }
        return line
    }

    private static func isNumbered(_ line: String) -> Bool {
        guard let dot = line.firstIndex(of: ".") else { return false }
        let prefix = line[..<dot]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return false }
        let after = line.index(after: dot)
        return after < line.endIndex && line[after] == " "
    }

    private static func stripNumbered(_ line: String) -> String {
        guard let dot = line.firstIndex(of: ".") else { return line }
        let after = line.index(after: dot)
        guard after < line.endIndex else { return line }
        return String(line[line.index(after: after)...]).trimmingCharacters(in: .whitespaces)
    }
}

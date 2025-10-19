import SwiftUI

struct AIResponseView: View {
    @Environment(\.dismiss) private var dismiss
    let question: String
    let response: String

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)

                        Text("AI Assistant")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    .padding(.top)

                    // Question Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Question")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                        }

                        Text(question)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                    }

                    // Response Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("AI Assistant Response")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                        }

                        Group {
                            if response.isEmpty {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Processing...")
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                            } else {
                                MarkdownText(response)
                                    .padding()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    }

                    // Done Button
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
                    .padding(.bottom, 20)
                }
                .padding()
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Close") {
                    dismiss()
                }
            )
        }
    }
}

struct MarkdownText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(parseMarkdown(text), id: \.id) { element in
                switch element.type {
                case .heading1:
                    Text(element.content)
                        .font(.title)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .heading2:
                    Text(element.content)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .heading3:
                    Text(element.content)
                        .font(.title3)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .bulletPoint:
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.body)
                            .foregroundColor(.primary)
                        MarkdownTextView(text: element.content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .numberedPoint:
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(element.number ?? 1).")
                            .font(.body)
                            .foregroundColor(.primary)
                        MarkdownTextView(text: element.content)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .bold:
                    Text(element.content)
                        .font(.body)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code:
                    Text(element.content)
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .paragraph:
                    MarkdownTextView(text: element.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parseMarkdown(_ text: String) -> [MarkdownElement] {
        let lines = text.components(separatedBy: .newlines)
        var elements: [MarkdownElement] = []
        var currentParagraph = ""
        var numberedIndex = 1

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.isEmpty {
                if !currentParagraph.isEmpty {
                    elements.append(MarkdownElement(type: .paragraph, content: currentParagraph.trimmingCharacters(in: .whitespaces)))
                    currentParagraph = ""
                }
                continue
            }

            if trimmedLine.hasPrefix("# ") {
                if !currentParagraph.isEmpty {
                    elements.append(MarkdownElement(type: .paragraph, content: currentParagraph.trimmingCharacters(in: .whitespaces)))
                    currentParagraph = ""
                }
                elements.append(MarkdownElement(type: .heading1, content: String(trimmedLine.dropFirst(2))))
            } else if trimmedLine.hasPrefix("## ") {
                if !currentParagraph.isEmpty {
                    elements.append(MarkdownElement(type: .paragraph, content: currentParagraph.trimmingCharacters(in: .whitespaces)))
                    currentParagraph = ""
                }
                elements.append(MarkdownElement(type: .heading2, content: String(trimmedLine.dropFirst(3))))
            } else if trimmedLine.hasPrefix("### ") {
                if !currentParagraph.isEmpty {
                    elements.append(MarkdownElement(type: .paragraph, content: currentParagraph.trimmingCharacters(in: .whitespaces)))
                    currentParagraph = ""
                }
                elements.append(MarkdownElement(type: .heading3, content: String(trimmedLine.dropFirst(4))))
            } else if trimmedLine.hasPrefix("- ") || trimmedLine.hasPrefix("* ") {
                if !currentParagraph.isEmpty {
                    elements.append(MarkdownElement(type: .paragraph, content: currentParagraph.trimmingCharacters(in: .whitespaces)))
                    currentParagraph = ""
                }
                elements.append(MarkdownElement(type: .bulletPoint, content: String(trimmedLine.dropFirst(2))))
            } else if trimmedLine.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil {
                if !currentParagraph.isEmpty {
                    elements.append(MarkdownElement(type: .paragraph, content: currentParagraph.trimmingCharacters(in: .whitespaces)))
                    currentParagraph = ""
                }
                let content = trimmedLine.replacingOccurrences(of: #"^\d+\.\s"#, with: "", options: .regularExpression)
                elements.append(MarkdownElement(type: .numberedPoint, content: content, number: numberedIndex))
                numberedIndex += 1
            } else if trimmedLine.hasPrefix("```") {
                // Skip code block markers for now
                continue
            } else {
                if !currentParagraph.isEmpty {
                    currentParagraph += " "
                }
                currentParagraph += trimmedLine
            }
        }

        if !currentParagraph.isEmpty {
            elements.append(MarkdownElement(type: .paragraph, content: currentParagraph.trimmingCharacters(in: .whitespaces)))
        }

        return elements
    }

    private func parseInlineMarkdown(_ text: String) -> String {
        var result = text

        // Remove markdown link syntax [text](url) and keep just the text
        let linkPattern = #"\[([^\]]+)\]\([^)]+\)"#
        if let regex = try? NSRegularExpression(pattern: linkPattern, options: []) {
            result = regex.stringByReplacingMatches(in: result, options: [], range: NSRange(location: 0, length: result.count), withTemplate: "$1")
        }

        return result
    }
}

struct MarkdownTextView: View {
    let text: String

    var body: some View {
        buildAttributedText()
    }

    private func buildAttributedText() -> Text {
        let parts = parseMarkdownText(text)

        return parts.reduce(Text("")) { result, part in
            switch part.style {
            case .normal:
                return result + Text(part.text)
            case .bold:
                return result + Text(part.text)
                    .fontWeight(.bold)
            case .code:
                return result + Text(part.text)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .font(.body)
        .foregroundColor(.primary)
    }

    private func parseMarkdownText(_ input: String) -> [TextPart] {
        // First remove link syntax, then parse bold text
        let textWithoutLinks = removeMarkdownLinks(input)
        return parseBoldText(textWithoutLinks)
    }

    private func removeMarkdownLinks(_ text: String) -> String {
        let linkPattern = #"\[([^\]]+)\]\([^)]+\)"#
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: []) else { return text }
        return regex.stringByReplacingMatches(in: text, options: [], range: NSRange(location: 0, length: text.count), withTemplate: "$1")
    }


    private func parseBoldText(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            if let boldStart = text.range(of: "**", range: currentIndex..<text.endIndex) {
                // Add text before bold
                if boldStart.lowerBound > currentIndex {
                    let beforeText = String(text[currentIndex..<boldStart.lowerBound])
                    parts.append(TextPart(text: beforeText, style: .normal))
                }

                // Find the closing **
                let searchStart = boldStart.upperBound
                if let boldEnd = text.range(of: "**", range: searchStart..<text.endIndex) {
                    // Extract bold text
                    let boldText = String(text[searchStart..<boldEnd.lowerBound])
                    parts.append(TextPart(text: boldText, style: .bold))
                    currentIndex = boldEnd.upperBound
                } else {
                    // No closing **, treat as normal text
                    let remainingText = String(text[boldStart.lowerBound..<text.endIndex])
                    parts.append(TextPart(text: remainingText, style: .normal))
                    break
                }
            } else {
                // No more bold text, add remaining as normal
                let remainingText = String(text[currentIndex..<text.endIndex])
                parts.append(TextPart(text: remainingText, style: .normal))
                break
            }
        }

        return parts
    }
}

struct TextPart {
    let text: String
    let style: TextStyle
}


enum TextStyle {
    case normal, bold, code
}

struct MarkdownElement {
    let id = UUID()
    let type: MarkdownType
    let content: String
    let number: Int?

    init(type: MarkdownType, content: String, number: Int? = nil) {
        self.type = type
        self.content = content
        self.number = number
    }
}

enum MarkdownType {
    case heading1, heading2, heading3
    case bulletPoint, numberedPoint
    case bold, code
    case paragraph
}

#Preview {
    AIResponseView(
        question: "What's the weather like today?",
        response: """
# Weather Information

I'm sorry, but I don't have access to real-time weather data. However, here are some **reliable ways** to get current weather information:

## Recommended Sources:
- Weather apps on your phone
- Weather.com website
- Voice assistants with internet access

### Quick Tips:
- Check local weather stations
- Use GPS-based weather services
- Set up weather alerts for severe conditions

You can also ask me general questions about weather patterns or climate!
"""
    )
}
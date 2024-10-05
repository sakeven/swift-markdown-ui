import SwiftUI
import LaTeXSwiftUI
import MathJaxSwift
import SVGView

extension Sequence where Element == InlineNode {
    @MainActor func renderText(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    images: [String: Image],
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer
  ) -> Text {
    var renderer = TextInlineRenderer(
      baseURL: baseURL,
      textStyles: textStyles,
      images: images,
      softBreakMode: softBreakMode,
      attributes: attributes
    )
    renderer.render(self)
    return renderer.result
  }
}

private struct TextInlineRenderer {
  var result = Text("")

  private let baseURL: URL?
  private let textStyles: InlineTextStyles
  private let images: [String: Image]
  private let softBreakMode: SoftBreak.Mode
  private let attributes: AttributeContainer
  private var shouldSkipNextWhitespace = false

  init(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    images: [String: Image],
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer
  ) {
    self.baseURL = baseURL
    self.textStyles = textStyles
    self.images = images
    self.softBreakMode = softBreakMode
    self.attributes = attributes
  }

    @MainActor mutating func render<S: Sequence>(_ inlines: S) where S.Element == InlineNode {
    for inline in inlines {
      self.render(inline)
    }
  }

    @MainActor private mutating func render(_ inline: InlineNode) {
    switch inline {
    case .text(let content):
      self.renderText(content)
    case .softBreak:
      self.renderSoftBreak()
    case .html(let content):
      self.renderHTML(content)
    case .image(let source, _):
      self.renderImage(source)
    default:
      self.defaultRender(inline)
    }
  }

    @MainActor private mutating func renderText(_ text: String) {
    var text = text

    if self.shouldSkipNextWhitespace {
      self.shouldSkipNextWhitespace = false
      text = text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
    }

    let laTeXMatches = findLaTeXRanges(in: text).reversed()
    var index = 0
    for match in laTeXMatches {
        let range = match.range
        let nsRange1 = NSRange(location: index, length: range.location - index)
        let txt = (text as NSString).substring(with: nsRange1)
        index = range.upperBound
        self.defaultRender(.text(txt))

        let nsRange = NSRange(location: range.location, length: range.length)
        let laTeXExpression = (text as NSString).substring(with: nsRange)
      
                // Extract the LaTeX code without delimiters
        let laTeXCode = laTeXExpression
                    .replacingOccurrences(of: "\\(", with: "")
                    .replacingOccurrences(of: "\\)", with: "")
                    .replacingOccurrences(of: "$$", with: "")
      
        if let image = renderLaTeX(laTeXCode) {
            self.result = self.result + Text(Image(nsImage: image))
        }
    }
    let nsRange1 = NSRange(location: index, length: text.count - index)
    let txt = (text as NSString).substring(with: nsRange1)
    self.defaultRender(.text(txt))
  }

  private mutating func renderSoftBreak() {
    switch self.softBreakMode {
    case .space where self.shouldSkipNextWhitespace:
      self.shouldSkipNextWhitespace = false
    case .space:
      self.defaultRender(.softBreak)
    case .lineBreak:
      self.shouldSkipNextWhitespace = true
      self.defaultRender(.lineBreak)
    }
  }

  private mutating func renderHTML(_ html: String) {
    let tag = HTMLTag(html)

    switch tag?.name.lowercased() {
    case "br":
      self.defaultRender(.lineBreak)
      self.shouldSkipNextWhitespace = true
    default:
      self.defaultRender(.html(html))
    }
  }

  private mutating func renderImage(_ source: String) {
    if let image = self.images[source] {
      self.result = self.result + Text(image)
    }
  }

  private mutating func defaultRender(_ inline: InlineNode) {
    self.result =
      self.result
      + Text(
        inline.renderAttributedString(
          baseURL: self.baseURL,
          textStyles: self.textStyles,
          softBreakMode: self.softBreakMode,
          attributes: self.attributes
        )
      )
  }
}

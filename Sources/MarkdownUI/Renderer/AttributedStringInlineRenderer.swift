import Foundation

extension InlineNode {
  func renderAttributedString(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer
  ) -> AttributedString {
    var renderer = AttributedStringInlineRenderer(
      baseURL: baseURL,
      textStyles: textStyles,
      softBreakMode: softBreakMode,
      attributes: attributes
    )
    renderer.render(self)
    return renderer.result.resolvingFonts()
  }
}

private struct AttributedStringInlineRenderer {
  var result = AttributedString()

  private let baseURL: URL?
  private let textStyles: InlineTextStyles
  private let softBreakMode: SoftBreak.Mode
  private var attributes: AttributeContainer
  private var shouldSkipNextWhitespace = false

  init(
    baseURL: URL?,
    textStyles: InlineTextStyles,
    softBreakMode: SoftBreak.Mode,
    attributes: AttributeContainer
  ) {
    self.baseURL = baseURL
    self.textStyles = textStyles
    self.softBreakMode = softBreakMode
    self.attributes = attributes
  }

  mutating func render(_ inline: InlineNode) {
    switch inline {
    case .text(let content):
      self.renderText(content)
    case .softBreak:
      self.renderSoftBreak()
    case .lineBreak:
      self.renderLineBreak()
    case .code(let content):
      self.renderCode(content)
    case .html(let content):
      self.renderHTML(content)
    case .emphasis(let children):
      self.renderEmphasis(children: children)
    case .strong(let children):
      self.renderStrong(children: children)
    case .strikethrough(let children):
      self.renderStrikethrough(children: children)
    case .link(let destination, let children):
      self.renderLink(destination: destination, children: children)
    case .image(let source, let children):
      self.renderImage(source: source, children: children)
    }
  }

  private mutating func renderText(_ text: String) {
    var text = text

    if self.shouldSkipNextWhitespace {
      self.shouldSkipNextWhitespace = false
      text = text.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
    }
    self.result += .init(text, attributes: self.attributes)
  }

  private mutating func renderSoftBreak() {
    switch softBreakMode {
    case .space where self.shouldSkipNextWhitespace:
      self.shouldSkipNextWhitespace = false
    case .space:
      self.result += .init(" ", attributes: self.attributes)
    case .lineBreak:
      self.renderLineBreak()
    }
  }

  private mutating func renderLineBreak() {
    self.result += .init("\n", attributes: self.attributes)
  }

  private mutating func renderCode(_ code: String) {
    self.result += .init(code, attributes: self.textStyles.code.mergingAttributes(self.attributes))
  }

  private mutating func renderHTML(_ html: String) {
    let tag = HTMLTag(html)

    switch tag?.name.lowercased() {
    case "br":
      self.renderLineBreak()
      self.shouldSkipNextWhitespace = true
    default:
      self.renderText(html)
    }
  }

  private mutating func renderEmphasis(children: [InlineNode]) {
    let savedAttributes = self.attributes
    self.attributes = self.textStyles.emphasis.mergingAttributes(self.attributes)

    for child in children {
      self.render(child)
    }

    self.attributes = savedAttributes
  }

  private mutating func renderStrong(children: [InlineNode]) {
    let savedAttributes = self.attributes
    self.attributes = self.textStyles.strong.mergingAttributes(self.attributes)

    for child in children {
      self.render(child)
    }

    self.attributes = savedAttributes
  }

  private mutating func renderStrikethrough(children: [InlineNode]) {
    let savedAttributes = self.attributes
    self.attributes = self.textStyles.strikethrough.mergingAttributes(self.attributes)

    for child in children {
      self.render(child)
    }

    self.attributes = savedAttributes
  }

  private mutating func renderLink(destination: String, children: [InlineNode]) {
    let savedAttributes = self.attributes
    self.attributes = self.textStyles.link.mergingAttributes(self.attributes)
    self.attributes.link = URL(string: destination, relativeTo: self.baseURL)

    for child in children {
      self.render(child)
    }

    self.attributes = savedAttributes
  }

  private mutating func renderImage(source: String, children: [InlineNode]) {
    // AttributedString does not support images
  }
}

extension TextStyle {
  fileprivate func mergingAttributes(_ attributes: AttributeContainer) -> AttributeContainer {
    var newAttributes = attributes
    self._collectAttributes(in: &newAttributes)
    return newAttributes
  }
}




let inlineMathPattern = #"\\\((.+?)\\\)"#
let displayMathPattern = #"\$\$(.+?)\$\$"#

func findLaTeXRanges(in text: String) -> [NSTextCheckingResult] {
    let patterns = [inlineMathPattern, displayMathPattern]
    var matches = [NSTextCheckingResult]()
    for pattern in patterns {
        let regex = try! NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let results = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        matches.append(contentsOf: results)
    }
    return matches
}

import MathJaxSwift
import SVGView
import SwiftUI

@MainActor func renderLaTeX(_ laTeX: String) -> NSImage? {
    do {
        let mathjax = try MathJax()
        let svg = try mathjax.tex2svg(laTeX)
        let svgd = try SVG(svgString: svg)
        let view = SVGView(string: svg)
        let width = svgd.geometry.width.toPoints(10)
        let height = svgd.geometry.height.toPoints(10)

        let renderer = ImageRenderer(content: view.frame(width: width, height: height))

        renderer.scale = NSScreen.main?.backingScaleFactor ?? 1

        return renderer.nsImage
    }
    catch {
        print("MathJax error: \(error)")
    }
    return nil
}


struct SVG: Codable, Hashable {

    /// An error produced when creating an SVG.
    enum SVGError: Error {
        case encodingSVGData
    }

    /// The SVG's data.
    let data: Data

    /// The SVG's geometry.
    let geometry: SVGGeometry

    /// Any error text produced when creating the SVG.
    let errorText: String?

    // MARK: Initializers

    /// Initializes a new SVG from data.
    ///
    /// - Parameter data: The SVG data.
    init(data: Data) throws {
        self = try JSONDecoder().decode(Self.self, from: data)
    }

    /// Initializes a new SVG.
    ///
    /// - Parameters:
    ///   - svgString: The SVG's input string.
    ///   - errorText: The error text that was generated when creating the SVG.
    init(svgString: String, errorText: String? = nil) throws {
        self.errorText = errorText

        // Get the SVG's geometry
        geometry = try SVGGeometry(svg: svgString)

        // Get the SVG data
        if let svgData = svgString.data(using: .utf8) {
            data = svgData
        }
        else {
            throw SVGError.encodingSVGData
        }
    }

}

// MARK: Methods

extension SVG {

    /// The JSON encoded value of the receiver.
    ///
    /// - Returns: The receivers JSON encoded data.
    func encoded() throws -> Data {
        try JSONEncoder().encode(self)
    }

}


struct SVGGeometry: Codable, Hashable {

    // MARK: Types

    /// A unit of height that defines the height of the `x` character
    /// of a font.
    typealias XHeight = CGFloat

    /// A parsing error.
    enum ParsingError: Error {
        case missingSVGElement
        case missingGeometry
    }

    // MARK: Static properties

    /// The SVG element regex.
    private static let svgRegex = #/<svg.*?>/#

    /// The attribute regex.
    private static let attributeRegex = #/\w*:*\w+=".*?"/#

    // MARK: Public properties

    /// The SVG's vertical alignment (offset).
    let verticalAlignment: XHeight

    /// The SVG's width.
    let width: XHeight

    /// The SVG's height.
    let height: XHeight

    /// The SVG's frame.
    let frame: CGRect

    // MARK: Initializers

    /// Initializes a geometry from an SVG.
    ///
    /// - Parameter svg: The SVG.
    init(svg: String) throws {
        // Find the SVG element
        guard let match = svg.firstMatch(of: SVGGeometry.svgRegex) else {
            throw ParsingError.missingSVGElement
        }

        // Get the SVG element
        let svgElement = String(svg[svg.index(after: match.range.lowerBound) ..< svg.index(before: match.range.upperBound)])

        // Get its attributes
        var verticalAlignment: XHeight?
        var width: XHeight?
        var height: XHeight?
        var frame: CGRect?

        for match in svgElement.matches(of: SVGGeometry.attributeRegex) {
            let attribute = String(svgElement[match.range])
            let components = attribute.components(separatedBy: CharacterSet(charactersIn: "="))
            guard components.count == 2 else {
                continue
            }
            switch components[0] {
                case "style": verticalAlignment = SVGGeometry.parseAlignment(from: components[1])
                case "width": width = SVGGeometry.parseXHeight(from: components[1])
                case "height": height = SVGGeometry.parseXHeight(from: components[1])
                case "viewBox": frame = SVGGeometry.parseViewBox(from: components[1])
                default: continue
            }
        }

        guard let verticalAlignment = verticalAlignment,
              let width = width,
              let height = height,
              let frame = frame else {
            throw ParsingError.missingGeometry
        }

        self.verticalAlignment = verticalAlignment
        self.width = width
        self.height = height
        self.frame = frame
    }

}

// MARK: Static methods

extension SVGGeometry {

    /// Parses the alignment from the style attribute.
    ///
    /// "vertical-align: -1.602ex;"
    ///
    /// - Parameter string: The input string.
    /// - Returns: The alignment's x-height.
    static func parseAlignment(from string: String) -> XHeight? {
        let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "\";"))
        let components = trimmed.components(separatedBy: CharacterSet(charactersIn: ":"))
        guard components.count == 2 else { return nil }
        let value = components[1].trimmingCharacters(in: .whitespaces)
        return XHeight(stringValue: value)
    }

    /// Parses the x-height value from an attribute.
    ///
    /// "2.127ex"
    ///
    /// - Parameter string: The input string.
    /// - Returns: The x-height.
    static func parseXHeight(from string: String) -> XHeight? {
        let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return XHeight(stringValue: trimmed)
    }

    /// Parses the view-box from an attribute.
    ///
    /// "0 -1342 940 2050"
    ///
    /// - Parameter string: The input string.
    /// - Returns: The view-box.
    static func parseViewBox(from string: String) -> CGRect? {
        let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        let components = trimmed.components(separatedBy: CharacterSet.whitespaces)
        guard components.count == 4 else { return nil }
        guard let x = Double(components[0]),
              let y = Double(components[1]),
              let width = Double(components[2]),
              let height = Double(components[3]) else {
            return nil
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

}

internal typealias _Font = NSFont

extension SVGGeometry.XHeight {

    /// Initializes a x-height value.
    ///
    /// "2.127ex"
    ///
    /// - Parameter stringValue: The x-height.
    init?(stringValue: String) {
        let trimmed = stringValue.trimmingCharacters(in: CharacterSet(charactersIn: "ex"))
        if let value = Double(trimmed) {
            self = CGFloat(value)
        }
        else {
            return nil
        }
    }

    /// Converts the x-height to points.
    ///
    /// - Parameter xHeight: The height of 1 x-height unit.
    /// - Returns: The points.
    func toPoints(_ xHeight: CGFloat) -> CGFloat {
        xHeight * self
    }

    /// Converts the x-height to points.
    ///
    /// - Parameter font: The font.
    /// - Returns: The points.
    func toPoints(_ font: _Font) -> CGFloat {
        toPoints(font.xHeight)
    }

    //    /// Converts the x-height to points.
    //    ///
    //    /// - Parameter font: The font.
    //    /// - Returns: The points.
    //    func toPoints(_ font: Font) -> CGFloat {
    //#if os(iOS)
    //        toPoints(_Font.preferredFont(from: font))
    //#else
    //        toPoints(_Font.preferredFont( from: font))
    //#endif
    //    }

}



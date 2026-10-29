import CoreImage
import UIKit

enum OverlayKind: Hashable {
    case titleCard(title: String, subtitle: String)
    case chapter(String)
    case caption(String)
    case timestamp(String)
}

/// 文字ラベルを出力サイズの透過画像として描画し、キャッシュする
final class OverlayImageCache {
    private let size: CGSize
    private var cache: [OverlayKind: CIImage] = [:]

    init(size: CGSize) {
        self.size = size
    }

    func image(for kind: OverlayKind) -> CIImage {
        if let cached = cache[kind] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(kind, in: context.cgContext)
        }
        let ciImage = image.cgImage.map { CIImage(cgImage: $0) } ?? CIImage.empty()
        cache[kind] = ciImage
        return ciImage
    }

    private func draw(_ kind: OverlayKind, in context: CGContext) {
        let w = size.width, h = size.height
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.6)
        shadow.shadowBlurRadius = h * 0.006
        shadow.shadowOffset = CGSize(width: 0, height: h * 0.002)

        switch kind {
        case let .titleCard(title, subtitle):
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let titleText = attributed(title, size: h * 0.075, weight: .bold, color: .white, align: .center)
            let subtitleText = attributed(subtitle, size: h * 0.035, weight: .regular,
                                          color: UIColor.white.withAlphaComponent(0.75), align: .center)
            let maxWidth = w * 0.85
            let titleSize = measure(titleText, maxWidth: maxWidth)
            let subtitleSize = subtitle.isEmpty ? .zero : measure(subtitleText, maxWidth: maxWidth)
            let gap = subtitle.isEmpty ? 0 : h * 0.03
            var y = (h - titleSize.height - gap - subtitleSize.height) / 2
            titleText.draw(with: CGRect(x: (w - maxWidth) / 2, y: y, width: maxWidth, height: titleSize.height),
                           options: .usesLineFragmentOrigin, context: nil)
            y += titleSize.height + gap
            subtitleText.draw(with: CGRect(x: (w - maxWidth) / 2, y: y, width: maxWidth, height: subtitleSize.height),
                              options: .usesLineFragmentOrigin, context: nil)

        case let .chapter(text):
            // 左上にシーン名。左端にアクセントの縦線
            let label = attributed(text, size: h * 0.05, weight: .semibold, color: .white, align: .left, shadow: shadow)
            let textSize = measure(label, maxWidth: w * 0.6)
            let origin = CGPoint(x: w * 0.05, y: h * 0.07)
            UIColor.white.withAlphaComponent(0.9).setFill()
            context.fill(CGRect(x: origin.x, y: origin.y + textSize.height * 0.1,
                                width: h * 0.006, height: textSize.height * 0.8))
            label.draw(with: CGRect(x: origin.x + h * 0.022, y: origin.y, width: w * 0.6, height: textSize.height),
                       options: .usesLineFragmentOrigin, context: nil)

        case let .timestamp(text):
            // 右上に小さく。左上のシーン名・下のキャプションと重ならない位置
            let label = attributed(text, size: h * 0.032, weight: .medium,
                                   color: UIColor.white.withAlphaComponent(0.92), align: .right, shadow: shadow)
            let textSize = measure(label, maxWidth: w * 0.5)
            label.draw(with: CGRect(x: w * 0.95 - w * 0.5, y: h * 0.075, width: w * 0.5, height: textSize.height),
                       options: .usesLineFragmentOrigin, context: nil)

        case let .caption(text):
            let label = attributed(text, size: h * 0.042, weight: .medium, color: .white, align: .center, shadow: shadow)
            let maxWidth = w * 0.8
            let textSize = measure(label, maxWidth: maxWidth)
            let padding = h * 0.015
            let box = CGRect(x: (w - textSize.width) / 2 - padding * 1.5, y: h * 0.92 - textSize.height - padding,
                             width: textSize.width + padding * 3, height: textSize.height + padding * 2)
            UIColor.black.withAlphaComponent(0.35).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: padding).fill()
            label.draw(with: CGRect(x: (w - maxWidth) / 2, y: box.minY + padding, width: maxWidth,
                                    height: textSize.height),
                       options: .usesLineFragmentOrigin, context: nil)
        }
    }

    private func attributed(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor,
                            align: NSTextAlignment, shadow: NSShadow? = nil) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = align
        var attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        if let shadow { attributes[.shadow] = shadow }
        return NSAttributedString(string: text, attributes: attributes)
    }

    private func measure(_ text: NSAttributedString, maxWidth: CGFloat) -> CGSize {
        let rect = text.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                     options: .usesLineFragmentOrigin, context: nil)
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }
}

import Foundation

/// Recipe/step `image_url`s may carry the admin crop tool's `#pos=<x%>,<y%>,<zoom>` fragment.
struct ImagePosition: Equatable {
    var x: Double
    var y: Double
    var zoom: Double

    private static let re = try! NSRegularExpression(pattern: "#pos=(-?[0-9.]+),(-?[0-9.]+),([0-9.]+)")

    init(x: Double, y: Double, zoom: Double) {
        self.x = x; self.y = y; self.zoom = zoom
    }

    init?(urlString: String) {
        let ns = urlString as NSString
        guard let m = Self.re.firstMatch(in: urlString, range: NSRange(location: 0, length: ns.length)),
              let x = Double(ns.substring(with: m.range(at: 1))),
              let y = Double(ns.substring(with: m.range(at: 2))),
              let zoom = Double(ns.substring(with: m.range(at: 3))) else { return nil }
        self.init(x: x, y: y, zoom: zoom)
    }
}

enum ImageURL {
    /// `url.split('#')[0]`
    static func base(_ urlString: String) -> String {
        urlString.components(separatedBy: "#").first ?? urlString
    }

    /// The uploads are multi-megabyte PNGs; ask Cloudinary for a resized JPEG instead.
    static func optimized(_ urlString: String, width: Int = 1000) -> URL? {
        let base = base(urlString)
        let marker = "/image/upload/"
        guard base.contains("res.cloudinary.com"), let range = base.range(of: marker) else {
            return URL(string: base)
        }
        let rest = base[range.upperBound...]
        // Leave URLs that already carry a transformation untouched.
        if let first = rest.split(separator: "/").first, first.contains(","), first.contains("_") {
            return URL(string: base)
        }
        return URL(string: base.replacingCharacters(in: range, with: "\(marker)f_jpg,q_auto,c_limit,w_\(width)/"))
    }
}

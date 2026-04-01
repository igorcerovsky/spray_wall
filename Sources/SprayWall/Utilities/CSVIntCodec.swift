import Foundation

enum CSVIntCodec {
    static func decode(_ input: String) -> [Int] {
        input
            .split(separator: ",")
            .compactMap { token in
                Int(token.trimmingCharacters(in: .whitespacesAndNewlines))
            }
    }

    static func encode(_ values: [Int]) -> String {
        values.map(String.init).joined(separator: ",")
    }
}

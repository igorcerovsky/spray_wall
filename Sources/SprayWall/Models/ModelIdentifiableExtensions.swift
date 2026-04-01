import Foundation

extension Hold: Identifiable {
    var id: Int { holdID }
}

extension Route: Identifiable {
    var id: Int { routeID }
}

extension Attempt: Identifiable {
    var id: Int { attemptID }
}

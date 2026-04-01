import Testing
@testable import SprayWall

@Test("CSVIntCodec decodes and trims values")
func csvDecode() {
    let values = CSVIntCodec.decode(" 12, 44,78, invalid, 91 ")
    #expect(values == [12, 44, 78, 91])
}

@Test("CSVIntCodec encodes values")
func csvEncode() {
    let csv = CSVIntCodec.encode([12, 44, 78, 91])
    #expect(csv == "12,44,78,91")
}

@Test("Password hash is deterministic")
func hashIsStable() {
    let one = AuthService.hash("secret-123")
    let two = AuthService.hash("secret-123")
    #expect(one == two)
}

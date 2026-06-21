import Testing
@testable import RNapiCore

@Test func packageVersionIsSet() {
    #expect(!RNapiCore.version.isEmpty)
}

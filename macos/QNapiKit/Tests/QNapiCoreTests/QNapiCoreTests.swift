import Testing
@testable import QNapiCore

@Test func packageVersionIsSet() {
    #expect(!QNapiCore.version.isEmpty)
}

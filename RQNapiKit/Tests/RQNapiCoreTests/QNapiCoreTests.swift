import Testing
@testable import RQNapiCore

@Test func packageVersionIsSet() {
    #expect(!RQNapiCore.version.isEmpty)
}

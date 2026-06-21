import Foundation
import Testing

@testable import RNapiCore

@Suite struct TextEncodingDetectorTests {
    private let polishSample = "Zażółć gęślą jaźń — typowy polski tekst napisów."

    @Test func detectsUTF8() {
        let data = Data(polishSample.utf8)
        #expect(TextEncodingDetector.detectEncoding(of: data) == .utf8)
    }

    @Test func detectsWindows1250() throws {
        let data = try #require(polishSample.data(using: .windowsCP1250))
        let encoding = TextEncodingDetector.detectEncoding(of: data)
        let roundTrip = try #require(String(data: data, encoding: encoding))
        #expect(roundTrip.contains("Zażółć"))
    }

    @Test func detectsISOLatin2() throws {
        // No em-dash here: ISO-8859-2 cannot encode it.
        let data = try #require("Zażółć gęślą jaźń".data(using: .isoLatin2))
        let encoding = TextEncodingDetector.detectEncoding(of: data)
        let roundTrip = try #require(String(data: data, encoding: encoding))
        #expect(roundTrip.contains("gęślą"))
    }

    @Test func decodeRecoversPolishText() throws {
        let data = try #require(polishSample.data(using: .windowsCP1250))
        let decoded = try #require(TextEncodingDetector.decode(data))
        #expect(decoded == polishSample)
    }

    @Test func replacesDiacritics() {
        #expect(
            TextEncodingDetector.replaceDiacriticsWithASCII("Zażółć gęślą jaźń")
                == "Zazolc gesla jazn")
        #expect(TextEncodingDetector.replaceDiacriticsWithASCII("Æneid œuvre") == "AEneid oeuvre")
        #expect(TextEncodingDetector.replaceDiacriticsWithASCII("plain ASCII") == "plain ASCII")
    }
}

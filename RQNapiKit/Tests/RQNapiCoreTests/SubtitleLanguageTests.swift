import Testing

@testable import RQNapiCore

@Suite struct SubtitleLanguageTests {
    @Test func resolvesFromTwoLetterCode() {
        let lang = SubtitleLanguage("pl")
        #expect(lang?.threeLetter == "pol")
        #expect(lang?.englishName == "Polish")
    }

    @Test func resolvesFromThreeLetterCode() {
        #expect(SubtitleLanguage("eng")?.twoLetter == "en")
    }

    @Test func resolvesFromFullName() {
        #expect(SubtitleLanguage("Portuguese-BR")?.threeLetter == "pob")
    }

    @Test func isCaseInsensitiveForCodes() {
        #expect(SubtitleLanguage("PL")?.twoLetter == "pl")
        #expect(SubtitleLanguage("ENG")?.twoLetter == "en")
    }

    @Test func unknownLanguageReturnsNil() {
        #expect(SubtitleLanguage("xx") == nil)
        #expect(SubtitleLanguage("Klingon") == nil)
    }

    @Test func tableHasUniqueCodes() {
        let twoLetter = Set(SubtitleLanguage.all.map(\.twoLetter))
        let threeLetter = Set(SubtitleLanguage.all.map(\.threeLetter))
        #expect(twoLetter.count == SubtitleLanguage.all.count)
        #expect(threeLetter.count == SubtitleLanguage.all.count)
    }
}

import Testing
@testable import DOSBoxerKit

struct CoverArtTests {
    @Test func looseNamesIgnorePunctuationAndCase() {
        #expect(CoverArtFetcher.loose("Duke Nukem - Episode 1 - Shrapnel City (1991)")
            == CoverArtFetcher.loose("duke nukem episode 1: shrapnel city (1991)"))
    }

    @Test func triesWithoutTheYearAndWithTheMoved() {
        let keys = CoverArtFetcher.lookupKeys(for: "Punisher, The - Eternity Disk (1990)")
        #expect(keys.first == CoverArtFetcher.loose("Punisher, The - Eternity Disk (1990)"))
        #expect(keys.contains(CoverArtFetcher.loose("Punisher, The - Eternity Disk")))
        #expect(keys.contains(CoverArtFetcher.loose("The Punisher - Eternity Disk (1990)")))
        #expect(CoverArtFetcher.lookupKeys(for: "Nations and Capitals (198x)")
            .contains(CoverArtFetcher.loose("Nations and Capitals")))
    }

    @Test func ignoresEditionTags() {
        let keys = CoverArtFetcher.lookupKeys(for: "Leisure Suit Larry 1 - In The Land of the Lounge Lizards SCI (1991)")
        #expect(keys.contains(CoverArtFetcher.loose("Leisure Suit Larry 1 - In the Land of the Lounge Lizards (1991)")))
        #expect(CoverArtFetcher.lookupKeys(for: "Ultima VII - The Black Gate CD (1992)")
            .contains(CoverArtFetcher.loose("Ultima VII - The Black Gate (1992)")))
        // A plain name keeps no edition tags to strip
        #expect(!CoverArtFetcher.lookupKeys(for: "Doom (1993)").contains(""))
    }

    /// "Legend of Kyrandia Book 1" finds "The Legend of Kyrandia: Book One".
    @Test func triesTheAndNumbersAsWords() {
        let keys = CoverArtFetcher.lookupKeys(for: "Legend of Kyrandia Book 1 (1992)")
        #expect(keys.contains(CoverArtFetcher.loose("The Legend of Kyrandia: Book One")))
        #expect(CoverArtFetcher.lookupKeys(for: "Ultima 4 (1985)").contains(CoverArtFetcher.loose("Ultima IV")))
    }

    @Test func fileNamesUseLibretroSubstitutions() {
        #expect(CoverArtFetcher.libretroFileName("Star Trek: 25th Anniversary") == "Star Trek_ 25th Anniversary")
    }
}

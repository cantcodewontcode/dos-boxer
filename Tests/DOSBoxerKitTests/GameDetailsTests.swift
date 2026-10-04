import Testing
@testable import DOSBoxerKit

struct GameDetailsTests {
    let crystalCaves: [(id: String, description: String)] = [
        ("Q108370748", "video game series"),
        ("Q1142344", "1991 video game"),
        ("Q125253477", "caves in Cayman Islands"),
        ("Q131511458", "2020 video game"),
    ]

    @Test func picksTheVideoGameFromTheRightYear() {
        #expect(GameDetailsFetcher.bestMatch(crystalCaves, year: 1991) == "Q1142344")
        #expect(GameDetailsFetcher.bestMatch(crystalCaves, year: 2020) == "Q131511458")
    }

    @Test func acceptsGamesNotCalledVideoGames() {
        let warcraft: [(id: String, description: String)] = [
            ("Q741716", "fantasy-themed real-time strategy game published by Blizzard Entertainment"),
            ("Q122890940", "1996 video game demo"),
        ]
        #expect(GameDetailsFetcher.bestMatch(warcraft, year: 1995) == "Q741716")
    }

    @Test func doesNotGuessWhenTheYearsDisagree() {
        #expect(GameDetailsFetcher.bestMatch(crystalCaves, year: 1985) == nil)
    }

    @Test func searchesWithoutEditionTags() {
        #expect(GameDetailsFetcher.searchTitle("Leisure Suit Larry 1 - In The Land of the Lounge Lizards SCI")
            == "Leisure Suit Larry 1 - In The Land of the Lounge Lizards")
    }
}

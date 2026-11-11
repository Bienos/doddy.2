import XCTest
@testable import DoddyCore

/// Tapping a follow on On my radar shows its stories, whatever label the server gave it (owner, 11 Nov 2026: "chcę
/// wybrać, to też nie działa").
final class NewsFeedLabelsTests: XCTestCase {
    private func card(_ title: String, _ follows: [String]) -> NewsCard {
        NewsCard(id: title, title: title, summary: "", url: "https://example.com/\(title)", source: "PAP", publishedAt: "2026-11-11T08:00:00Z", follows: follows)
    }

    func testTheDefaultFollowFindsTheStoriesTheServerNamedPolska() {
        let poland = NewsFollow.topic(id: "poland", label: "Co się dzieje w Polsce")
        let cpk = NewsFollow.words(label: "CPK", keywords: ["CPK"])
        let reports = [NewsFollowReport(label: "Polska", sources: [], cards: 2), NewsFollowReport(label: "CPK", sources: [], cards: 1)]
        let labels = NewsFeedLabels.byFollow(requested: [poland, cpk], reports: reports)
        XCTAssertEqual(labels, [poland.id: "Polska", cpk.id: "CPK"])
        let cards = [card("a", ["Polska"]), card("b", ["Polska", "CPK"]), card("c", ["Sport"])]
        XCTAssertEqual(NewsFeedLabels.cards(of: poland, in: cards, labels: labels).map(\.title), ["a", "b"])
        XCTAssertEqual(NewsFeedLabels.cards(of: cpk, in: cards, labels: labels).map(\.title), ["b"])
        XCTAssertEqual(NewsFeedLabels.cards(of: poland, in: cards, labels: [:]).map(\.title), [], "the old match by the follow's own label found nothing")
    }

    func testAnAnswerForAnotherListOnlyMatchesLabelsAsTheyAre() {
        let poland = NewsFollow.topic(id: "poland", label: "Co się dzieje w Polsce")
        let cpk = NewsFollow.words(label: "CPK", keywords: ["CPK"])
        let added = NewsFollow.words(label: "Orlen", keywords: ["Orlen"])
        let reports = [NewsFollowReport(label: "Polska", sources: [], cards: 2), NewsFollowReport(label: "CPK", sources: [], cards: 1)]
        let labels = NewsFeedLabels.byFollow(requested: [poland, cpk, added], reports: reports)
        XCTAssertEqual(labels, [cpk.id: "CPK"], "never a guess when the lists differ")
    }
}

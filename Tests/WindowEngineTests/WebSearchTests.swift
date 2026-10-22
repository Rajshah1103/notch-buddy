import Foundation
import Testing
@testable import WindowEngine

struct WebSearchTests {
    private func classify(_ text: String) -> WebAction? { WebAction.classify(text, engine: .google) }

    @Test(arguments: [
        ("github.com", "https://github.com"),
        ("github.com/acme/api/pull/1", "https://github.com/acme/api/pull/1"),
        ("www.apple.com", "https://www.apple.com"),
        ("https://example.org/a?b=1", "https://example.org/a?b=1"),
        ("localhost:3000", "http://localhost:3000"),
        ("192.168.1.10:8080/admin", "http://192.168.1.10:8080/admin"),
        ("jenkins.acme.dev/job/x", "https://jenkins.acme.dev/job/x"),
    ])
    func typedAddressesOpenDirectly(text: String, expected: String) {
        let action = classify(text)
        #expect(action?.kind == .address)
        #expect(action?.url.absoluteString == expected)
    }

    @Test(arguments: ["main.swift", "main.rs", "script.py", "README.md", "how to center a div", "swift concurrency", "c++ templates", "a.b", "ftp://x.com"])
    func everythingElseIsASearch(text: String) {
        #expect(classify(text)?.kind == .search)
    }

    @Test func blankTextDoesNothing() {
        #expect(classify("   ") == nil)
    }

    @Test func searchesAreEncodedForTheChosenEngine() {
        #expect(WebAction.classify("a&b=c d", engine: .duckDuckGo)?.url.absoluteString == "https://duckduckgo.com/?q=a%26b%3Dc%20d")
        #expect(classify("swift concurrency")?.title == "Search Google for “swift concurrency”")
    }

    @Test func profilesComeInTheBrowsersOrderWithFallbacks() {
        let data = Data(#"""
        {"profile":{"info_cache":{"Default":{"name":"Personal","user_name":"me@x.com"},"Profile 2":{"name":"Work","user_name":""},
        "Profile 10":{"name":"Side"},"Profile 1":{"name":"","user_name":"a@b.c"}},
        "profiles_order":["Profile 2","Default"],"last_used":"Profile 2"}}
        """#.utf8)
        let list = BrowserProfiles.parse(data)
        #expect(list.profiles.map(\.directory) == ["Profile 2", "Default", "Profile 1", "Profile 10"])
        #expect(list.lastUsed == "Profile 2")
        #expect(list.profiles[0].email == nil)
        #expect(list.profiles[2].name == "Profile 1")
        #expect(BrowserProfiles.parse(Data("nope".utf8)) == .empty)
    }
}

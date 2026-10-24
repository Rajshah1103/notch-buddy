import Foundation
import Testing
@testable import GmailKit

struct ResponseParserTests {
    @Test func readsTheUnreadCount() {
        #expect(ResponseParser.unreadCount(fromLabel: Data(#"{"id":"INBOX","messagesUnread":42}"#.utf8)) == 42)
        #expect(ResponseParser.unreadCount(fromLabel: Data("{}".utf8)) == nil)
    }

    @Test func readsMessageIDsInOrder() {
        #expect(ResponseParser.ids(fromList: Data(#"{"messages":[{"id":"b"},{"id":"a"}]}"#.utf8)) == ["b", "a"])
        #expect(ResponseParser.ids(fromList: Data(#"{"resultSizeEstimate":0}"#.utf8)) == [])
    }

    @Test func readsAMessageFromItsHeaders() {
        let json = #"{"id":"m1","internalDate":"1800000000000","payload":{"headers":[{"name":"from","value":"\"Ada Lovelace\" <ada@example.com>"},{"name":"Subject","value":"Lunch?"}]}}"#
        let message = ResponseParser.message(from: Data(json.utf8))
        #expect(message?.from == "Ada Lovelace")
        #expect(message?.subject == "Lunch?")
        #expect(message?.date == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func fillsInAMissingSubjectAndKeepsABareAddress() {
        let json = #"{"id":"m2","payload":{"headers":[{"name":"From","value":"bot@example.com"}]}}"#
        let message = ResponseParser.message(from: Data(json.utf8))
        #expect(message?.subject == "(no subject)")
        #expect(message?.from == "bot@example.com")
        #expect(ResponseParser.sender("<bare@example.com>") == "bare@example.com")
    }
}

struct AuthTests {
    @Test func pkceChallengeIsTheUnpaddedSha256OfTheVerifier() {
        // The worked example from RFC 7636, appendix B.
        #expect(GmailAuth.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(GmailAuth.makeVerifier().count >= 43)
    }

    @Test func authorizationURLCarriesTheRequiredParts() {
        let url = GmailAuth.authorizationURL(clientID: "id", redirect: "http://127.0.0.1:1", challenge: "c", state: "s")
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["scope"] == GmailAuth.scope)
        #expect(items["access_type"] == "offline")
        #expect(items["redirect_uri"] == "http://127.0.0.1:1")
    }

    @Test func readsTheRedirectRequest() {
        let params = LoopbackReceiver.parameters(inRequest: "GET /?code=abc%2F1&state=xyz HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        #expect(params["code"] == "abc/1")
        #expect(params["state"] == "xyz")
        #expect(LoopbackReceiver.parameters(inRequest: "GET /favicon.ico HTTP/1.1\r\n\r\n").isEmpty)
    }
}

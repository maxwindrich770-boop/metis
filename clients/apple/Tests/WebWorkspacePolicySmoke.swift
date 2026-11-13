import Foundation

private struct WebPolicyFailure: Error, CustomStringConvertible {
    let description: String
}

/// Build with MetisWebWorkspace.swift alone; UIKit/WebKit are not required.
@main
struct WebWorkspacePolicySmoke {
    static func main() {
        do {
            try verifyOrigins()
            try verifyFrames()
            try verifyDownloadNames()
            try verifyModelPreferences()
            try verifyOnboardingCompletion()
            print("Web workspace policy smoke passed")
        } catch {
            FileHandle.standardError.write(Data("Web workspace policy smoke failed: \(error)\n".utf8))
            exit(EXIT_FAILURE)
        }
    }

    private static func check(_ condition: Bool, _ description: String) throws {
        guard condition else { throw WebPolicyFailure(description: description) }
    }

    private static func url(_ value: String) -> URL { URL(string: value)! }

    private static func verifyOnboardingCompletion() throws {
        let suite = "metis-onboarding-smoke-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let alice = "metis:onboarding:v1:fixture-alice:browser"
        let bob = "metis:onboarding:v1:fixture-bob:browser"
        let origin = "https://metis.example"
        let done = MetisWebOnboardingPolicy.completedValue
        try check(MetisWebOnboardingPolicy.completedKeys(origin: origin, defaults: defaults).isEmpty,
                  "A fresh installation must not skip the guide")
        try check(MetisWebOnboardingPolicy.recordCompletion(key: alice, value: done, origin: origin, defaults: defaults),
                  "A completed guide was not saved")
        let relaunched = UserDefaults(suiteName: suite)!
        try check(MetisWebOnboardingPolicy.completedKeys(origin: origin, defaults: relaunched) == [alice],
                  "Completion did not survive recreation of the preferences store")
        try check(!MetisWebOnboardingPolicy.completedKeys(origin: origin, defaults: defaults).contains(bob),
                  "One account must not complete another account's guide")
        try check(MetisWebOnboardingPolicy.completedKeys(origin: "https://other.example", defaults: defaults).isEmpty,
                  "Completion escaped its server origin")
        for key in ["metis:onboarding:v1::browser", "auth_token", "x_model", "metis:onboarding:v1:alice:desktop"] {
            try check(!MetisWebOnboardingPolicy.recordCompletion(key: key, value: done, origin: origin, defaults: defaults),
                      "An unrelated storage key was persisted")
        }
        for value in ["{}", "invalid", #"{"version":1,"phase":"welcome","tourIndex":0}"#,
                      #"{"version":2,"phase":"done","tourIndex":0}"#,
                      #"{"version":true,"phase":"done","tourIndex":0}"#,
                      #"{"version":1,"phase":"done","tourIndex":1}"#,
                      String(repeating: " ", count: 1025)] {
            try check(!MetisWebOnboardingPolicy.recordCompletion(key: bob, value: value, origin: origin, defaults: defaults),
                      "An unfinished or invalid guide was marked complete")
        }
        try check(MetisWebOnboardingPolicy.completedKeys(origin: origin, defaults: defaults) == [alice],
                  "Rejected writes changed the saved completion")
    }

    private static func verifyOrigins() throws {
        let server = url("https://metis.example")
        for candidate in [
            "https://metis.example",
            "https://metis.example:443/",
            "https://METIS.EXAMPLE/chats?c=fixture#message",
        ] {
            try check(MetisWebPolicy.isSameOrigin(url(candidate), server: server),
                      "Same origin was rejected: \(candidate)")
        }
        try check(MetisWebPolicy.isSameOrigin(url("https://metis.example/path"),
                                            server: url("https://metis.example:443")),
                  "An explicit default HTTPS port changed the origin")
        try check(MetisWebPolicy.isSameOrigin(url("http://localhost:80/path"), server: url("http://localhost")),
                  "An explicit default HTTP port changed the origin")
        try check(MetisWebPolicy.isSameOrigin(url("https://metis.example:8443/path"),
                                            server: url("https://metis.example:8443")),
                  "Matching explicit nondefault ports were rejected")

        for candidate in [
            "https://metis.example:444/",
            "https://child.metis.example/",
            "https://metis.example.invalid/",
            "http://metis.example/",
            "http://metis.example:443/",
            "https://user@metis.example/",
            "https://user:password@metis.example/",
            "file:///tmp/metis.example",
            "javascript:alert(1)",
            "blob:https://metis.example/fixture",
        ] {
            try check(!MetisWebPolicy.isSameOrigin(url(candidate), server: server),
                      "An origin boundary was accepted: \(candidate)")
        }
        try check(!MetisWebPolicy.isSameOrigin(url("https://metis.example/"),
                                             server: url("https://metis.example:8443")),
                  "A missing nondefault port crossed the origin boundary")

        for candidate in ["blob:https://metis.example/fixture", "blob:https://metis.example:443/fixture"] {
            try check(MetisWebPolicy.isFirstPartyBlob(url(candidate), server: server),
                      "A first-party blob was rejected")
        }
        for candidate in [
            "blob:https://other.example/fixture",
            "blob:https://metis.example:8443/fixture",
            "blob:http://metis.example/fixture",
            "blob:https://user:password@metis.example/fixture",
            "blob:null/fixture",
            "https://metis.example/fixture",
        ] {
            try check(!MetisWebPolicy.isFirstPartyBlob(url(candidate), server: server),
                      "A foreign or opaque blob was accepted: \(candidate)")
        }

        for candidate in ["https://provider.example/oauth", "http://127.0.0.1:43100/fixture-external"] {
            try check(MetisWebPolicy.isExternalLink(url(candidate)), "A normal user link was rejected")
        }
        for candidate in ["javascript:alert(1)", "data:text/plain,fixture", "file:///tmp/fixture",
                          "https://user:password@provider.example/", "/relative"] {
            try check(!MetisWebPolicy.isExternalLink(url(candidate)), "An unsafe external link was accepted")
        }
    }

    private static func verifyFrames() throws {
        let server = url("https://metis.example")
        try check(MetisWebPolicy.permitsSubframe(url("https://metis.example/preview"), server: server,
                                               firstPartySource: false),
                  "A same-origin frame was rejected")
        for candidate in ["data:text/plain,public-fixture", "about:blank", "blob:https://metis.example/fixture"] {
            try check(MetisWebPolicy.permitsSubframe(url(candidate), server: server, firstPartySource: true),
                      "Trusted preview frame was rejected: \(candidate)")
            try check(!MetisWebPolicy.permitsSubframe(url(candidate), server: server, firstPartySource: false),
                      "An untrusted source created a preview frame: \(candidate)")
        }
        for candidate in ["https://other.example/preview", "blob:https://other.example/fixture",
                          "about:srcdoc", "javascript:alert(1)", "file:///tmp/fixture"] {
            try check(!MetisWebPolicy.permitsSubframe(url(candidate), server: server, firstPartySource: true),
                      "A foreign or executable preview frame was accepted: \(candidate)")
        }
    }


    private static func verifyModelPreferences() throws {
        let opaqueModel = "SYNTHETIC/provider:opaque model 🌱"
        let validParameters = #"[{"id":"SYNTHETIC parameter","value":"opaque value"}]"#
        let values = ["tenant-config_model": opaqueModel, "tenant-config_model_params": validParameters]
        try check(MetisWebPreferencePolicy.sanitized(values) == values,
                  "Opaque model IDs, parameters, and configurable storage prefixes must round-trip unchanged")
        try check(MetisWebPreferencePolicy.sanitized([:]) == [:],
                  "Clearing the preference family must remain representable")
        try check(MetisWebPreferencePolicy.sanitized(["custom_model_params": "[]"]) != nil,
                  "An empty parameter selection was rejected")
        for key in ["x_model", "some-other-prefix_model_params", "🌱_model"] {
            try check(MetisWebPreferencePolicy.isSupportedKey(key), "A configured preference prefix was rejected")
        }
        for key in ["", "_model", "_model_params", "model", "prefix_model_params_extra", "prefix_draft", "auth_token"] {
            try check(!MetisWebPreferencePolicy.isSupportedKey(key), "An unrelated local storage key was accepted")
            try check(MetisWebPreferencePolicy.sanitized([key:"SYNTHETIC"]) == nil,
                      "Unrelated local storage escaped the native allowlist")
        }
        for parameters in [
            "not JSON", "{}", #"{"id":"p","value":"v"}"#, "[1]",
            #"[{"id":"p"}]"#, #"[{"value":"v"}]"#,
            #"[{"id":1,"value":"v"}]"#, #"[{"id":"p","value":true}]"#,
            #"[{"id":"p","value":"v","extra":"field"}]"#,
        ] {
            try check(MetisWebPreferencePolicy.sanitized(["custom_model_params":parameters]) == nil,
                      "A malformed parameter envelope was accepted")
        }
        var entries = Dictionary(uniqueKeysWithValues: (0..<MetisWebPreferencePolicy.maximumEntries).map {
            ("prefix-\($0)_model", opaqueModel)
        })
        try check(MetisWebPreferencePolicy.sanitized(entries) != nil, "The documented entry limit was rejected")
        entries["one-more_model"] = opaqueModel
        try check(MetisWebPreferencePolicy.sanitized(entries) == nil, "Too many preference entries were accepted")

        let emptySize = try JSONEncoder().encode(["prefix_model":""]).count
        let boundary = ["prefix_model":String(repeating:"a", count:MetisWebPreferencePolicy.maximumBytes-emptySize)]
        try check(try JSONEncoder().encode(boundary).count == MetisWebPreferencePolicy.maximumBytes,
                  "The byte-limit fixture must exercise the encoded boundary")
        try check(MetisWebPreferencePolicy.sanitized(boundary) != nil, "The encoded byte limit was rejected")
        let oversized = ["prefix_model":boundary["prefix_model"]! + "a"]
        try check(MetisWebPreferencePolicy.sanitized(oversized) == nil, "An oversized preference payload was accepted")
        try check(MetisWebPreferencePolicy.sanitized([
            "unicode_model":String(repeating:"🌱", count:MetisWebPreferencePolicy.maximumBytes / 4),
        ]) == nil, "Preference size must count encoded bytes, including Unicode")
    }

    private static func verifyDownloadNames() throws {
        let names: [(String, String)] = [
            ("report.txt", "report.txt"),
            ("../../report.txt", "report.txt"),
            ("..\\..\\report.txt", "report.txt"),
            ("/private/tmp/report.txt", "report.txt"),
            (" ..report.txt.. \n", "report.txt"),
            ("report\u{0000}\u{000A}.txt", "report.txt"),
            ("\u{202E}report\u{202C}.txt", "report.txt"),
            ("\u{2066}report\u{2069}.txt", "report.txt"),
            (" \t..\n", "Download"),
            ("/", "Download"),
            ("...", "Download"),
            ("", "Download"),
        ]
        for (input, expected) in names {
            try check(MetisWebPolicy.safeDownloadName(input) == expected,
                      "Unsafe download filename was not sanitized")
        }
        for input in [String(repeating: "a", count: 400), String(repeating: "🌱", count: 100)] {
            let safe = MetisWebPolicy.safeDownloadName(input)
            try check(!safe.isEmpty && safe.utf8.count <= 180, "Download filename was not bounded in bytes")
            try check(!safe.contains("\u{FFFD}"), "Truncating a filename split a Unicode character")
        }
    }
}

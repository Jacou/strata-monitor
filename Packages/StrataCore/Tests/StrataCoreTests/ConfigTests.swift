import XCTest
@testable import StrataCore

/// `GET /config` / `POST /config`: the lenient models, the grouping the screen draws, the diff a
/// Save sends, and what the store does with the server's answers.
final class ConfigTests: XCTestCase {
    private let base = URL(string: "http://192.168.1.10:8081")!

    private func decode(_ json: String) throws -> ConfigResponse {
        try Fixtures.decode(ConfigResponse.self, json)
    }

    // MARK: - the real payload

    private func fixture() throws -> ConfigResponse {
        try JSONDecoder().decode(ConfigResponse.self, from: Fixtures.data("config", testClass: type(of: self)))
    }

    func testFixtureDecodes() throws {
        let response = try fixture()
        XCTAssertEqual(response.file, "strata-iq3_xxs.json")
        let keys = try XCTUnwrap(response.keys)
        XCTAssertEqual(keys.count, 15)

        let temperature = try XCTUnwrap(keys.first { $0.key == "sampling.temperature" })
        XCTAssertEqual(temperature.kind, .number)
        XCTAssertEqual(temperature.value, .null)                       // "value": null → the file's own default
        XCTAssertEqual(temperature.help, "Default temperature for requests that send none (0 = greedy, the default without a sampling block)")

        let vram = try XCTUnwrap(keys.first { $0.key == "vram_reserve_mib" })
        XCTAssertEqual(vram.value, .number(700))
        XCTAssertEqual(vram.value?.text, "700")

        let thinking = try XCTUnwrap(keys.first { $0.key == "anthropic_thinking" })
        XCTAssertEqual(thinking.kind, .enum)
        XCTAssertEqual(thinking.options.map(\.text), ["model", "on_request"])

        let aliases = try XCTUnwrap(keys.first { $0.key == "aliases" })
        XCTAssertEqual(aliases.kind, .names)
    }

    /// The payload's `note` is not a key and must not upset the decode.
    func testUnknownTopLevelKeysAreIgnored() throws {
        let response = try decode(#"{"file":"f.json","note":"whatever","keys":[]}"#)
        XCTAssertEqual(response.file, "f.json")
        XCTAssertEqual(response.keys?.count, 0)
    }

    // MARK: - lenient kinds and values

    func testKindNamesMapToControls() throws {
        func kind(_ raw: String) -> ConfigKind {
            (try? decode(#"{"keys":[{"key":"k","kind":"\#(raw)"}]}"#).keys?.first?.kind) ?? .other("missing")
        }
        XCTAssertEqual(kind("number"), .number)
        XCTAssertEqual(kind("bool"), .boolean)
        XCTAssertEqual(kind("boolean"), .boolean)
        XCTAssertEqual(kind("enum"), .enum)
        XCTAssertEqual(kind("names"), .names)
        XCTAssertEqual(kind("string"), .names)
        XCTAssertEqual(kind("text"), .names)
        XCTAssertEqual(kind("list"), .names)
        XCTAssertEqual(kind("quant"), .other("quant"))   // an unknown kind stays readable
        XCTAssertEqual(kind(""), .other(""))
        XCTAssertEqual(ConfigKind.other("quant").label, "quant")
        XCTAssertEqual(ConfigKind.other("").label, "value")
    }

    func testABoolKeyOffersOnAndOffEvenWithoutChoices() throws {
        let key = try XCTUnwrap(decode(#"{"keys":[{"key":"k","kind":"bool","value":true}]}"#).keys?.first)
        XCTAssertEqual(key.value, .bool(true))
        XCTAssertEqual(key.options.map(\.text), ["true", "false"])
    }

    func testValuesArriveAsNumbersStringsBoolsAndLists() throws {
        let keys = try XCTUnwrap(decode(
            """
            {"keys": [
              {"key":"a","kind":"number","value":0.6},
              {"key":"b","kind":"number","value":"40"},
              {"key":"c","kind":"bool","value":"true"},
              {"key":"d","kind":"names","value":["strata","alias"]},
              {"key":"e","kind":"names","value":"strata, alias"},
              {"key":"f","kind":"enum","value":null},
              {"key":"g","kind":"number"},
              {"key":"h","kind":"enum","value":"end","choices":["start","end"]},
              {"key":"i","kind":"bool","value":1}
            ]}
            """
        ).keys)

        XCTAssertEqual(keys.map(\.value), [
            .number(0.6), .number(40), .bool(true),
            .names(["strata", "alias"]), .string("strata, alias"), .null, nil,
            .string("end"), .bool(true),
        ])
        XCTAssertEqual(keys[0].value?.text, "0.6")
        XCTAssertEqual(keys[1].value?.text, "40")
        XCTAssertEqual(keys[2].value?.text, "true")
        XCTAssertEqual(keys[3].value?.text, "strata, alias")
        XCTAssertEqual(keys[5].value?.text, "default")
    }

    /// A kind the server does not know keeps whatever arrived, rather than guessing.
    func testUnknownKindsLeaveTheValueAlone() throws {
        let keys = try XCTUnwrap(decode(#"{"keys":[{"key":"a","kind":"quant","value":"4bit"},{"key":"b","kind":"quant","value":7}]}"#).keys)
        XCTAssertEqual(keys.map(\.value), [.string("4bit"), .number(7)])
    }

    /// "missing" and "null" are different: a null is the file's default, a missing field is unknown.
    func testMissingValueIsNilAndNullIsTheDefault() throws {
        let keys = try XCTUnwrap(decode(#"{"keys":[{"key":"a","value":null},{"key":"b"}]}"#).keys)
        XCTAssertEqual(keys[0].value, .null)
        XCTAssertNil(keys[1].value)
    }

    func testAJunkKeyIsDroppedRatherThanFailingThePayload() throws {
        let response = try decode(#"{"file":"f","keys":[{"key":"a","kind":"number"}, "junk", 7, {"key":"b","kind":"bool"}]}"#)
        XCTAssertEqual(response.keys?.map(\.key), ["a", "b"])
    }

    func testMissingKeysArrayStillDecodes() throws {
        let response = try decode(#"{"file":"f"}"#)
        XCTAssertNil(response.keys)
        XCTAssertTrue(ConfigViewModel(response).isEmpty)
    }

    // MARK: - the POST body

    func testRequestBodyIsSetWithTheKeyMappedToTheValue() throws {
        XCTAssertEqual(try encodeBody(ConfigRequest(set: ["sampling.temperature": .number(0.6)])),
                       #"{"set":{"sampling.temperature":0.6}}"#)
    }

    /// Clearing a value sends null, which is how the web page says "use the default again".
    func testClearingAValueSendsNull() throws {
        XCTAssertEqual(try encodeBody(ConfigRequest(set: ["idle_unload_s": .null])),
                       #"{"set":{"idle_unload_s":null}}"#)
    }

    func testWholeNumbersAreSentAsIntegers() throws {
        XCTAssertEqual(try encodeBody(ConfigRequest(set: ["vram_reserve_mib": .number(700)])),
                       #"{"set":{"vram_reserve_mib":700}}"#)
        XCTAssertEqual(try encodeBody(ConfigRequest(set: ["top_k": .number(20.0)])),
                       #"{"set":{"top_k":20}}"#)
    }

    /// The server splits a `names` value at commas, so one goes back the same way.
    func testNamesAreSentAsOneCommaSeparatedString() throws {
        XCTAssertEqual(try encodeBody(ConfigRequest(set: ["aliases": .names(["strata", "alias"])])),
                       #"{"set":{"aliases":"strata, alias"}}"#)
        XCTAssertEqual(try encodeBody(ConfigRequest(set: ["k": .bool(false)])), #"{"set":{"k":false}}"#)
        XCTAssertEqual(try encodeBody(ConfigRequest(set: ["j": .string("end")])), #"{"set":{"j":"end"}}"#)
    }

    private func encodeBody(_ request: ConfigRequest) throws -> String {
        let data = try JSONEncoder().encode(request)
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - the reply

    func testReplyCarriesWhatChangedAndTheBackupFile() throws {
        let reply = try Fixtures.decode(ConfigReply.self, #"{"changed":["sampling.top_k"],"file":"strata.json"}"#)
        XCTAssertEqual(reply.changed, ["sampling.top_k"])
        XCTAssertEqual(reply.file, "strata.json")
        XCTAssertNil(reply.errorMessage)
    }

    func testReplyCarriesTheServersOwnWordsWhenItRefuses() throws {
        let reply = try Fixtures.decode(
            ConfigReply.self,
            #"{"error":{"type":"invalid_request_error","message":"'__probe__' cannot be changed here"}}"#
        )
        XCTAssertEqual(reply.errorMessage, "'__probe__' cannot be changed here")
        XCTAssertEqual(reply.error?.type, "invalid_request_error")
    }

    // MARK: - grouping

    func testKeysGroupByTheirPrefixInServerOrder() {
        let model = ConfigViewModel(try? fixture())
        XCTAssertEqual(model.groups.map(\.name), ["sampling", "General"])
        XCTAssertEqual(model.groups.map(\.title), ["Sampling", "General"])
        XCTAssertEqual(model.groups[0].rows.map(\.key), [
            "sampling.temperature", "sampling.top_p", "sampling.top_k", "sampling.min_p",
        ])
        XCTAssertEqual(model.groups[1].rows.count, 11)
        XCTAssertEqual(model.keyCount, 15)
        XCTAssertEqual(model.file, "strata-iq3_xxs.json")
    }

    func testGroupFor() {
        XCTAssertEqual(ConfigViewModel.group(for: "sampling.top_k"), "sampling")
        XCTAssertEqual(ConfigViewModel.group(for: "lazy_load"), "General")
        XCTAssertEqual(ConfigViewModel.group(for: "a.b.c"), "a")
        XCTAssertEqual(ConfigViewModel.group(for: ""), "General")
    }

    func testRowsShowTheCurrentValueOrTheWordDefault() {
        let model = ConfigViewModel(ConfigResponse(file: "f", keys: [
            ConfigKey(key: "a", value: .number(700), kind: .number, help: "leaves VRAM free"),
            ConfigKey(key: "b", value: .null, kind: .boolean),
            ConfigKey(key: "c", kind: .other("quant")),
        ]))
        let rows: [ConfigViewModel.Row] = model.groups.first?.rows ?? []
        XCTAssertEqual(rows.map(\.valueText), ["700", "default", "default"])
        XCTAssertEqual(rows.map(\.isDefault), [false, true, true])
        XCTAssertEqual(rows.map(\.kindLabel), ["number", "bool", "quant"])
        XCTAssertEqual(rows[0].help, "leaves VRAM free")
        XCTAssertEqual(rows[1].help, "")
    }

    // MARK: - the diff a Save sends

    private var keys: [ConfigKey] {
        [
            ConfigKey(key: "temperature", value: .number(0.6), kind: .number),
            ConfigKey(key: "top_k", value: .number(20), kind: .number),
            ConfigKey(key: "lazy", value: .bool(false), kind: .boolean),
            ConfigKey(key: "aliases", value: .string("strata"), kind: .names),
            ConfigKey(key: "reserve", value: .null, kind: .number),
        ]
    }

    func testOnlyEditedKeysAreSent() {
        let changes = ConfigViewModel.changes(keys: keys, edits: ["top_k": .number(40)])
        XCTAssertEqual(changes, ["top_k": .number(40)])
    }

    func testUntouchedKeysAreNeverSentEvenWhenTheyWouldDiffer() {
        XCTAssertTrue(ConfigViewModel.changes(keys: keys, edits: [:]).isEmpty)
    }

    /// A value the same as the server's is not a change, so the Save button stays disabled.
    func testAValueThatMatchesTheServerIsNotAChange() {
        XCTAssertTrue(ConfigViewModel.changes(keys: keys, edits: ["top_k": .number(20)]).isEmpty)
        XCTAssertTrue(ConfigViewModel.changes(keys: keys, edits: ["lazy": .bool(false)]).isEmpty)
        XCTAssertTrue(ConfigViewModel.changes(keys: keys, edits: ["aliases": .string("strata")]).isEmpty)
    }

    /// Clearing a key is a change: it sends null.
    func testClearingIsAChangeAndSendsNull() {
        XCTAssertEqual(ConfigViewModel.changes(keys: keys, edits: ["top_k": nil]), ["top_k": .null])
    }

    /// A key already at its default stays at its default when "cleared".
    func testClearingAnAlreadyDefaultKeyIsNotAChange() {
        XCTAssertTrue(ConfigViewModel.changes(keys: keys, edits: ["reserve": nil]).isEmpty)
    }

    /// The web page compares `JSON.stringify(old ?? null)` with the new value; a number typed into
    /// a field arrives as text, and that is the same value.
    func testNumbersAndNumericStringsMatch() {
        XCTAssertFalse(ConfigViewModel.differs(from: .number(20), to: .string("20")))
        XCTAssertFalse(ConfigViewModel.differs(from: .string("20"), to: .number(20)))
        XCTAssertTrue(ConfigViewModel.differs(from: .number(20), to: .string("21")))
        XCTAssertTrue(ConfigViewModel.differs(from: .number(0.6), to: .string("0.7")))
    }

    func testDiffersAcrossKinds() {
        XCTAssertFalse(ConfigViewModel.differs(from: nil, to: .null))
        XCTAssertFalse(ConfigViewModel.differs(from: .null, to: nil))
        XCTAssertTrue(ConfigViewModel.differs(from: .bool(true), to: .bool(false)))
        XCTAssertTrue(ConfigViewModel.differs(from: .bool(true), to: .string("true")))
        XCTAssertTrue(ConfigViewModel.differs(from: nil, to: .number(1)))
        XCTAssertTrue(ConfigViewModel.differs(from: .names(["a", "b"]), to: .names(["a"])))
        XCTAssertTrue(ConfigViewModel.differs(from: .string("model"), to: .string("on_request")))
    }

    // MARK: - the store

    private func client(_ transport: some HTTPTransport) -> StrataClient {
        StrataClient(baseURL: base, apiKey: "k", transport: transport)
    }

    /// Answers GET /config with `get` and POST /config with whatever the test wants back.
    private func server(
        get: String,
        post: (body: String, status: Int) = (body: #"{"changed":[],"file":"f"}"#, status: 200)
    ) -> StubTransport {
        let url = base
        return StubTransport { request in
            let isPost = request.httpMethod == "POST"
            return (Data((isPost ? post.body : get).utf8), httpResponse(url, isPost ? post.status : 200))
        }
    }

    @MainActor
    func testStoreLoadsTheServersKeys() async throws {
        let store = ConfigStore()
        await store.load(client: client(StubTransport.respondingData(try Fixtures.data("config", testClass: type(of: self)))))
        XCTAssertEqual(store.model.keyCount, 15)
        XCTAssertEqual(store.model.file, "strata-iq3_xxs.json")
        XCTAssertFalse(store.isUnavailable)
        XCTAssertNil(store.errorText)
    }

    @MainActor
    func testStoreSaysSoWhenTheServerHasNoRunConfig() async throws {
        let store = ConfigStore()
        await store.load(client: client(StubTransport.status(404)))
        XCTAssertTrue(store.isUnavailable)
        XCTAssertEqual(store.errorText, "This server does not expose its run config (HTTP 404).")
        XCTAssertTrue(store.model.isEmpty)
    }

    @MainActor
    func testStoreAsksForTheKeyBeforeBlamingTheServer() async {
        let store = ConfigStore()
        await store.load(client: client(StubTransport.status(401)))
        XCTAssertTrue(store.isUnavailable)
        XCTAssertEqual(store.errorText, "The server needs its API key before it will show the run config.")
    }

    @MainActor
    func testStoreWithoutAnAddressSaysWhatToFix() async {
        let store = ConfigStore()
        await store.load(client: nil)
        XCTAssertTrue(store.isUnavailable)
        XCTAssertEqual(store.errorText, "Set the server address in Settings first.")
    }

    @MainActor
    func testStoreHoldsAnEditUntilItIsSaved() async throws {
        let transport = server(get: #"{"file":"f","keys":[{"key":"top_k","kind":"number","value":20}]}"#)
        let store = ConfigStore()
        await store.load(client: client(transport))

        let key = try XCTUnwrap(store.model.keys.first)
        XCTAssertEqual(store.value(for: key), .number(20))
        XCTAssertFalse(store.hasChanges)

        store.setEdit(.number(40), for: key.key)
        XCTAssertEqual(store.value(for: key), .number(40))
        XCTAssertTrue(store.hasChanges)
        XCTAssertEqual(store.pendingChanges, ["top_k": .number(40)])

        store.discardEdits()
        XCTAssertEqual(store.value(for: key), .number(20))
        XCTAssertFalse(store.hasChanges)
    }

    @MainActor
    func testStorePostsTheChangesThenReReadsTheFile() async throws {
        let url = base
        let gets = CallCounter()
        let transport = StubTransport { request in
            if request.httpMethod == "POST" {
                return (Data(#"{"changed":["top_k"],"file":"strata"}"#.utf8), httpResponse(url, 200))
            }
            // The first GET is the load, the second is the re-read a save triggers.
            let body = gets.next() == 1
                ? #"{"file":"f","keys":[{"key":"top_k","kind":"number","value":20}]}"#
                : #"{"file":"strata","keys":[{"key":"top_k","kind":"number","value":40}]}"#
            return (Data(body.utf8), httpResponse(url, 200))
        }
        let store = ConfigStore()
        await store.load(client: client(transport))
        store.setEdit(.number(40), for: "top_k")
        await store.save(client: client(transport))

        let post = try XCTUnwrap(transport.requests.first { $0.httpMethod == "POST" })
        XCTAssertEqual(post.url?.path, "/config")
        XCTAssertEqual(post.httpMethod, "POST")
        XCTAssertEqual(post.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(post.value(forHTTPHeaderField: "Authorization"), "Bearer k")
        XCTAssertEqual(String(decoding: try XCTUnwrap(post.httpBody), as: UTF8.self), #"{"set":{"top_k":40}}"#)

        // Re-fetched, so the rows show the file rather than what was typed.
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "GET" }.count, 2)
        XCTAssertEqual(store.model.keys.first?.value, .number(40))
        XCTAssertFalse(store.hasChanges)
        XCTAssertEqual(store.message, "Saved top_k. The earlier file is strata.bak — start the model again to use it.")
        XCTAssertNil(store.errorText)
    }

    @MainActor
    func testStoreSendsNullWhenAKeyIsCleared() async throws {
        let transport = server(
            get: #"{"file":"f","keys":[{"key":"reserve","kind":"number","value":700}]}"#,
            post: (#"{"changed":["reserve"],"file":"f"}"#, 200)
        )
        let store = ConfigStore()
        await store.load(client: client(transport))
        store.setEdit(nil, for: "reserve")
        await store.save(client: client(transport))

        let post = try XCTUnwrap(transport.requests.first { $0.httpMethod == "POST" })
        XCTAssertEqual(String(decoding: try XCTUnwrap(post.httpBody), as: UTF8.self), #"{"set":{"reserve":null}}"#)
    }

    @MainActor
    func testStoreSaysNothingChangedWithoutHittingTheServer() async throws {
        let transport = server(get: #"{"file":"f","keys":[{"key":"top_k","kind":"number","value":20}]}"#)
        let store = ConfigStore()
        await store.load(client: client(transport))
        await store.save(client: client(transport))

        XCTAssertEqual(store.message, "Nothing changed.")
        XCTAssertFalse(transport.requests.contains { $0.httpMethod == "POST" })
    }

    @MainActor
    func testStoreShowsTheServersOwnWordsAboutARejectedValue() async throws {
        let transport = server(
            get: #"{"file":"f","keys":[{"key":"top_k","kind":"number","value":20}]}"#,
            post: (#"{"error":{"type":"invalid_request_error","message":"'top_k' must be between 1 and 64"}}"#, 400)
        )
        let store = ConfigStore()
        await store.load(client: client(transport))
        store.setEdit(.number(999), for: "top_k")
        await store.save(client: client(transport))

        XCTAssertEqual(store.errorText, "'top_k' must be between 1 and 64")
        XCTAssertNil(store.message)
        // The edit stays on screen so the value can be fixed rather than retyped.
        XCTAssertTrue(store.hasChanges)
        XCTAssertEqual(store.pendingChanges, ["top_k": .number(999)])
        // Only the load ran a GET: a refused save does not re-read.
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "GET" }.count, 1)
    }

    @MainActor
    func testStoreReportsAPlainHTTPFailureWithoutAmessage() async throws {
        let transport = server(
            get: #"{"file":"f","keys":[{"key":"top_k","kind":"number","value":20}]}"#,
            post: (body: "{}", status: 500)
        )
        let store = ConfigStore()
        await store.load(client: client(transport))
        store.setEdit(.number(1), for: "top_k")
        await store.save(client: client(transport))
        XCTAssertEqual(store.errorText, "Server replied HTTP 500")
    }
}

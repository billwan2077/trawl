@testable import TrawlCore
import XCTest

final class SpotlightQueryBuilderTests: XCTestCase {
    private func plan(_ query: String, _ configure: (inout SearchOptions) -> Void = { _ in }) -> SpotlightQueryBuilder.Plan {
        var options = SearchOptions(roots: [URL(fileURLWithPath: "/tmp")])
        configure(&options)
        return SpotlightQueryBuilder.plan(for: query, options: options)
    }

    func testNameQueries() {
        XCTAssertEqual(plan("report"), .query(#"kMDItemFSName == "*report*"c"#))
        XCTAssertEqual(plan("*.pdf"), .query(#"kMDItemFSName == "*.pdf"c"#))
        XCTAssertEqual(plan("a OR b c"),
                       .query(#"(kMDItemFSName == "*a*"c || (kMDItemFSName == "*b*"c && kMDItemFSName == "*c*"c))"#))
        XCTAssertEqual(plan("budget -draft"), .query(#"kMDItemFSName == "*budget*"c"#), "NOT is left to Matcher")
        XCTAssertEqual(plan(#"say "hi""#) , .query(#"(kMDItemFSName == "*say*"c && kMDItemFSName == "*hi*"c)"#))
        XCTAssertEqual(plan("Report") { $0.match.caseSensitive = true }, .query(#"kMDItemFSName == "*Report*""#))
    }

    func testContentQueries() {
        XCTAssertEqual(plan("budget") { $0.target = .contents }, .query(#"kMDItemTextContent == "budget*"c"#))
        XCTAssertEqual(plan(#""annual report""#) { $0.target = .contents },
                       .query(#"kMDItemTextContent == "annual report"c"#))
        XCTAssertEqual(plan("q3") { $0.target = .both },
                       .query(#"(kMDItemFSName == "*q3*"c || kMDItemTextContent == "q3*"c)"#))
        XCTAssertEqual(plan("q3 -draft") { $0.target = .both }, .query(#"kMDItemFSName == "*q3*"c"#),
                       "content side dropped when the query has NOT")
    }

    func testSkippedQueries() {
        guard case .skip = plan("a.*b", { $0.match.useRegex = true }) else { return XCTFail("regex") }
        guard case .skip = plan("NOT draft") else { return XCTFail("negative only") }
        guard case .skip = plan("budget -draft", { $0.target = .contents }) else { return XCTFail("content NOT") }
    }

    func testTypeFilterAndEscaping() {
        guard case .query(let q) = plan("x", { $0.fileTypes = [.pdf] }) else { return XCTFail() }
        XCTAssertEqual(q, #"(kMDItemFSName == "*x*"c && (kMDItemFSName == "*.pdf"c))"#)
        XCTAssertEqual(SpotlightQueryBuilder.escape(#"a"b\c*"#), #"a\"b\\c\*"#)
    }
}

final class HybridSearcherTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Tool.app/Contents"), withIntermediateDirectories: true)
        for name in ["report.txt", "memo.docx", ".hidden/report.txt", "Tool.app/Contents/report.txt"] {
            try "plain text".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func path(_ name: String) -> String { root.appendingPathComponent(name).path }

    func testVerifyAppliesSearchOptions() throws {
        var options = SearchOptions(roots: [root])
        let matcher = try Matcher(query: "report")
        func check(_ name: String, allowed: Bool = true) -> SearchResult? {
            HybridSearcher.verify(path(name), options: options, matcher: matcher, contentHitsAllowed: allowed)
        }
        XCTAssertEqual(check("report.txt")?.sources, .spotlight)
        XCTAssertNil(check("memo.docx"), "name search re-checks the name")
        XCTAssertNil(check(".hidden/report.txt"))
        XCTAssertNil(check("Tool.app/Contents/report.txt"))
        XCTAssertNil(check("missing-report.txt"))
        XCTAssertNil(HybridSearcher.verify("/etc/report.txt", options: options, matcher: matcher, contentHitsAllowed: true))

        options.target = .contents
        XCTAssertEqual(check("memo.docx")?.matchedContent, true, "Office content hits are kept")
        XCTAssertNil(check("memo.docx", allowed: false), "but not when the query has NOT")
        options.fileTypes = [.word]
        XCTAssertNotNil(check("memo.docx"))
        XCTAssertNil(check("report.txt"))
    }

    func testMergeDeduplicatesAndTracksSources() async throws {
        var options = SearchOptions(roots: [root])
        options.target = .both
        let matcher = try Matcher(query: "report")
        let walk = FileSearcher.search(options, matcher: matcher)
        let spotlight = AsyncStream<[String]> { $0.yield([path("report.txt"), path("memo.docx")]); $0.finish() }
        let stream = HybridSearcher.merge(walk: walk, spotlight: spotlight, notice: "note") {
            HybridSearcher.verify($0, options: options, matcher: matcher, contentHitsAllowed: true)
        }

        var sources: [String: SearchSources] = [:]
        var finished: SearchSources = []
        var notices: [String] = []
        var ended = false
        for await event in stream {
            switch event {
            case .results(let batch): batch.forEach { sources[$0.name, default: []].formUnion($0.sources) }
            case let .sourcesAdded(urls, source): urls.forEach { sources[$0.lastPathComponent, default: []].formUnion(source) }
            case .engineFinished(let engine, _): finished.formUnion(engine)
            case .notice(let text): notices.append(text)
            case .finished: ended = true
            case .progress, .unreadable: break
            }
        }
        XCTAssertEqual(sources, ["report.txt": [.spotlight, .walk], "memo.docx": .spotlight])
        XCTAssertEqual(finished, [.spotlight, .walk])
        XCTAssertEqual(notices, ["note"])
        XCTAssertTrue(ended)
    }

    func testMergeWithNoEnginesFinishes() async {
        var events = 0
        for await _ in HybridSearcher.merge(walk: nil, spotlight: nil, notice: nil, verify: { _ in nil }) { events += 1 }
        XCTAssertEqual(events, 1, "only .finished")
    }
}

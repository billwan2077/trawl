@testable import TrawlCore
import XCTest

final class FileSearcherTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("docs/.hidden"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Tool.app/Contents"), withIntermediateDirectories: true)
        try "meeting notes: budget approved".write(to: root.appendingPathComponent("docs/notes.txt"), atomically: true, encoding: .utf8)
        try "budget".write(to: root.appendingPathComponent("docs/.hidden/secret budget.txt"), atomically: true, encoding: .utf8)
        try "budget".write(to: root.appendingPathComponent("Tool.app/Contents/budget.txt"), atomically: true, encoding: .utf8)
        try Data([0x62, 0x75, 0x64, 0x00, 0x67, 0x65, 0x74]).write(to: root.appendingPathComponent("docs/blob.bin"))
        try "budget".data(using: .utf16)!.write(to: root.appendingPathComponent("docs/wide.txt"))
        for name in ["Q3.docx", "q3.xlsx", "server.log", "Photo.JPG"] {
            try "x".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func names(_ query: String, configure: (inout SearchOptions) -> Void = { _ in }) async throws -> [String] {
        var options = SearchOptions(roots: [root])
        configure(&options)
        var found: [String] = []
        for await event in FileSearcher.search(options, matcher: try Matcher(query: query, options: options.match)) {
            if case .results(let batch) = event { found += batch.map(\.name) }
        }
        return found.sorted()
    }

    func testNameSearchSkipsHiddenAndPackagesByDefault() async throws {
        let found = try await names("budget")
        XCTAssertEqual(found, [])
        let withHidden = try await names("budget") { $0.includeHidden = true; $0.searchPackages = true }
        XCTAssertEqual(withHidden, ["budget.txt", "secret budget.txt"])
    }

    func testContentSearchSkipsBinaryAndReadsUTF16() async throws {
        let found = try await names("budget") { $0.target = .contents }
        XCTAssertEqual(found, ["notes.txt", "wide.txt"])
    }

    func testFoldersCanBeExcluded() async throws {
        let withFolders = try await names("docs")
        XCTAssertEqual(withFolders, ["docs"])
        let without = try await names("docs") { $0.includeFolders = false }
        XCTAssertEqual(without, [])
    }

    func testFileTypeFilterLimitsSearchAndExcludesFolders() async throws {
        let all = try await names("q3 OR server OR photo")
        XCTAssertEqual(all, ["Photo.JPG", "Q3.docx", "q3.xlsx", "server.log"])
        let some = try await names("q3 OR server OR photo") { $0.fileTypes = [.word, .log] }
        XCTAssertEqual(some, ["Q3.docx", "server.log"])
        let folders = try await names("docs") { $0.fileTypes = FileCategory.common }
        XCTAssertEqual(folders, [])
    }

    func testCategoryLookup() {
        XCTAssertEqual(FileCategory(fileExtension: "PPTX"), .powerpoint)
        XCTAssertEqual(FileCategory(url: URL(fileURLWithPath: "/a/photo.heic")), .image)
        XCTAssertEqual(FileCategory(url: URL(fileURLWithPath: "/a/clip.mov")), .video)
        XCTAssertNil(FileCategory(fileExtension: "swift"))
        XCTAssertNil(FileCategory(fileExtension: ""))
    }

    func testNestedRootsAreDeduplicated() {
        let roots = [URL(fileURLWithPath: "/a/b"), URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/ab"), URL(fileURLWithPath: "/a")]
        XCTAssertEqual(FileSearcher.normalizedRoots(roots).map(\.path), ["/a", "/ab"])
    }
}

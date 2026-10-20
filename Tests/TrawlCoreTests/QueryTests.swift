@testable import TrawlCore
import XCTest

final class QueryTests: XCTestCase {
    func testImplicitAndAndPrecedence() throws {
        XCTAssertEqual(try QueryParser.parse("a b OR c"),
                       .or(.and(.term("a", phrase: false), .term("b", phrase: false)), .term("c", phrase: false)))
        XCTAssertEqual(try QueryParser.parse("a AND NOT b"),
                       .and(.term("a", phrase: false), .not(.term("b", phrase: false))))
        XCTAssertEqual(try QueryParser.parse("(a | b) & c"),
                       .and(.or(.term("a", phrase: false), .term("b", phrase: false)), .term("c", phrase: false)))
    }

    func testPhrasesPrefixNegationAndLowercaseOperators() throws {
        XCTAssertEqual(try QueryParser.parse("\"annual report\" -draft"),
                       .and(.term("annual report", phrase: true), .not(.term("draft", phrase: false))))
        XCTAssertEqual(try QueryParser.parse("cats and dogs"),
                       .and(.and(.term("cats", phrase: false), .term("and", phrase: false)), .term("dogs", phrase: false)))
        XCTAssertEqual(try QueryParser.parse("R&D a-b"),
                       .and(.term("R&D", phrase: false), .term("a-b", phrase: false)))
    }

    func testErrors() {
        for bad in ["", "   ", "(a", "a)", "a OR", "AND a", "\"open"] {
            XCTAssertThrowsError(try QueryParser.parse(bad), bad)
        }
    }

    func testNameMatching() throws {
        let pdf = try Matcher(query: "*.pdf")
        XCTAssertTrue(pdf.matchesName("Report.PDF"))
        XCTAssertFalse(pdf.matchesName("report.pdf.zip"))

        let q = try Matcher(query: "img_?? OR (budget -draft)")
        XCTAssertTrue(q.matchesName("IMG_01"))
        XCTAssertFalse(q.matchesName("img_001"))
        XCTAssertTrue(q.matchesName("Budget 2026.xlsx"))
        XCTAssertFalse(q.matchesName("budget draft.xlsx"))

        XCTAssertFalse(try Matcher(query: "readme", options: MatchOptions(caseSensitive: true)).matchesName("README"))
    }

    func testContentMatching() throws {
        let text = "Quarterly numbers\nThe annual report is attached.\n"
        XCTAssertTrue(try Matcher(query: "\"annual report\" quarterly").matchesContent(text))
        XCTAssertFalse(try Matcher(query: "\"report annual\"").matchesContent(text))
        XCTAssertTrue(try Matcher(query: "ann*port").matchesContent(text))
        XCTAssertFalse(try Matcher(query: "Quarterly*attached").matchesContent(text), "* does not cross lines")
        XCTAssertTrue(try Matcher(query: #"\bnum\w+"#, options: MatchOptions(useRegex: true)).matchesContent(text))
        XCTAssertThrowsError(try Matcher(query: "([", options: MatchOptions(useRegex: true)))
    }
}

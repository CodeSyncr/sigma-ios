import XCTest
@testable import NimbusSigma

final class FormulaHintTests: XCTestCase {
    let fns = [
        SigmaFunction(name: "SUM", category: "Math", syntax: "SUM(number1, [number2, …])", description: "Adds numbers and ranges."),
        SigmaFunction(name: "SUMIF", category: "Math", syntax: "SUMIF(range, criterion, [sum_range])", description: ""),
        SigmaFunction(name: "SUMIFS", category: "Math", syntax: "SUMIFS(sum_range, range1, criterion1, [range2, criterion2, …])", description: ""),
        SigmaFunction(name: "IF", category: "Logical", syntax: "IF(condition, value_if_true, [value_if_false])", description: ""),
        SigmaFunction(name: "ROUND", category: "Math", syntax: "ROUND(number, [places])", description: ""),
        SigmaFunction(name: "SUBSTITUTE", category: "Text", syntax: "SUBSTITUTE(text, old, new, [occurrence])", description: ""),
    ]

    func names(_ h: FormulaHint) -> [String] {
        if case let .suggest(_, m) = h { return m.map(\.name) }
        return []
    }

    func testSuggestsShortestFirst() {
        XCTAssertEqual(names(FormulaHint.of("=SU", functions: fns)), ["SUM", "SUMIF", "SUMIFS", "SUBSTITUTE"])
        XCTAssertEqual(names(FormulaHint.of("=A1+ro", functions: fns)), ["ROUND"])
    }

    func testNothingOutsideAFormula() {
        XCTAssertEqual(FormulaHint.of("SU", functions: fns), .none)
        XCTAssertEqual(FormulaHint.of("=", functions: fns), .none)
    }

    func testArgumentHints() {
        XCTAssertEqual(FormulaHint.of("=SUMIF(", functions: fns), .arguments(fns[1], argument: 0))
        XCTAssertEqual(FormulaHint.of("=SUMIF(A1:A9, ", functions: fns), .arguments(fns[1], argument: 1))
        XCTAssertEqual(FormulaHint.of("=sumif(A1:A9,\">5\",", functions: fns), .arguments(fns[1], argument: 2))
        XCTAssertEqual(FormulaHint.of("=IF(ROUND(B2, ", functions: fns), .arguments(fns[4], argument: 1))
        XCTAssertEqual(FormulaHint.of("=IF(ROUND(B2, 1), ", functions: fns), .arguments(fns[3], argument: 1))
        XCTAssertEqual(FormulaHint.of("=IF(\"a, b", functions: fns), .arguments(fns[3], argument: 0))
    }

    func testExactNameOffersLongerOnes() {
        XCTAssertEqual(names(FormulaHint.of("=SUM", functions: fns)), ["SUMIF", "SUMIFS"])
    }

    func testSplitsArguments() {
        XCTAssertEqual(FormulaHint.arguments("SUM(number1, [number2, …])"), ["number1", "[number2, …]"])
        XCTAssertEqual(FormulaHint.arguments("SUMIF(range, criterion, [sum_range])"), ["range", "criterion", "[sum_range]"])
        XCTAssertEqual(FormulaHint.arguments("PI()"), [])
    }
}

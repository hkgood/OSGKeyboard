import XCTest
@testable import OSGKeyboardShared

final class PolishOutputValidatorTests: XCTestCase {
    func testMissingDictionaryCanonicalTermIsHardViolation() {
        let dictionary = PersonalDictionary(entries: [
            .init(
                term: "Kubernetes",
                aliases: ["k8s"],
                category: .productName,
                source: .manual
            ),
        ])
        let violations = PolishOutputValidator.validate(
            input: "部署 k8s 集群",
            output: "部署容器集群",
            dictionary: dictionary,
            lengthRatio: 0.5...2
        )
        XCTAssertTrue(violations.contains(.missingDictionaryTerms(["Kubernetes"])))
        XCTAssertTrue(violations.contains(where: \.isHard))
    }

    func testIdentifiersArePreservedExactly() {
        let violations = PolishOutputValidator.validate(
            input: "send https://example.com/a to dev@example.com using user_id",
            output: "send it to the team",
            dictionary: .empty,
            lengthRatio: 0.5...2
        )
        XCTAssertTrue(violations.contains { violation in
            if case .missingIdentifiers(let values) = violation {
                return values.contains("https://example.com/a")
                    && values.contains("dev@example.com")
                    && values.contains("user_id")
            }
            return false
        })
    }

    func testNumbersLengthAndLanguageAreObservationOnly() {
        let violations = PolishOutputValidator.validate(
            input: "项目 123 明天下午交付并通知全部相关成员",
            output: "Ship tomorrow.",
            dictionary: .empty,
            lengthRatio: 0.9...1.1
        )
        XCTAssertFalse(violations.isEmpty)
        XCTAssertTrue(violations.filter(\.isHard).isEmpty)
    }
}

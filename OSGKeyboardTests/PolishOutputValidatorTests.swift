@testable import OSGKeyboardShared
import XCTest

final class PolishOutputValidatorTests: XCTestCase {

    func testMissingDictionaryCanonicalTermIsViolation() {
        let dictionary = PersonalDictionary(entries: [
            .init(
                term: "Kubernetes",
                aliases: ["k8s"],
                category: .productName,
                source: .manual
            )
        ])
        let violations = PolishOutputValidator.validate(
            input: "部署 k8s 集群",
            output: "部署容器集群",
            dictionary: dictionary
        )
        XCTAssertTrue(violations.contains(.missingDictionaryTerms(["Kubernetes"])))
    }

    func testIdentifiersArePreservedExactly() {
        let violations = PolishOutputValidator.validate(
            input: "send https://example.com/a to dev@example.com using user_id",
            output: "send it to the team",
            dictionary: .empty
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

    func testDatesFractionsAndSlashWordsAreNotProtectedPaths() {
        let cases = [
            ("在 2025/03/01 之前完成", "在2025年3月1日之前完成"),
            ("价格是 3/4 杯面粉", "价格是四分之三杯面粉"),
            ("我给 3/5 分", "我给五分之三"),
            ("读一下 and/or 的用法", "读一下 and or 的用法")
        ]

        for (input, output) in cases {
            let violations = PolishOutputValidator.validate(
                input: input,
                output: output,
                dictionary: .empty
            )
            XCTAssertFalse(
                violations.contains {
                    if case .missingIdentifiers = $0 { return true }
                    return false
                },
                "Must not classify slash value as a protected path: \(input)"
            )
        }
    }

    func testStrongPathSignalsRemainHardProtectedIdentifiers() {
        let inputs = [
            "/usr/local/bin",
            "../Sources/App.swift",
            "Sources/Features/Auth",
            "src/user_id"
        ]
        for input in inputs {
            let violations = PolishOutputValidator.validate(
                input: "打开 \(input)",
                output: "打开对应文件",
                dictionary: .empty
            )
            XCTAssertTrue(
                violations.contains {
                    if case .missingIdentifiers(let values) = $0 {
                        return values.contains(input)
                    }
                    return false
                },
                "Expected hard path protection for \(input)"
            )
        }
    }

}

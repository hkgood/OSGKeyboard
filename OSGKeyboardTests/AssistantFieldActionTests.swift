import XCTest
@testable import OSGKeyboardShared

@MainActor
final class AssistantFieldActionTests: XCTestCase {
    func testContentActionsRequireText() {
        let roles: [KeyboardState.ReturnKeyRole] = [
            .send,
            .go,
            .search,
            .join,
            .route,
            .google,
            .yahoo
        ]

        for role in roles {
            XCTAssertFalse(role.assistantActionAvailable(hasText: false))
            XCTAssertTrue(role.assistantActionAvailable(hasText: true))
        }
    }

    func testNavigationActionsRemainAvailableWithoutText() {
        let roles: [KeyboardState.ReturnKeyRole] = [
            .newline,
            .done,
            .next,
            .continue,
            .emergencyCall
        ]

        for role in roles {
            XCTAssertTrue(role.assistantActionAvailable(hasText: false))
        }
    }

    func testSearchRolesUseSearchSymbol() {
        XCTAssertEqual(
            KeyboardState.ReturnKeyRole.search.assistantActionSystemImage,
            "magnifyingglass"
        )
        XCTAssertEqual(
            KeyboardState.ReturnKeyRole.google.assistantActionSystemImage,
            "magnifyingglass"
        )
        XCTAssertEqual(
            KeyboardState.ReturnKeyRole.yahoo.assistantActionSystemImage,
            "magnifyingglass"
        )
    }
}

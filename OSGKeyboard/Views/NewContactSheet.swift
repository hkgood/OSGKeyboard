// NewContactSheet.swift
// OSGKeyboard · Main App
//
// System-owned contact editor used after an explicit keyboard skill handoff.

import Contacts
import ContactsUI
import SwiftUI

struct NewContactDraft: Identifiable, Equatable {
    let id = UUID()
    let phoneNumber: String
}

struct NewContactSheet: UIViewControllerRepresentable {
    let phoneNumber: String
    let onComplete: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UINavigationController {
        let contact = CNMutableContact()
        contact.phoneNumbers = [
            CNLabeledValue(
                label: CNLabelPhoneNumberMobile,
                value: CNPhoneNumber(stringValue: phoneNumber)
            )
        ]
        let editor = CNContactViewController(forNewContact: contact)
        editor.contactStore = CNContactStore()
        editor.delegate = context.coordinator
        return UINavigationController(rootViewController: editor)
    }

    func updateUIViewController(
        _ uiViewController: UINavigationController,
        context: Context
    ) {}

    final class Coordinator: NSObject, CNContactViewControllerDelegate {
        private let onComplete: () -> Void

        init(onComplete: @escaping () -> Void) {
            self.onComplete = onComplete
        }

        func contactViewController(
            _ viewController: CNContactViewController,
            didCompleteWith contact: CNContact?
        ) {
            onComplete()
        }
    }
}

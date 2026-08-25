// PersonalDictionaryEntryService.swift
// OSGKeyboard · Shared
//
// Keeps every user-confirmed term on the same save, alias-generation,
// and cloud-sync path, regardless of which UI initiated the change.

import Foundation

@MainActor
public final class PersonalDictionaryEntryService {
    public typealias AliasGeneration = @MainActor (String) async -> [String]
    public typealias CloudPush = @MainActor (PersonalDictionary) async -> Void

    public struct SavedEntry: Sendable {
        public let entryID: UUID
        public let term: String
        public let source: PersonalDictionary.Entry.Source
        public let dictionary: PersonalDictionary
        public let shouldGenerateAliases: Bool
    }

    private let store: AppGroupStore
    private let generateAliases: AliasGeneration
    private let pushToCloud: CloudPush

    public init(
        store: AppGroupStore = AppGroupStore(),
        aliasGeneration: AliasGeneration? = nil,
        cloudPush: CloudPush? = nil
    ) {
        self.store = store
        if let aliasGeneration {
            generateAliases = aliasGeneration
        } else {
            let generator = DictionaryAliasGenerator()
            generateAliases = { term in
                await generator.generateAliases(for: term)
            }
        }
        pushToCloud = cloudPush ?? { dictionary in
            try? await PersonalDictionaryCloudSync.shared.pushLocalIfEnabled(dictionary)
        }
    }

    /// Saves immediately so alias generation never blocks the user's action.
    public func saveEntry(
        term: String,
        existingID: UUID? = nil,
        source: PersonalDictionary.Entry.Source,
        minimumUsageCount: Int? = nil
    ) -> SavedEntry? {
        var shouldGenerateAliases = false
        guard let mutation = store.updatePersonalDictionary({ dictionary -> PersonalDictionary.Entry? in
            let previousTerm = existingID.flatMap { id in
                dictionary.entries.first(where: { $0.id == id })?.term
            }
            let termChanged = previousTerm.map {
                $0.caseInsensitiveCompare(term) != .orderedSame
            } ?? true

            guard let saved = dictionary.upsert(
                term: term,
                existingID: existingID,
                source: source
            ),
                  let index = dictionary.entries.firstIndex(where: { $0.id == saved.id }) else {
                return nil
            }
            if let minimumUsageCount {
                dictionary.entries[index].usageCount = max(
                    dictionary.entries[index].usageCount,
                    minimumUsageCount
                )
            }
            dictionary.version += 1
            shouldGenerateAliases = existingID == nil || termChanged
            return dictionary.entries[index]
        }) else {
            return nil
        }

        return SavedEntry(
            entryID: mutation.result.id,
            term: mutation.result.term,
            source: mutation.result.source,
            dictionary: mutation.dictionary,
            shouldGenerateAliases: shouldGenerateAliases
        )
    }

    /// Finishes the asynchronous work against the latest dictionary snapshot.
    ///
    /// The identity and canonical term checks prevent a late LLM response from
    /// restoring a deleted entry or attaching aliases after the term changed.
    @discardableResult
    public func finishSaving(_ saved: SavedEntry) async -> PersonalDictionary {
        await pushToCloud(store.personalDictionary)
        guard saved.shouldGenerateAliases else { return store.personalDictionary }

        let aliases = await generateAliases(saved.term)
        guard !aliases.isEmpty else { return store.personalDictionary }

        guard let mutation = store.updatePersonalDictionary({ dictionary -> UUID? in
            guard let current = dictionary.entries.first(where: { $0.id == saved.entryID }),
                  current.term == saved.term,
                  current.source == saved.source else {
                return nil
            }
            dictionary.updateAliases(for: saved.entryID, aliases: aliases)
            dictionary.version += 1
            return saved.entryID
        }) else {
            return store.personalDictionary
        }

        await pushToCloud(mutation.dictionary)
        // Cloud sync may merge remote entries into local storage while pushing.
        return store.personalDictionary
    }
}

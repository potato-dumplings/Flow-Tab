public enum StableIdentityOrder {
    public static func reconcile<Element, Identity: Hashable>(
        current: [Element],
        updated: [Element],
        identity: (Element) -> Identity
    ) -> [Element] {
        guard !current.isEmpty else { return updated }

        var updatedElementsByIdentity: [Identity: Element] = [:]
        var updatedIdentities: [Identity] = []
        var knownUpdatedIdentities: Set<Identity> = []
        for element in updated {
            let elementIdentity = identity(element)
            if knownUpdatedIdentities.insert(elementIdentity).inserted {
                updatedIdentities.append(elementIdentity)
            }
            updatedElementsByIdentity[elementIdentity] = element
        }

        var reconciled: [Element] = []
        reconciled.reserveCapacity(updatedElementsByIdentity.count)
        var emittedIdentities: Set<Identity> = []
        let currentIdentities = Set(current.map(identity))
        let leadingAdditions = updatedIdentities.prefix {
            !currentIdentities.contains($0)
        }
        for elementIdentity in leadingAdditions {
            if let updatedElement =
                updatedElementsByIdentity[elementIdentity],
               emittedIdentities.insert(elementIdentity).inserted {
                reconciled.append(updatedElement)
            }
        }
        for element in current {
            let elementIdentity = identity(element)
            guard
                let updatedElement = updatedElementsByIdentity[elementIdentity],
                emittedIdentities.insert(elementIdentity).inserted
            else {
                continue
            }
            reconciled.append(updatedElement)
        }
        for elementIdentity in updatedIdentities
            where emittedIdentities.insert(elementIdentity).inserted
        {
            if let element = updatedElementsByIdentity[elementIdentity] {
                reconciled.append(element)
            }
        }
        return reconciled
    }
}

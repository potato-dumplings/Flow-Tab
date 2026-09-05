#if FLOWTAB_TESTING
import Foundation

struct ControlTabPressureSelectionRenderExpectation {
    private let selectedWindowIDBefore: String?
    private let renderGenerationBefore: UInt64

    private(set) var selectedWindowID: String?
    private(set) var renderGeneration: UInt64?

    init(
        selectedWindowIDBefore: String?,
        renderGenerationBefore: UInt64
    ) {
        self.selectedWindowIDBefore = selectedWindowIDBefore
        self.renderGenerationBefore = renderGenerationBefore
    }

    mutating func observeCommandReturn(
        selectedWindowID: String?,
        renderGeneration: UInt64
    ) {
        guard isCompletedSelectionMutation(
            selectedWindowID: selectedWindowID,
            renderGeneration: renderGeneration
        ) else {
            return
        }
        self.selectedWindowID = selectedWindowID
        self.renderGeneration = renderGeneration
    }

    mutating func acceptDraw(
        selectedWindowID: String?,
        renderGeneration: UInt64,
        currentRenderGeneration: UInt64
    ) -> Bool {
        guard renderGeneration == currentRenderGeneration,
              isCompletedSelectionMutation(
                  selectedWindowID: selectedWindowID,
                  renderGeneration: renderGeneration
              )
        else {
            return false
        }
        if let expectedWindowID = self.selectedWindowID,
           selectedWindowID != expectedWindowID
        {
            return false
        }
        if let expectedGeneration = self.renderGeneration,
           renderGeneration != expectedGeneration
        {
            return false
        }
        self.selectedWindowID = selectedWindowID
        self.renderGeneration = renderGeneration
        return true
    }

    func matchesReadback(selectedWindowID: String?) -> Bool {
        guard let expectedWindowID = self.selectedWindowID,
              renderGeneration != nil
        else {
            return false
        }
        return selectedWindowID == expectedWindowID
    }

    private func isCompletedSelectionMutation(
        selectedWindowID: String?,
        renderGeneration: UInt64
    ) -> Bool {
        selectedWindowID != nil
            && selectedWindowID != selectedWindowIDBefore
            && renderGeneration > renderGenerationBefore
    }
}
#endif

import Foundation

/// One cell in the Follow Along scrub strip's flattened view — everything from where
/// the session is right now through the end of this consecutive run of Follow Along
/// sections, not just the current pass.
enum FollowAlongStripItem: Identifiable {
    case step(TimeSectionStep, sectionID: UUID, repeatIndex: Int)
    /// The synthetic inter-pass breather `WorkoutSection.sectionRest(after:)`
    /// computes — not a real `TimeSectionStep`, so it needs its own case to appear
    /// in the strip at all.
    case rest(sectionID: UUID, afterRepeatIndex: Int, seconds: Int)
    /// Small text, not a square chip — a round/section boundary.
    case roundSeparator(label: String, sectionID: UUID, repeatIndex: Int)
    /// The strip's own final marker — "End of Section" when a different section type
    /// follows, "End of Workout" otherwise.
    case endMarker(label: String)

    var id: String {
        switch self {
        case .step(let step, let sectionID, let repeatIndex):
            return "step-\(sectionID)-\(repeatIndex)-\(step.id)"
        case .rest(let sectionID, let afterRepeatIndex, _):
            return "rest-\(sectionID)-\(afterRepeatIndex)"
        case .roundSeparator(_, let sectionID, let repeatIndex):
            return "separator-\(sectionID)-\(repeatIndex)"
        case .endMarker:
            return "end-marker"
        }
    }

    /// The section/pass a chip belongs to — nil for the two cases that don't belong
    /// to a specific step (round separators still carry one, since a tap on the
    /// strip only ever targets a `.step`, but `.endMarker` genuinely has neither).
    var sectionID: UUID? {
        switch self {
        case .step(_, let sectionID, _), .rest(let sectionID, _, _), .roundSeparator(_, let sectionID, _):
            return sectionID
        case .endMarker:
            return nil
        }
    }

    var repeatIndex: Int? {
        switch self {
        case .step(_, _, let repeatIndex), .rest(_, let repeatIndex, _), .roundSeparator(_, _, let repeatIndex):
            return repeatIndex
        case .endMarker:
            return nil
        }
    }
}

enum FollowAlongStripPlan {
    /// Builds the flattened list of everything from the current section+pass through
    /// the end of this consecutive run of Follow Along (`.time`) sections — every
    /// remaining repeat of the current section, then each subsequent section for as
    /// long as it's also `.time`, each with all of its own repeats. Stops at the
    /// first non-`.time` section or the end of the workout, closing with one final
    /// marker either way.
    ///
    /// `sections` is the whole workout's sequential section list (`Workout.sortedSections`)
    /// — this only ever reads forward from `startSectionIndex`, so a caller not
    /// currently on a `.time` section gets back an empty list.
    static func build(sections: [WorkoutSection], startSectionIndex: Int, startRepeatIndex: Int) -> [FollowAlongStripItem] {
        guard startSectionIndex >= 0, startSectionIndex < sections.count,
              sections[startSectionIndex].sectionType == .time
        else { return [] }

        var items: [FollowAlongStripItem] = []
        var sectionIndex = startSectionIndex

        while sectionIndex < sections.count, sections[sectionIndex].sectionType == .time {
            let section = sections[sectionIndex]
            let firstPass = sectionIndex == startSectionIndex ? startRepeatIndex : 0
            guard firstPass < section.effectiveRepeatCount else {
                sectionIndex += 1
                continue
            }
            for pass in firstPass..<section.effectiveRepeatCount {
                // Marks every round/section transition except the very first thing in
                // the whole strip — there's nothing to announce about where the
                // session already is.
                if !items.isEmpty {
                    let label = sectionRoundTitle(section, repeatIndex: pass, name: "Section: \(section.displayName)")
                    items.append(.roundSeparator(label: label, sectionID: section.id, repeatIndex: pass))
                }
                for step in section.runnableTimeSteps(pass: pass) {
                    items.append(.step(step, sectionID: section.id, repeatIndex: pass))
                }
                let rest = section.sectionRest(after: pass)
                if rest > 0 {
                    items.append(.rest(sectionID: section.id, afterRepeatIndex: pass, seconds: rest))
                }
            }
            sectionIndex += 1
        }

        let endLabel = sectionIndex < sections.count ? "End of Section" : "End of Workout"
        items.append(.endMarker(label: endLabel))
        return items
    }
}

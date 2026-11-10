import SwiftUI

// Shown only when PendingReviewStore has something to show — i.e. only after
// a crash/force-quit/restart left an install or uninstall operation
// unresolved. Presents the evidence ATLAS gathered and requires an explicit
// user action per item: Confirm (import to History / acknowledge the
// uninstall's completed moves) or Dismiss (discard the review without
// touching any file — the underlying journal is preserved, not deleted,
// via OperationJournal.dismiss()). Nothing here ever acts automatically.
struct OperationReviewView: View {
    @ObservedObject var reviewStore: PendingReviewStore
    let historyStore: HistoryStore
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if reviewStore.reviews.isEmpty {
                Spacer()
                Text("All reviewed.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(reviewStore.reviews, id: \.jobID) { review in
                            reviewCard(for: review)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 480, height: 420)
        .onChange(of: reviewStore.reviews.isEmpty) { isEmpty in
            if isEmpty { onDone() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Interrupted Operation Found")
                .font(.system(size: 15, weight: .bold))
            Text("ATLAS was interrupted during an install or uninstall. Review what it found before continuing — nothing has been added to your history or removed yet.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(16)
    }

    @ViewBuilder
    private func reviewCard(for review: PendingReview) -> some View {
        switch review {
        case .install(let r):
            installCard(r)
        case .uninstall(let r):
            uninstallCard(r)
        }
    }

    private func installCard(_ r: PendingInstallReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Possible interrupted install: \(URL(fileURLWithPath: r.targetIdentifier).lastPathComponent)")
                .font(.system(size: 12, weight: .semibold))
            Text("\(r.changedPaths.count) file(s) found that match what this installer would have placed. ATLAS cannot fully confirm they weren't changed by something else during the same window.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            pathList(r.changedPaths)
            actionRow(
                confirmLabel: "Add to History",
                onConfirm: { reviewStore.confirmInstall(r, store: historyStore) },
                onDismiss: { reviewStore.dismiss(.install(r)) }
            )
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func uninstallCard(_ r: PendingUninstallReview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Possible interrupted uninstall: \(r.targetIdentifier)")
                .font(.system(size: 12, weight: .semibold))
            if !r.confirmedMoved.isEmpty {
                Text("\(r.confirmedMoved.count) file(s) were confirmed moved to Trash before the interruption.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                pathList(r.confirmedMoved.map(\.originalPath))
            }
            if !r.unresolvedOriginalPaths.isEmpty {
                Text("\(r.unresolvedOriginalPaths.count) file(s) were recorded as moved, but ATLAS could not confirm their current location — their status is unknown.")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                pathList(r.unresolvedOriginalPaths)
            }
            actionRow(
                confirmLabel: "Acknowledge",
                onConfirm: {
                    // No separate "trash manifest" exists for an interrupted
                    // uninstall — acknowledging simply clears the review.
                    // The confirmed-moved files are already safely in Trash;
                    // this does not move, restore, or delete anything.
                    OperationJournal.shared.clear(jobID: r.jobID)
                    reviewStore.dismiss(.uninstall(r))
                },
                onDismiss: { reviewStore.dismiss(.uninstall(r)) }
            )
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func pathList(_ paths: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(paths.prefix(6), id: \.self) { path in
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            if paths.count > 6 {
                Text("+ \(paths.count - 6) more")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func actionRow(confirmLabel: String, onConfirm: @escaping () -> Void, onDismiss: @escaping () -> Void) -> some View {
        HStack {
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            Spacer()
            Button(confirmLabel, action: onConfirm)
                .buttonStyle(.borderedProminent)
        }
    }
}

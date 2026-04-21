import SwiftData
import SwiftUI

struct BoulderEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel
    @Query(sort: \Hold.holdID) private var holds: [Hold]

    let boulder: Boulder

    @State private var name = ""
    @State private var grade = ""
    @State private var setter = ""
    @State private var tags = ""
    @State private var notes = ""
    @State private var rating = 0

    @State private var selectedGroup: BoulderHoldGroup = .hold
    @State private var editingHoldDetails: Hold?

    var body: some View {
        List {
            Section("Boulder") {
                TextField("Name", text: $name)
                TextField("Grade", text: $grade)
                HStack {
                    Text("Rating")
                    Spacer()
                    starRatingPicker
                }
                LabeledContent("Setter", value: setter.isEmpty ? "-" : setter)
                TextField("Tags (comma-separated)", text: $tags)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)

                if canEditDraft {
                    LabeledContent("Status", value: boulder.status.displayName)
                }
            }
            .disabled(!canEditDraft)

            if canEditDraft {
                Section("Role") {
                    roleButtons
                    Text("Role-first mode: select a role, then click a hold to assign it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Wall") {
                wallPreview
                    .frame(maxWidth: .infinity)
                    .aspectRatio(WallSpec.widthCm / WallSpec.totalHeightCm, contentMode: .fit)
            }

            if canEditDraft {
                Section("Summary") {
                    LabeledContent("Start", value: listText(boulder.startHoldIDs))
                    LabeledContent("Holds", value: listText(boulder.holdIDs))
                    LabeledContent("Footholds", value: listText(boulder.footholdIDs))
                    LabeledContent("Top", value: listText(boulder.topHoldIDs))
                }
            }

            if canEditDraft {
                Section {
                    Button("Save Draft") {
                        saveDraft()
                    }

                    Button("Mark Established") {
                        establish()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if !canEditDraft {
                Section("Ascent") {
                    HStack {
                        LabeledContent("Attempts", value: "\(boulder.attemptCount)")
                        Spacer()
                        Button("Log Attempt") {
                            logAttempt()
                        }
                        .disabled(boulder.ascentLogged)
                    }

                    HStack {
                        LabeledContent("Ascent", value: boulder.ascentLogged ? "Logged" : "Not logged")
                        Spacer()
                        Button("Log Ascent") {
                            logAscent()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(boulder.ascentLogged)
                    }

                    if let loggedAt = boulder.ascentLoggedAt {
                        LabeledContent("Ascent Time", value: loggedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote)
                    }
                }
            }
        }
        .navigationTitle("Boulder")
        .task {
            load()
        }
        .sheet(item: $editingHoldDetails) { hold in
            HoldDetailView(hold: hold)
        }
    }

    private var wallPreview: some View {
        GeometryReader { geometry in
            ZStack {
                wallBackground(size: geometry.size)

                ForEach(holdsForWallPreview) { hold in
                    let role = boulder.role(for: hold.holdID)

                    BoulderWallHoldMarker(
                        holdID: hold.holdID,
                        role: role,
                        isDimmed: role == nil,
                        showHoldID: canEditDraft
                    )
                    .position(position(for: hold, size: geometry.size))
                    .onTapGesture {
                        handleRoleFirstTap(on: hold)
                    }
                    .onTapGesture(count: 2) {
                        removeFromDraftIfAllowed(holdID: hold.holdID)
                    }
                }
            }
        }
    }

    private var roleButtons: some View {
        HStack(spacing: 8) {
            ForEach(BoulderHoldGroup.allCases) { group in
                Button(group.displayName) {
                    selectedGroup = group
                }
                .buttonStyle(.borderedProminent)
                .tint(selectedGroup == group ? groupColor(for: group) : .gray.opacity(0.35))
            }
        }
    }

    private func handleRoleFirstTap(on hold: Hold) {
        guard canEditDraft else {
            appModel.globalMessage = "Established boulders are read-only. Edit a draft boulder."
            return
        }

        if let message = boulder.assign(hold.holdID, to: selectedGroup) {
            appModel.globalMessage = message
            return
        }

        persist(message: nil)
    }

    private func load() {
        name = boulder.name
        grade = boulder.grade
        rating = Boulder.clampedRating(boulder.rating)
        setter = resolvedSetter()
        tags = boulder.tags
        notes = boulder.notes
    }

    private func saveDraft() {
        updateModelFromForm()
        boulder.normalizeForDraft()
        boulder.status = .draft
        persist(message: "Boulder draft saved.")
    }

    private func establish() {
        updateModelFromForm()
        boulder.normalizeForDraft()

        let issues = boulder.validateForEstablish(existingHoldIDs: Set(holds.map(\.holdID)))
        guard issues.isEmpty else {
            appModel.globalMessage = "Cannot establish: \(issues.joined(separator: " "))"
            return
        }

        boulder.status = .established
        persist(message: "Boulder established.")
    }

    private func updateModelFromForm() {
        boulder.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        boulder.grade = grade.trimmingCharacters(in: .whitespacesAndNewlines)
        boulder.rating = Boulder.clampedRating(rating)
        boulder.setter = resolvedSetter()
        setter = boulder.setter
        boulder.tags = tags.trimmingCharacters(in: .whitespacesAndNewlines)
        boulder.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var starRatingPicker: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    rating = (rating == value) ? 0 : value
                } label: {
                    Image(systemName: value <= rating ? "star.fill" : "star")
                        .foregroundStyle(value <= rating ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func removeFromDraftIfAllowed(holdID: Int) {
        guard canEditDraft else {
            appModel.globalMessage = "Established boulders are read-only. Edit a draft boulder."
            return
        }

        boulder.remove(holdID)
        persist(message: nil)
    }

    private func logAttempt() {
        if let message = boulder.logAttempt() {
            appModel.globalMessage = message
            return
        }

        persist(message: "Attempt logged.")
    }

    private func logAscent() {
        if let message = boulder.logAscent() {
            appModel.globalMessage = message
            return
        }

        persist(message: "Ascent logged. Attempts are now locked.")
    }

    private func resolvedSetter() -> String {
        if let current = appModel.currentUser?.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
           !current.isEmpty {
            return current
        }

        return boulder.setter.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func groupColor(for group: BoulderHoldGroup) -> Color {
        switch group {
        case .start:
            return .green
        case .hold:
            return .blue
        case .foothold:
            return .yellow
        case .top:
            return .red
        }
    }

    private var canEditDraft: Bool {
        boulder.status == .draft
    }

    private func persist(message: String?) {
        do {
            try modelContext.save()
            if let message {
                appModel.globalMessage = message
            }
        } catch {
            appModel.globalMessage = "Could not save boulder: \(error.localizedDescription)"
        }
    }

    private func wallBackground(size: CGSize) -> some View {
        let kickboardHeight = size.height * (WallSpec.kickboardHeightCm / WallSpec.totalHeightCm)
        let mainWallHeight = max(0, size.height - kickboardHeight)
        let mainWallImageURL = existingURL(for: { try WallProjectPaths.defaultMainWallRectifiedURL() })
        let kickboardImageURL = existingURL(for: { try WallProjectPaths.defaultKickboardRectifiedURL() })

        return ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                wallSectionBackground(
                    imageURL: mainWallImageURL,
                    fallbackColor: Color.gray.opacity(0.2)
                )
                .frame(height: mainWallHeight)

                wallSectionBackground(
                    imageURL: kickboardImageURL,
                    fallbackColor: Color.brown.opacity(0.22)
                )
                .frame(height: kickboardHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1)
                .offset(y: -kickboardHeight)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func wallSectionBackground(imageURL: URL?, fallbackColor: Color) -> some View {
        if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(fallbackColor)
                default:
                    Rectangle().fill(fallbackColor)
                }
            }
        } else {
            Rectangle().fill(fallbackColor)
        }
    }

    private func existingURL(for resolver: () throws -> URL) -> URL? {
        guard let resolved = try? resolver(),
              FileManager.default.fileExists(atPath: resolved.path) else {
            return nil
        }
        return resolved
    }

    private func position(for hold: Hold, size: CGSize) -> CGPoint {
        let x = (hold.xCm / WallSpec.widthCm) * size.width
        let y = (1 - (hold.yCm / WallSpec.totalHeightCm)) * size.height
        return CGPoint(x: x, y: y)
    }

    private func listText(_ values: [Int]) -> String {
        values.isEmpty ? "-" : values.map(String.init).joined(separator: ", ")
    }

    private var holdsForWallPreview: [Hold] {
        if canEditDraft {
            return holds
        }

        return holds.filter { boulder.contains($0.holdID) }
    }
}

private struct BoulderWallHoldMarker: View {
    let holdID: Int
    let role: BoulderHoldGroup?
    let isDimmed: Bool
    let showHoldID: Bool

    var body: some View {
        ZStack(alignment: .top) {
            markerView
                .frame(width: 16, height: 16)

            if showHoldID {
                Text("\(holdID)")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.65))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .offset(y: -14)
            }
        }
        .opacity(isDimmed ? 0.45 : 1)
    }

    @ViewBuilder
    private var markerView: some View {
        switch role {
        case .start:
            RoundedRectangle(cornerRadius: 2)
                .fill(markerColor.opacity(0.22))
                .overlay {
                    RoundedRectangle(cornerRadius: 2).stroke(markerColor, lineWidth: 2)
                }
        case .hold:
            Circle()
                .fill(markerColor.opacity(0.22))
                .overlay {
                    Circle().stroke(markerColor, lineWidth: 2)
                }
        case .foothold:
            Diamond()
                .fill(markerColor.opacity(0.22))
                .overlay {
                    Diamond().stroke(markerColor, lineWidth: 2)
                }
        case .top:
            RoundedRectangle(cornerRadius: 2)
                .fill(markerColor.opacity(0.22))
                .overlay {
                    RoundedRectangle(cornerRadius: 2).stroke(markerColor, lineWidth: 2)
                }
        case .none:
            Circle()
                .fill(markerColor.opacity(0.22))
                .overlay {
                    Circle().stroke(markerColor, lineWidth: 2)
                }
        }
    }

    private var markerColor: Color {
        switch role {
        case .start:
            return .green
        case .hold:
            return .blue
        case .foothold:
            return .yellow
        case .top:
            return .red
        case .none:
            return .white
        }
    }
}

private struct Diamond: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: insetRect.midX, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.midY))
        path.addLine(to: CGPoint(x: insetRect.midX, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.minX, y: insetRect.midY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

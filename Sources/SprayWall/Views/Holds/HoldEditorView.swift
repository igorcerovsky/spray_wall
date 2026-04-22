import SwiftData
import SwiftUI

struct HoldEditorView: View {
    private static let adminEmail = "igor.cerovsky@gmail.com"
    private static let persistedEmailKey = "spraywall.last_logged_in_email"

    @Environment(\.modelContext) private var modelContext
    @Environment(AppModel.self) private var appModel

    @State private var showHoldList = false
    @State private var isEditingHolds = false
    @State private var inlineStatusMessage: String?
    @State private var holds: [Hold] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                controls

                wallPreview
                    .frame(maxWidth: .infinity)
                    .aspectRatio(WallSpec.widthCm / WallSpec.totalHeightCm, contentMode: .fit)

                DisclosureGroup("Holds (\(holds.count))", isExpanded: $showHoldList) {
                    ForEach(holds.prefix(20)) { hold in
                        HStack {
                            Text("#\(hold.holdID)")
                                .font(.headline.monospacedDigit())
                            Text("\(Int(hold.xCm)), \(Int(hold.yCm)) cm")
                                .font(.subheadline)
                            Spacer()
                            Text(hold.plane.rawValue.capitalized)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding()
            .navigationTitle("Hold Positions")
            .task {
                fetchHolds()
            }
        }
    }

    private var wallPreview: some View {
        GeometryReader { geometry in
            ZStack {
                wallBackground(size: geometry.size)

                ForEach(holds) { hold in
                    HoldPositionDotView(holdID: hold.holdID)
                        .position(position(for: hold, size: geometry.size))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard isEditingHolds else { return }
                                    move(hold: hold, to: value.location, size: geometry.size)
                                }
                                .onEnded { _ in
                                    guard isEditingHolds else { return }
                                    persistMove(holdID: hold.holdID, xCm: hold.xCm, yCm: hold.yCm)
                                }
                        )
                        .contextMenu {
                            if isEditingHolds {
                                Button("Delete Hold", role: .destructive) {
                                    delete(hold: hold)
                                }
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        handleCanvasTap(at: value.location, size: geometry.size)
                    }
            )
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Button(isEditingHolds ? "Done" : "Edit") {
                    if canEditWallLayout {
                        isEditingHolds.toggle()
                        inlineStatusMessage = nil
                    } else {
                        appModel.globalMessage = "Wall layout can be edited only by admin."
                        inlineStatusMessage = "Only admin can edit wall layout. Signed in as: \(effectiveUserEmail ?? "unknown")"
                    }
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }

            Text("Positioning mode: only hold ID and coordinates are edited here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(isEditingHolds
                 ? "Edit mode: tap wall to add, drag to move, right-click to delete."
                 : "Locked mode: wall is read-only. Press Edit to modify hold positions.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !canEditWallLayout {
                Text("Wall layout is shared across all users. Only admin can edit it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Current user: \(appModel.currentUser?.email ?? "not logged in")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let inlineStatusMessage, !inlineStatusMessage.isEmpty {
                Text(inlineStatusMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    private func addHold(at location: CGPoint, size: CGSize) {
        guard canEditWallLayout else {
            appModel.globalMessage = "Wall layout can be edited only by admin."
            inlineStatusMessage = "Only admin can edit wall layout. Signed in as: \(effectiveUserEmail ?? "unknown")"
            return
        }

        let writeContext = ModelContext(modelContext.container)
        let existing = (try? writeContext.fetch(FetchDescriptor<Hold>(sortBy: [SortDescriptor(\.holdID)]))) ?? []
        let holdID = (existing.map(\.holdID).max() ?? 0) + 1
        let xCm = max(0, min(WallSpec.widthCm, (location.x / size.width) * WallSpec.widthCm))
        let yCm = max(0, min(WallSpec.totalHeightCm, (1 - (location.y / size.height)) * WallSpec.totalHeightCm))
        let plane: HoldPlane = yCm <= WallSpec.kickboardHeightCm ? .kickboard : .main

        let hold = Hold(
            holdID: holdID,
            xCm: xCm,
            yCm: yCm,
            plane: plane,
            role: .hand
        )
        writeContext.insert(hold)
        if persist(context: writeContext) {
            let afterCount = fetchHoldsAndReturnCount()
            let insertedPresent = isHoldPersisted(holdID: holdID)

            if insertedPresent {
                inlineStatusMessage = "Added hold #\(holdID) at (\(Int(xCm)), \(Int(yCm))) cm. Total holds: \(afterCount)."
            } else {
                inlineStatusMessage = "Insert attempted for hold #\(holdID), but DB verification failed."
                appModel.globalMessage = "Insert verification failed."
            }
        }
    }

    private func move(hold: Hold, to location: CGPoint, size: CGSize) {
        guard canEditWallLayout else {
            return
        }

        hold.xCm = max(0, min(WallSpec.widthCm, (location.x / size.width) * WallSpec.widthCm))
        hold.yCm = max(0, min(WallSpec.totalHeightCm, (1 - (location.y / size.height)) * WallSpec.totalHeightCm))
        hold.plane = hold.yCm <= WallSpec.kickboardHeightCm ? .kickboard : .main
        inlineStatusMessage = nil
    }

    private func persistMove(holdID: Int, xCm: Double, yCm: Double) {
        let writeContext = ModelContext(modelContext.container)
        let id = holdID
        let descriptor = FetchDescriptor<Hold>(
            predicate: #Predicate<Hold> { item in
                item.holdID == id
            }
        )

        guard let target = try? writeContext.fetch(descriptor).first else {
            inlineStatusMessage = "Move failed: hold #\(holdID) not found in DB."
            return
        }

        target.xCm = max(0, min(WallSpec.widthCm, xCm))
        target.yCm = max(0, min(WallSpec.totalHeightCm, yCm))
        target.plane = target.yCm <= WallSpec.kickboardHeightCm ? .kickboard : .main

        if persist(context: writeContext) {
            _ = fetchHoldsAndReturnCount()
        }
    }

    private func delete(hold: Hold) {
        guard canEditWallLayout else {
            appModel.globalMessage = "Wall layout can be edited only by admin."
            inlineStatusMessage = "Only admin can edit wall layout. Signed in as: \(effectiveUserEmail ?? "unknown")"
            return
        }

        let writeContext = ModelContext(modelContext.container)
        let id = hold.holdID
        let descriptor = FetchDescriptor<Hold>(
            predicate: #Predicate<Hold> { item in
                item.holdID == id
            }
        )
        if let target = try? writeContext.fetch(descriptor).first {
            writeContext.delete(target)
        }

        if persist(context: writeContext) {
            _ = fetchHoldsAndReturnCount()
            inlineStatusMessage = "Hold deleted. Total holds: \(holds.count)."
        }
    }

    @discardableResult
    private func persist(context: ModelContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            appModel.globalMessage = "Save failed: \(error.localizedDescription)"
            inlineStatusMessage = "Save failed: \(error.localizedDescription)"
            return false
        }
    }

    private func fetchHolds() {
        _ = fetchHoldsAndReturnCount()
    }

    @discardableResult
    private func fetchHoldsAndReturnCount() -> Int {
        do {
            let readContext = ModelContext(modelContext.container)
            let descriptor = FetchDescriptor<Hold>(sortBy: [SortDescriptor(\.holdID)])
            holds = try readContext.fetch(descriptor)
            return holds.count
        } catch {
            holds = []
            appModel.globalMessage = "Could not load holds: \(error.localizedDescription)"
            inlineStatusMessage = "Could not load holds: \(error.localizedDescription)"
            return 0
        }
    }

    private func isHoldPersisted(holdID: Int) -> Bool {
        do {
            let readContext = ModelContext(modelContext.container)
            let id = holdID
            let descriptor = FetchDescriptor<Hold>(
                predicate: #Predicate<Hold> { hold in
                    hold.holdID == id
                }
            )
            return try readContext.fetch(descriptor).isEmpty == false
        } catch {
            return false
        }
    }

    private func position(for hold: Hold, size: CGSize) -> CGPoint {
        let x = (hold.xCm / WallSpec.widthCm) * size.width
        let y = (1 - (hold.yCm / WallSpec.totalHeightCm)) * size.height
        return CGPoint(x: x, y: y)
    }

    private func handleCanvasTap(at location: CGPoint, size: CGSize) {
        inlineStatusMessage = "Wall click detected at (\(Int(location.x)), \(Int(location.y))) px."

        guard canEditWallLayout else {
            appModel.globalMessage = "Wall layout can be edited only by admin (\(Self.adminEmail)). Current user: \(effectiveUserEmail ?? "unknown")."
            inlineStatusMessage = "Only admin can edit wall layout. Signed in as: \(effectiveUserEmail ?? "unknown")"
            return
        }

        guard isEditingHolds else {
            appModel.globalMessage = "Holds are locked. Press Edit to add or move holds."
            inlineStatusMessage = "Holds are locked. Press Edit first."
            return
        }

        addHold(at: location, size: size)
    }

    private var canEditWallLayout: Bool {
        effectiveUserEmail == Self.adminEmail
    }

    private var effectiveUserEmail: String? {
        if let runtimeEmail = appModel.currentUser?.email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           !runtimeEmail.isEmpty {
            return runtimeEmail
        }

        let persistedEmail = UserDefaults.standard.string(forKey: Self.persistedEmailKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if let persistedEmail, !persistedEmail.isEmpty {
            return persistedEmail
        }

        return nil
    }
}

private struct HoldPositionDotView: View {
    let holdID: Int

    var body: some View {
        ZStack(alignment: .top) {
            Circle()
                .fill(Color.purple.opacity(0.22))
                .frame(width: 10, height: 10)
                .overlay {
                    Circle().stroke(Color.purple, lineWidth: 1)
                }

            Text("\(holdID)")
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.65))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .offset(y: -12)
        }
    }
}

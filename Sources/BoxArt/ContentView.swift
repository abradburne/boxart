import SwiftUI
import AppKit
import BoxArtCore

struct ContentView: View {
    @ObservedObject var model: LibraryModel
    @AppStorage("gridView") private var gridView = true
    @AppStorage("showInspector") private var showInspector = false

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                header
                Divider()
                HStack(spacing: 0) {
                    LibraryView(model: model, gridView: gridView, showInspector: $showInspector)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if showInspector { Divider(); InspectorView(model: model).frame(width: 280) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                statusBar
            }.background(Color(nsColor: .textBackgroundColor))
        }
        .searchable(text: $model.query, prompt: "Search games")
        .toolbar {
            ToolbarItemGroup {
                Picker("View", selection: $gridView) {
                    Image(systemName: "square.grid.2x2").tag(true)
                    Image(systemName: "list.bullet").tag(false)
                }.pickerStyle(.segmented).frame(width: 80)
                Button { showInspector.toggle() } label: { Image(systemName: "sidebar.right") }.help("Show artwork details")
                Button { model.showSettings = true } label: { Image(systemName: "gearshape") }.help("Artwork settings")
            }
        }
        .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
        .onChange(of: model.profile) { _, _ in model.refreshExisting() }
        .onChange(of: model.kind) { _, _ in model.kindChanged() }
        .onChange(of: model.jpeg) { _, _ in model.refreshExisting() }
        .onChange(of: model.query) { _, _ in model.pruneSelection() }
        .onChange(of: model.filter) { _, _ in model.pruneSelection() }
        .onChange(of: model.systems) { _, _ in model.pruneSelection() }
        .alert("BoxArt", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .task { model.scan() }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").font(.title2).foregroundStyle(.teal)
                Text("BoxArt").font(.title2.bold())
            }.padding(20)
            List {
                Section("Library") {
                    Button { model.choose(nil) } label: {
                        sidebarRow("All games", icon: "square.grid.2x2", saved: model.saved, total: model.games.count)
                    }.listRowBackground(model.systems.isEmpty ? Color.teal.opacity(0.12) : .clear)
                }
                Section {
                    ForEach(model.systemCounts, id: \.system) { entry in
                        Button { model.choose(entry.system, adding: NSEvent.modifierFlags.contains(.command)) } label: {
                            sidebarRow(entry.system.name, icon: "gamecontroller", saved: entry.saved, total: entry.total)
                        }
                        .listRowBackground(model.systems.contains(entry.system) ? Color.teal.opacity(0.12) : .clear)
                        .accessibilityAddTraits(model.systems.contains(entry.system) ? .isSelected : [])
                        .contextMenu {
                            Button("Get Artwork for \(entry.system.name)") { model.getArtwork(for: entry.system) }
                                .disabled(model.busy || entry.saved == entry.total)
                            Button(model.systems.contains(entry.system) ? "Remove from View" : "Add to View") { model.choose(entry.system, adding: true) }
                        }
                    }
                } header: {
                    Text("Consoles")
                } footer: {
                    if model.systemCounts.count > 1 {
                        Text("Command-click to show several consoles.").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }.listStyle(.sidebar).buttonStyle(.plain)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("ROM library", systemImage: "sdcard").font(.callout.weight(.medium))
                Text(model.folder).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                Button("Choose folder…") { model.chooseFolder() }.disabled(model.busy)
            }.padding(18)
        }
    }

    private func sidebarRow(_ title: String, icon: String, saved: Int, total: Int) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 20)
            Text(title).lineLimit(1)
            Spacer()
            if saved == total, total > 0 { Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(.green) }
            Text("\(saved)/\(total)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(saved) of \(total) games have artwork")
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.heading).font(.largeTitle.bold()).lineLimit(1)
                    Text(subtitle).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Picker("Artwork type", selection: $model.kind) { ForEach(ArtKind.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().fixedSize().disabled(model.busy).help(model.kind.detail)
                Button { model.scan() } label: { Image(systemName: "arrow.clockwise") }.help("Rescan library").disabled(model.busy)
                actionButton
            }
            HStack(spacing: 6) {
                ForEach(StatusFilter.allCases) { statusChip($0) }
                Spacer()
                if !model.selectedIDs.isEmpty {
                    Button("Clear selection") { model.clearSelection() }.buttonStyle(.link)
                }
            }
            if model.filter == .unsaved {
                HStack(spacing: 10) {
                    Image(systemName: "tray.and.arrow.down").foregroundStyle(.teal)
                    Text("Previews held in memory. They are lost when the app closes unless saved.")
                        .font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save these covers") { model.save(ids: Set(model.visible.map(\.id))) }
                        .disabled(model.busy || model.visible.isEmpty)
                }
            }
        }.padding(24)
    }

    private var subtitle: String {
        var parts = ["\(model.visible.count) \(model.visible.count == 1 ? "game" : "games")"]
        if model.systems.count > 1 { parts.append(model.systems.map(\.name).sorted().joined(separator: ", ")) }
        parts.append(model.kind.rawValue)
        parts.append(model.profile.rawValue)
        return parts.joined(separator: " · ")
    }

    /// One button that acts on the narrowest thing in view, with the wider and gentler choices in the menu beside it.
    private var actionButton: some View {
        HStack(spacing: 4) {
            Button(model.title(for: model.defaultScope)) { model.run(model.defaultScope) }
                .buttonStyle(.borderedProminent).tint(.teal)
                .help("Finds missing artwork and saves each cover as soon as it is found. Games that already have artwork are left alone.")
            Menu {
                if !model.selectedIDs.isEmpty { Button(model.title(for: .selection)) { model.run(.selection) } }
                if model.isNarrowed { Button(model.title(for: .shown)) { model.run(.shown) } }
                Button(model.title(for: .library)) { model.run(.library) }
                Divider()
                Button("Preview without saving") { model.run(model.defaultScope, save: false) }
                Button("Save \(model.ready) unsaved \(model.ready == 1 ? "preview" : "previews")") { model.save() }.disabled(model.ready == 0)
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.button).menuIndicator(.hidden).fixedSize()
            .help("Choose what to get artwork for")
            .accessibilityLabel("More artwork actions")
        }
        .disabled(model.busy || model.games.isEmpty)
    }

    private func statusChip(_ item: StatusFilter) -> some View {
        let selected = model.filter == item
        let count = model.filterCount(item)
        return Button { model.filter = item } label: {
            HStack(spacing: 7) {
                Image(systemName: item.icon).font(.system(size: 12, weight: .medium))
                Text(item.rawValue).font(.system(size: 13, weight: selected ? .semibold : .medium))
                Text(count.formatted()).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(selected ? Color.teal.opacity(0.16) : Color.primary.opacity(0.06), in: Capsule())
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(selected ? Color.teal.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.teal.opacity(0.45) : Color.clear))
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.rawValue), \(count) games")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .help(item == .unsaved ? "Downloaded or imported covers that have not been saved" : "Show \(item.rawValue.lowercased()) games in the current consoles and search")
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            if model.busy { ProgressView(value: model.progress).frame(width: 110) }
            Text(model.message).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            Spacer()
            if model.busy { Button("Stop") { model.stop() } }
            if !model.selectedIDs.isEmpty { Text("\(model.selectedIDs.count) selected").font(.caption.monospacedDigit()).foregroundStyle(.teal) }
            Text("\(model.saved) / \(model.games.count) saved").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }.padding(14)
    }
}

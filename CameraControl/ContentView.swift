import SwiftUI

struct ContentView: View {
    @EnvironmentObject var studio: Studio
    @Environment(\.openWindow) private var openWindow
    @State private var tab = SidebarTab.look

    enum SidebarTab: String, CaseIterable, Identifiable {
        case look = "Look", background = "Scene", fun = "Fun", news = "News", text = "Text"
        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                preview
                controlBar
                reactionBar
                Spacer(minLength: 0)
            }
            .padding(18)
            .frame(maxWidth: .infinity)

            Divider()

            VStack(spacing: 0) {
                Picker("", selection: $tab) {
                    ForEach(SidebarTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch tab {
                        case .look: LookPanel()
                        case .background: BackgroundPanel()
                        case .fun: FunPanel()
                        case .news: NewsPanel()
                        case .text: TextPanel()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: 350)
            .background(.background.secondary)
        }
        .toolbar {
            ToolbarItem {
                Picker("Camera", selection: $studio.selectedDeviceID) {
                    ForEach(studio.devices, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }
                .frame(minWidth: 200)
            }
            ToolbarItem {
                Button { openWindow(id: "output") } label: {
                    Label("Output Window", systemImage: "rectangle.on.rectangle")
                }
                .help("Open a clean output window to share or capture")
            }
        }
        .task { await studio.start() }
    }

    private var preview: some View {
        VideoView(frames: studio.frames)
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                if studio.cameraDenied {
                    VStack(spacing: 8) {
                        Image(systemName: "video.slash").font(.largeTitle)
                        Text("Camera access is off").font(.headline)
                        Text("Turn it on in System Settings → Privacy & Security → Camera.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 6) {
                    if studio.settings.freeze { badge("FROZEN", .blue) }
                    if studio.settings.blank { badge("BE RIGHT BACK", .orange) }
                    badge("\(studio.fps) fps · \(studio.latencyMs) ms", .black.opacity(0.5))
                        .help("Frame rate, and time from camera capture to finished frame")
                }
                .padding(10)
            }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.bold).monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color, in: Capsule())
            .foregroundStyle(.white)
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            BigToggle(title: "Freeze", icon: "snowflake", isOn: $studio.settings.freeze, tint: .blue)
                .keyboardShortcut("f", modifiers: .command)
                .help("Hold the current frame (⌘F)")
            BigToggle(title: "Be Right Back", icon: "pause.circle.fill", isOn: $studio.settings.blank, tint: .orange)
                .keyboardShortcut("b", modifiers: .command)
                .help("Swap your video for a 'be right back' card (⌘B)")
            BigToggle(title: "News Mode", icon: "tv", isOn: $studio.settings.newsEnabled, tint: .red)
                .keyboardShortcut("l", modifiers: .command)
                .help("Lower third, ticker and LIVE bug (⌘L)")
            BigToggle(title: "Caption", icon: "captions.bubble", isOn: $studio.settings.captionEnabled, tint: .purple)
                .keyboardShortcut("t", modifiers: .command)
                .help("Show your caption text (⌘T)")
        }
    }

    private var reactionBar: some View {
        HStack(spacing: 8) {
            Text("React").font(.callout.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(Reaction.allCases.enumerated()), id: \.element) { index, r in
                Button { studio.react(r) } label: {
                    Text(r.emojis[0]).font(.system(size: 26))
                        .frame(width: 46, height: 40)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                .help("⌘\(index + 1)")
            }
        }
    }
}

struct BigToggle: View {
    let title: String
    let icon: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title2)
                Text(title).font(.callout.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(isOn ? .white : .primary)
            .background(isOn ? tint : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sidebar panels

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.headline).padding(.top, 4)
    }
}

private struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Slider(value: $value, in: range)
        }
    }
}

/// A grid of selectable tiles; used for filters, stickers and scenes.
private struct TileGrid<Item: Identifiable & Hashable, Tile: View>: View {
    let items: [Item]
    @Binding var selection: Item
    var columns = 3
    @ViewBuilder let tile: (Item) -> Tile

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(items) { item in
                Button { selection = item } label: {
                    tile(item)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(item == selection ? Color.accentColor : .clear, lineWidth: 2.5))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LookPanel: View {
    @EnvironmentObject var studio: Studio

    var body: some View {
        SectionTitle("Filter")
        TileGrid(items: FilterKind.allCases, selection: $studio.settings.filter) { f in
            Text(f.label).font(.callout.weight(.medium))
        }
        if studio.settings.filter != .none {
            LabeledSlider(label: "Strength", value: $studio.settings.filterIntensity, range: 0...1)
        }
        if studio.settings.filter.isDistortion {
            Text("Distortions follow your face.").font(.caption).foregroundStyle(.secondary)
        }

        SectionTitle("Camera")
        Toggle("Mirror", isOn: $studio.settings.mirror)
        LabeledSlider(label: "Zoom", value: $studio.settings.zoom, range: 1...3)
        LabeledSlider(label: "Brightness", value: $studio.settings.brightness, range: -0.4...0.4)
        LabeledSlider(label: "Contrast", value: $studio.settings.contrast, range: 0.5...1.8)
        LabeledSlider(label: "Saturation", value: $studio.settings.saturation, range: 0...2)
        Button("Reset look") {
            let d = EffectSettings()
            studio.settings.filter = d.filter
            studio.settings.zoom = d.zoom
            studio.settings.brightness = d.brightness
            studio.settings.contrast = d.contrast
            studio.settings.saturation = d.saturation
        }
    }
}

private struct BackgroundPanel: View {
    @EnvironmentObject var studio: Studio

    var body: some View {
        SectionTitle("Background")
        Picker("", selection: $studio.settings.backgroundMode) {
            ForEach(BackgroundMode.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        switch studio.settings.backgroundMode {
        case .none:
            Text("Your real background is shown. Pick Blur, a Scene, a Color or your own Image to replace it.")
                .font(.callout).foregroundStyle(.secondary)
        case .blur:
            LabeledSlider(label: "Blur amount", value: $studio.settings.blurRadius, range: 4...60)
        case .preset:
            TileGrid(items: BackgroundPreset.allCases, selection: $studio.settings.backgroundPreset, columns: 2) { p in
                VStack(spacing: 4) {
                    Image(nsImage: studio.thumbnail(p))
                        .resizable().aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text(p.label).font(.caption.weight(.medium))
                }
                .padding(6)
            }
        case .color:
            ColorPicker("Color", selection: studio.backgroundColor, supportsOpacity: false)
        case .custom:
            Button("Choose Image…") { studio.chooseBackgroundImage() }
            Text(studio.customBackgroundName ?? "No image picked yet.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct FunPanel: View {
    @EnvironmentObject var studio: Studio

    var body: some View {
        SectionTitle("Face stickers")
        Text("Stickers track your face.").font(.caption).foregroundStyle(.secondary)
        TileGrid(items: Sticker.allCases, selection: $studio.settings.sticker, columns: 5) { s in
            Text(s == .none ? "⊘" : s.emoji).font(.system(size: 26))
        }

        SectionTitle("Reactions")
        Text("Tap to fire one off (⌘1 – ⌘7).").font(.caption).foregroundStyle(.secondary)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4)) {
            ForEach(Reaction.allCases) { r in
                Button { studio.react(r) } label: {
                    Text(r.emojis[0]).font(.system(size: 30)).frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

private struct NewsPanel: View {
    @EnvironmentObject var studio: Studio
    private let tags = ["BREAKING NEWS", "LIVE REPORT", "EXCLUSIVE", "WEATHER", "SPORTS", "DEVELOPING STORY", ""]

    var body: some View {
        Toggle("News mode", isOn: $studio.settings.newsEnabled).toggleStyle(.switch)

        SectionTitle("Lower third")
        HStack {
            TextField("Tag", text: $studio.settings.newsTag)
            Menu("") {
                ForEach(tags, id: \.self) { t in
                    Button(t.isEmpty ? "No tag" : t) { studio.settings.newsTag = t }
                }
            }
            .fixedSize()
        }
        TextField("Name", text: $studio.settings.newsName)
        TextField("Title", text: $studio.settings.newsTitle)

        SectionTitle("Ticker")
        Toggle("Scrolling ticker", isOn: $studio.settings.tickerEnabled)
        TextEditor(text: $studio.settings.tickerText)
            .font(.callout)
            .frame(height: 90)
            .scrollContentBackground(.hidden)
            .padding(4)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

        SectionTitle("Channel")
        Toggle("LIVE bug with clock", isOn: $studio.settings.showLiveBug)
        TextField("Channel name", text: $studio.settings.channelName)

        Text("Tip: pair with the News Studio scene in the Scene tab.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

private struct TextPanel: View {
    @EnvironmentObject var studio: Studio

    var body: some View {
        SectionTitle("Caption")
        Toggle("Show caption", isOn: $studio.settings.captionEnabled).toggleStyle(.switch)
        TextField("Caption", text: $studio.settings.captionText)
        Picker("Position", selection: $studio.settings.captionPosition) {
            Text("Top").tag(CaptionPosition.top)
            Text("Bottom").tag(CaptionPosition.bottom)
        }
        .pickerStyle(.segmented)

        SectionTitle("Be right back card")
        TextField("Title", text: $studio.settings.blankTitle)
        TextField("Subtitle", text: $studio.settings.blankSubtitle)
        Toggle("Show it now", isOn: $studio.settings.blank)
    }
}

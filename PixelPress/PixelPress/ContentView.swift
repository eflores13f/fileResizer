//
//  ContentView.swift
//  PixelPress
//
//  Created by eflo on 3/5/26.
//
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var items: [ImageItem] = []

    @State private var selectedPreset: ExportPreset = .web
    @State private var maxDimension: Double = 2048
    @State private var jpegQuality: Double = 0.82
    @State private var outputFormat: OutputFormat = .jpeg

    @State private var useTargetCompression: Bool = false
    @State private var targetSizeKB: Int = 500

    @State private var outputMode: OutputMode = .sameFolder
    @State private var outputFolderURL: URL?

    @State private var renameMode: RenameMode = .suffixDimension
    @State private var customPrefix: String = "PixelPress"

    @State private var isDraggingDropZone = false
    @State private var isProcessing = false
    @State private var progress: Double = 0
    @State private var processedCount = 0
    @State private var totalCount = 0

    @State private var showImporter = false
    @State private var showLog = false
    @State private var showSettingsSheet = false

    @State private var logMessages: [String] = [
        "Welcome to PixelPress.",
        "Drop images or folders to begin."
    ]

    @State private var exportSummary: ExportSummary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headerSection
                heroSection

                if !items.isEmpty {
                    librarySection
                }

                presetSection
                statusOverviewSection
                actionSection

                if let exportSummary {
                    exportSummarySection(exportSummary)
                }

                detailsSection
                footerSection
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image, .folder],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importURLs(urls)
            case .failure(let error):
                appendLog("❌ File import failed: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $showSettingsSheet) {
            settingsSheet
        }
    }
}

// MARK: - UI
private extension ContentView {
    var headerSection: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(.ultraThinMaterial)
                    .frame(width: 58, height: 58)

                Image(systemName: "photo.stack.fill")
                    .font(.system(size: 26, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("PixelPress")
                    .font(.system(size: 30, weight: .bold))

                Text("Premium batch image resizing and compression for macOS")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    showSettingsSheet = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)

                Button {
                    showImporter = true
                } label: {
                    Label("Add Images", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    var heroSection: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(
                            isDraggingDropZone ? Color.accentColor : Color.secondary.opacity(0.35),
                            style: StrokeStyle(lineWidth: 2, dash: [10])
                        )
                )

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 80, height: 80)

                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 31, weight: .semibold))
                        .foregroundColor(isDraggingDropZone ? .accentColor : .primary)
                }

                Text("Drag & Drop Images or Folders")
                    .font(.title2.weight(.bold))

                Text("JPG • PNG • HEIC • TIFF • BMP")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Select Images", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Clear All") {
                        clearAll()
                    }
                    .buttonStyle(.bordered)
                    .disabled(items.isEmpty)

                    Button("Settings") {
                        showSettingsSheet = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 4)
            }
            .padding(24)
        }
        .frame(height: 220)
        .onDrop(of: [.fileURL], isTargeted: $isDraggingDropZone) { providers in
            handleDrop(providers: providers)
        }
    }

    var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Selected Images")
                    .font(.headline)

                Spacer()

                Text("\(items.count) ready")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(spacing: 14) {
                    ForEach(items) { item in
                        thumbnailCard(item)
                            .onDrag {
                                NSItemProvider(object: item.id.uuidString as NSString)
                            }
                            .onDrop(of: [.text], delegate: ThumbnailDropDelegate(item: item, items: $items))
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    func thumbnailCard(_ item: ImageItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(nsImage: item.previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 116)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .trailing, spacing: 6) {
                    Button {
                        removeItem(item)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.7))
                    }
                    .buttonStyle(.plain)

                    if let result = item.lastExportResult {
                        exportBadge(for: result)
                    }
                }
                .padding(8)
            }

            Text(item.url.lastPathComponent)
                .font(.caption.weight(.medium))
                .lineLimit(1)

            HStack {
                Text(formatBytes(item.originalBytes))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(item.estimatedOutputText(
                    format: outputFormat,
                    quality: jpegQuality,
                    maxDimension: maxDimension,
                    useTargetCompression: useTargetCompression,
                    targetKB: targetSizeKB
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(width: 150)
    }

    func exportBadge(for result: ItemExportResult) -> some View {
        HStack(spacing: 4) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(result.badgeText)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(result.success ? Color.green.opacity(0.16) : Color.red.opacity(0.16))
        )
        .foregroundStyle(result.success ? Color.green : Color.red)
    }

    var presetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presets")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(ExportPreset.allCases) { preset in
                    presetCard(preset)
                }
            }
        }
    }

    func presetCard(_ preset: ExportPreset) -> some View {
        let selected = selectedPreset == preset

        return Button {
            applyPreset(preset)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(preset.title)
                        .font(.headline)

                    Spacer()

                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Text(preset.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)

                Spacer()

                Text(preset.summaryLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(selected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(selected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    var statusOverviewSection: some View {
        HStack(spacing: 12) {
            statCard(title: "Original Total", value: totalOriginalBytes > 0 ? formatBytes(totalOriginalBytes) : "—")
            statCard(title: "Estimated Export", value: estimatedBatchOutputText)
            statCard(title: "Save Location", value: outputMode == .sameFolder ? "Same Folder" : "Custom Folder")
            statCard(title: "Rename Pattern", value: renameMode.shortTitle)
        }
    }

    func statCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    var actionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(actionStatusTitle)
                        .font(.headline)

                    Text(actionStatusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Button("Open Output") {
                        openOutputLocation()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canOpenOutput)

                    Button {
                        processBatch()
                    } label: {
                        Label(isProcessing ? "Processing..." : "Export Images", systemImage: "arrow.down.circle.fill")
                            .frame(minWidth: 180)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(items.isEmpty || isProcessing || (outputMode == .customFolder && outputFolderURL == nil))
                }
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            HStack {
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    func exportSummarySection(_ summary: ExportSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Complete")
                        .font(.headline)

                    Text("\(summary.processedCount) image(s) processed successfully")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Reveal in Finder") {
                    revealLastExportedFiles(summary)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                metricCard(title: "Original", value: formatBytes(summary.totalOriginalBytes))
                metricCard(title: "Exported", value: formatBytes(summary.totalExportedBytes))
                metricCard(title: "Saved", value: formatBytes(summary.savedBytes))
                metricCard(title: "Reduction", value: "\(summary.percentSaved)%")
            }

            if !summary.items.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Latest Results")
                        .font(.subheadline.weight(.semibold))

                    ForEach(summary.items.prefix(8)) { item in
                        HStack {
                            Text(item.fileName)
                                .lineLimit(1)

                            Spacer()

                            Text("\(formatBytes(item.originalBytes)) → \(formatBytes(item.exportedBytes))")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.green.opacity(0.20), lineWidth: 1)
        )
    }

    var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showLog.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: showLog ? "chevron.down" : "chevron.right")
                    Text("Activity Log")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .font(.headline)

            if showLog {
                ScrollView {
                    Text(logMessages.joined(separator: "\n"))
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(minHeight: 130, maxHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
            }
        }
    }

    var footerSection: some View {
        HStack {
            Spacer()
            Text("PixelPress • by Cipher Cat Labs")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    func metricCard(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
        )
    }

    var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox("Resize") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Max Dimension")
                                Spacer()
                                Text("\(Int(maxDimension)) px")
                                    .foregroundStyle(.secondary)
                            }

                            Slider(value: $maxDimension, in: 256...5000, step: 64)

                            Text(dimensionDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("Format") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Output Format", selection: $outputFormat) {
                                ForEach(OutputFormat.allCases) { format in
                                    Text(format.displayName).tag(format)
                                }
                            }
                            .pickerStyle(.segmented)

                            Text(outputFormat.descriptionText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("Compression") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Quality")
                                Spacer()
                                Text(String(format: "%.2f", jpegQuality))
                                    .foregroundStyle(.secondary)
                            }

                            Slider(value: $jpegQuality, in: 0.10...1.00, step: 0.01)

                            Text(qualityDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Toggle("Compress under target size", isOn: $useTargetCompression)

                            HStack {
                                Text("Target")
                                Spacer()
                                Stepper(value: $targetSizeKB, in: 50...10000, step: 50) {
                                    Text("\(targetSizeKB) KB")
                                }
                                .disabled(!useTargetCompression || outputFormat != .jpeg)
                            }

                            if outputFormat == .png && useTargetCompression {
                                Text("Target-size compression is available for JPEG only in this version.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("Output") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Save Location", selection: $outputMode) {
                                Text("Same folder").tag(OutputMode.sameFolder)
                                Text("Choose folder").tag(OutputMode.customFolder)
                            }
                            .pickerStyle(.radioGroup)

                            if outputMode == .customFolder {
                                HStack {
                                    Text(outputFolderURL?.path ?? "No folder selected")
                                        .font(.caption)
                                        .foregroundStyle(outputFolderURL == nil ? .secondary : .primary)
                                        .lineLimit(1)

                                    Spacer()
                                }

                                HStack {
                                    Button("Choose Folder") {
                                        chooseOutputFolder()
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Open Output") {
                                        openOutputLocation()
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(!canOpenOutput)
                                }
                            } else {
                                Text("Exports save beside each original file.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("File Naming") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Rename Pattern", selection: $renameMode) {
                                ForEach(RenameMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.radioGroup)

                            if renameMode == .customPrefix {
                                TextField("Prefix", text: $customPrefix)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Text(renamePreviewText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }

                    GroupBox("Quick Tips") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Drag thumbnails left or right to reorder.", systemImage: "arrow.left.and.right")
                            Label("JPEG is best for smaller files.", systemImage: "photo")
                            Label("PNG is best for graphics and transparency.", systemImage: "sparkles")
                            Label("Use Email preset for lightweight sharing.", systemImage: "envelope")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    }
                }
                .padding(20)
            }
            .navigationTitle("PixelPress Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSettingsSheet = false
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 700)
    }
}

// MARK: - Computed
private extension ContentView {
    var totalOriginalBytes: Int64 {
        items.reduce(0) { $0 + $1.originalBytes }
    }

    var estimatedBatchOutputBytes: Int64 {
        items.reduce(0) {
            $0 + $1.estimatedOutputBytes(
                format: outputFormat,
                quality: jpegQuality,
                maxDimension: maxDimension,
                useTargetCompression: useTargetCompression,
                targetKB: targetSizeKB
            )
        }
    }

    var estimatedBatchOutputText: String {
        items.isEmpty ? "—" : formatBytes(estimatedBatchOutputBytes)
    }

    var canOpenOutput: Bool {
        switch outputMode {
        case .sameFolder:
            return items.first != nil
        case .customFolder:
            return outputFolderURL != nil
        }
    }

    var dimensionDescription: String {
        switch Int(maxDimension) {
        case 0..<800:
            return "Small export, best for quick shares and lightweight files."
        case 800..<1600:
            return "Balanced size for email and casual web use."
        case 1600..<2600:
            return "Great for websites, blogs, and general uploads."
        case 2600..<3600:
            return "Higher detail while still reducing file size."
        default:
            return "Maximum detail, larger output files."
        }
    }

    var qualityDescription: String {
        switch jpegQuality {
        case 0..<0.40:
            return "Aggressive compression for the smallest files."
        case 0.40..<0.70:
            return "Balanced compression with noticeable savings."
        case 0.70..<0.90:
            return "High quality with strong visual retention."
        default:
            return "Best quality with lighter compression."
        }
    }

    var actionStatusTitle: String {
        if isProcessing {
            return "Processing \(processedCount) of \(totalCount)"
        }
        if items.isEmpty {
            return "No images selected yet"
        }
        return "\(items.count) image(s) ready to export"
    }

    var actionStatusSubtitle: String {
        if isProcessing {
            return "PixelPress is resizing and compressing your images."
        }
        return "Choose a preset, fine-tune settings, then export."
    }

    var progressLabel: String {
        if isProcessing {
            return "Working..."
        } else if progress == 1 && processedCount > 0 {
            return "Done"
        } else {
            return "Waiting to begin"
        }
    }

    var renamePreviewText: String {
        let sample = "IMG_2048"
        switch renameMode {
        case .suffixDimension:
            return "Example: photo-2048w.jpg"
        case .prefixPreset:
            return "Example: \(selectedPreset.title.lowercased())-\(sample).jpg"
        case .customPrefix:
            let prefix = customPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "PixelPress" : customPrefix
            return "Example: \(prefix)-\(sample).jpg"
        case .replaceOriginalName:
            return "Example: export-1.jpg"
        }
    }
}

// MARK: - Actions
private extension ContentView {
    func applyPreset(_ preset: ExportPreset) {
        selectedPreset = preset

        switch preset {
        case .web:
            maxDimension = 2048
            jpegQuality = 0.82
            outputFormat = .jpeg
            useTargetCompression = false

        case .email:
            maxDimension = 1280
            jpegQuality = 0.72
            outputFormat = .jpeg
            useTargetCompression = true
            targetSizeKB = 350

        case .social:
            maxDimension = 1600
            jpegQuality = 0.80
            outputFormat = .jpeg
            useTargetCompression = false

        case .archive:
            maxDimension = 4096
            jpegQuality = 0.95
            outputFormat = .jpeg
            useTargetCompression = false
        }

        appendLog("Applied preset: \(preset.title)")
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    DispatchQueue.main.async {
                        guard let data = item as? Data,
                              let url = URL(dataRepresentation: data, relativeTo: nil) else {
                            self.appendLog("❌ Could not read dropped item.")
                            return
                        }

                        self.importURLs([url])
                    }
                }
                handled = true
            }
        }

        return handled
    }

    func importURLs(_ urls: [URL]) {
        let before = items.count

        for url in urls {
            if isDirectory(url) {
                let nested = collectImagesRecursively(in: url)
                for file in nested {
                    _ = addItem(file)
                }
            } else {
                _ = addItem(url)
            }
        }

        let net = items.count - before
        appendLog("Added \(net) image(s) from \(urls.count) item(s).")

        if items.count > 0 && before == 0 {
            applyPreset(selectedPreset)
        }
    }

    @discardableResult
    func addItem(_ url: URL) -> Bool {
        guard isSupportedImage(url) else { return false }
        guard !items.contains(where: { $0.url == url }) else { return false }
        guard let image = NSImage(contentsOf: url) else { return false }

        let newItem = ImageItem(
            url: url,
            previewImage: image,
            originalBytes: fileSize(for: url),
            lastExportResult: nil
        )

        items.append(newItem)
        return true
    }

    func removeItem(_ item: ImageItem) {
        items.removeAll { $0.id == item.id }
        appendLog("Removed \(item.url.lastPathComponent)")
    }

    func clearAll() {
        items.removeAll()
        exportSummary = nil
        progress = 0
        processedCount = 0
        totalCount = 0
        appendLog("Cleared all selected images.")
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"

        if panel.runModal() == .OK {
            outputFolderURL = panel.url
            appendLog("Output folder set to: \(panel.url?.path ?? "Unknown")")
        }
    }

    func openOutputLocation() {
        switch outputMode {
        case .sameFolder:
            if let first = items.first {
                NSWorkspace.shared.activateFileViewerSelecting([first.url.deletingLastPathComponent()])
            }
        case .customFolder:
            if let outputFolderURL {
                NSWorkspace.shared.open(outputFolderURL)
            }
        }
    }

    func revealLastExportedFiles(_ summary: ExportSummary) {
        let urls = summary.outputURLs
        if !urls.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    func processBatch() {
        guard !items.isEmpty else {
            appendLog("❌ No images selected.")
            return
        }

        if outputMode == .customFolder && outputFolderURL == nil {
            appendLog("❌ Please choose an output folder.")
            return
        }

        exportSummary = nil
        isProcessing = true
        progress = 0
        processedCount = 0
        totalCount = items.count

        for index in items.indices {
            items[index].lastExportResult = nil
        }

        appendLog("Starting export...")

        let snapshotItems = items
        let snapshotDimension = maxDimension
        let snapshotQuality = jpegQuality
        let snapshotFormat = outputFormat
        let snapshotUseTarget = useTargetCompression
        let snapshotTargetKB = targetSizeKB
        let snapshotOutputMode = outputMode
        let snapshotOutputFolder = outputFolderURL
        let snapshotRenameMode = renameMode
        let snapshotPrefix = customPrefix
        let snapshotPreset = selectedPreset

        DispatchQueue.global(qos: .userInitiated).async {
            var successful: [ExportItemSummary] = []
            var outputURLs: [URL] = []
            var totalOriginal: Int64 = 0
            var totalExported: Int64 = 0

            for (index, item) in snapshotItems.enumerated() {
                autoreleasepool {
                    let sourceURL = item.url
                    let originalBytes = item.originalBytes
                    totalOriginal += originalBytes

                    do {
                        guard let sourceImage = NSImage(contentsOf: sourceURL) else {
                            throw ExportError.failedToLoadImage
                        }

                        let resized = resizeImage(sourceImage, maxDimension: CGFloat(snapshotDimension))
                        let destinationFolder = resolveOutputFolder(
                            for: sourceURL,
                            mode: snapshotOutputMode,
                            outputFolderURL: snapshotOutputFolder
                        )
                        let outputName = buildOutputFileName(
                            sourceURL: sourceURL,
                            renameMode: snapshotRenameMode,
                            preset: snapshotPreset,
                            customPrefix: snapshotPrefix,
                            maxDimension: Int(snapshotDimension),
                            itemIndex: index + 1,
                            fileExtension: snapshotFormat.fileExtension
                        )
                        let outURL = destinationFolder.appendingPathComponent(outputName)

                        let data: Data
                        switch snapshotFormat {
                        case .jpeg:
                            if snapshotUseTarget {
                                data = try exportJPEGUnderTargetSize(
                                    image: resized,
                                    targetKB: snapshotTargetKB,
                                    fallbackQuality: snapshotQuality
                                )
                            } else {
                                data = try exportJPEG(resized, quality: snapshotQuality)
                            }
                        case .png:
                            data = try exportPNG(resized)
                        }

                        try data.write(to: outURL, options: .atomic)

                        let exportedBytes = Int64(data.count)
                        totalExported += exportedBytes
                        outputURLs.append(outURL)

                        successful.append(
                            ExportItemSummary(
                                fileName: outURL.lastPathComponent,
                                originalBytes: originalBytes,
                                exportedBytes: exportedBytes,
                                outputURL: outURL
                            )
                        )

                        DispatchQueue.main.async {
                            if let currentIndex = self.items.firstIndex(where: { $0.id == item.id }) {
                                let savedBytes = max(originalBytes - exportedBytes, 0)
                                let savedPercent = originalBytes > 0 ? Int((Double(savedBytes) / Double(originalBytes)) * 100) : 0
                                self.items[currentIndex].lastExportResult = ItemExportResult(
                                    success: true,
                                    badgeText: "-\(savedPercent)%"
                                )
                            }

                            self.appendLog("✅ \(sourceURL.lastPathComponent) → \(outURL.lastPathComponent)")
                        }
                    } catch {
                        DispatchQueue.main.async {
                            if let currentIndex = self.items.firstIndex(where: { $0.id == item.id }) {
                                self.items[currentIndex].lastExportResult = ItemExportResult(
                                    success: false,
                                    badgeText: "Failed"
                                )
                            }

                            self.appendLog("❌ \(sourceURL.lastPathComponent) — \(error.localizedDescription)")
                        }
                    }

                    DispatchQueue.main.async {
                        self.processedCount = index + 1
                        self.progress = Double(index + 1) / Double(max(totalCount, 1))
                    }
                }
            }

            let saved = max(totalOriginal - totalExported, 0)
            let percent = totalOriginal > 0 ? Int((Double(saved) / Double(totalOriginal)) * 100) : 0

            let summary = ExportSummary(
                processedCount: successful.count,
                totalOriginalBytes: totalOriginal,
                totalExportedBytes: totalExported,
                savedBytes: saved,
                percentSaved: percent,
                items: successful.sorted { $0.fileName < $1.fileName },
                outputURLs: outputURLs
            )

            DispatchQueue.main.async {
                self.isProcessing = false
                self.exportSummary = summary
                self.appendLog("Finished export. Saved \(formatBytes(summary.savedBytes)).")
            }
        }
    }

    func resolveOutputFolder(for originalURL: URL, mode: OutputMode, outputFolderURL: URL?) -> URL {
        switch mode {
        case .sameFolder:
            return originalURL.deletingLastPathComponent()
        case .customFolder:
            return outputFolderURL ?? originalURL.deletingLastPathComponent()
        }
    }

    func buildOutputFileName(
        sourceURL: URL,
        renameMode: RenameMode,
        preset: ExportPreset,
        customPrefix: String,
        maxDimension: Int,
        itemIndex: Int,
        fileExtension: String
    ) -> String {
        let originalBase = sourceURL.deletingPathExtension().lastPathComponent

        switch renameMode {
        case .suffixDimension:
            return "\(originalBase)-\(maxDimension)w.\(fileExtension)"

        case .prefixPreset:
            return "\(preset.title.lowercased())-\(originalBase)-\(maxDimension)w.\(fileExtension)"

        case .customPrefix:
            let safePrefix = customPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "PixelPress" : customPrefix
            return "\(safePrefix)-\(originalBase)-\(maxDimension)w.\(fileExtension)"

        case .replaceOriginalName:
            return "export-\(itemIndex).\(fileExtension)"
        }
    }

    func appendLog(_ message: String) {
        logMessages.append(message)
    }
}

// MARK: - File Helpers
private extension ContentView {
    func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }

    func collectImagesRecursively(in folderURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var found: [URL] = []

        for case let fileURL as URL in enumerator {
            if isSupportedImage(fileURL) {
                found.append(fileURL)
            }
        }

        return found
    }

    func isSupportedImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "heic", "tif", "tiff", "bmp"].contains(ext)
    }

    func fileSize(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Export Helpers
private extension ContentView {
    func resizeImage(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let original = image.size
        let longest = max(original.width, original.height)

        guard longest > maxDimension else { return image }

        let scale = maxDimension / longest
        let newSize = NSSize(width: original.width * scale, height: original.height * scale)

        let newImage = NSImage(size: newSize)
        newImage.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: original),
            operation: .copy,
            fraction: 1.0
        )

        newImage.unlockFocus()
        return newImage
    }

    func exportJPEG(_ image: NSImage, quality: Double) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]) else {
            throw ExportError.failedToCreateData
        }

        return data
    }

    func exportPNG(_ image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.failedToCreateData
        }

        return data
    }

    func exportJPEGUnderTargetSize(image: NSImage, targetKB: Int, fallbackQuality: Double) throws -> Data {
        let targetBytes = targetKB * 1024

        var low = 0.10
        var high = min(max(fallbackQuality, 0.10), 1.0)
        var bestData: Data?

        for _ in 0..<10 {
            let mid = (low + high) / 2
            let data = try exportJPEG(image, quality: mid)

            if data.count <= targetBytes {
                bestData = data
                low = mid
            } else {
                high = mid
            }
        }

        if let bestData {
            return bestData
        } else {
            return try exportJPEG(image, quality: 0.10)
        }
    }
}

// MARK: - Models
private struct ImageItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let previewImage: NSImage
    let originalBytes: Int64
    var lastExportResult: ItemExportResult?

    init(url: URL, previewImage: NSImage, originalBytes: Int64, lastExportResult: ItemExportResult?) {
        self.id = UUID()
        self.url = url
        self.previewImage = previewImage
        self.originalBytes = originalBytes
        self.lastExportResult = lastExportResult
    }

    static func == (lhs: ImageItem, rhs: ImageItem) -> Bool {
        lhs.id == rhs.id
    }

    func estimatedOutputBytes(
        format: OutputFormat,
        quality: Double,
        maxDimension: Double,
        useTargetCompression: Bool,
        targetKB: Int
    ) -> Int64 {
        if useTargetCompression && format == .jpeg {
            return Int64(targetKB * 1024)
        }

        let resizeFactor = estimatedResizeFactor(maxDimension: maxDimension)

        switch format {
        case .jpeg:
            let qualityFactor = max(0.12, quality)
            return Int64(Double(originalBytes) * resizeFactor * qualityFactor * 0.95)
        case .png:
            return Int64(Double(originalBytes) * resizeFactor * 0.90)
        }
    }

    func estimatedOutputText(
        format: OutputFormat,
        quality: Double,
        maxDimension: Double,
        useTargetCompression: Bool,
        targetKB: Int
    ) -> String {
        let estimate = estimatedOutputBytes(
            format: format,
            quality: quality,
            maxDimension: maxDimension,
            useTargetCompression: useTargetCompression,
            targetKB: targetKB
        )
        return "~\(ByteCountFormatter.string(fromByteCount: estimate, countStyle: .file))"
    }

    private func estimatedResizeFactor(maxDimension: Double) -> Double {
        guard let rep = NSBitmapImageRep(data: previewImage.tiffRepresentation ?? Data()) else {
            return 0.65
        }

        let width = Double(rep.pixelsWide)
        let height = Double(rep.pixelsHigh)
        let longest = max(width, height)

        if longest <= 0 { return 0.65 }
        if longest <= maxDimension { return 0.85 }

        let scale = maxDimension / longest
        return max(0.05, scale * scale)
    }
}

private struct ItemExportResult: Equatable {
    let success: Bool
    let badgeText: String
}

private struct ExportItemSummary: Identifiable {
    let id = UUID()
    let fileName: String
    let originalBytes: Int64
    let exportedBytes: Int64
    let outputURL: URL
}

private struct ExportSummary {
    let processedCount: Int
    let totalOriginalBytes: Int64
    let totalExportedBytes: Int64
    let savedBytes: Int64
    let percentSaved: Int
    let items: [ExportItemSummary]
    let outputURLs: [URL]
}

private enum OutputMode: String, CaseIterable, Identifiable {
    case sameFolder
    case customFolder

    var id: String { rawValue }
}

private enum OutputFormat: String, CaseIterable, Identifiable {
    case jpeg
    case png

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }

    var displayName: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        }
    }

    var descriptionText: String {
        switch self {
        case .jpeg:
            return "Best for smaller file sizes and adjustable compression."
        case .png:
            return "Best for lossless output, graphics, and transparency workflows."
        }
    }
}

private enum RenameMode: String, CaseIterable, Identifiable {
    case suffixDimension
    case prefixPreset
    case customPrefix
    case replaceOriginalName

    var id: String { rawValue }

    var title: String {
        switch self {
        case .suffixDimension: return "Keep name + add dimension"
        case .prefixPreset: return "Add preset prefix"
        case .customPrefix: return "Use custom prefix"
        case .replaceOriginalName: return "Replace with export numbering"
        }
    }

    var shortTitle: String {
        switch self {
        case .suffixDimension: return "Dimension"
        case .prefixPreset: return "Preset Prefix"
        case .customPrefix: return "Custom Prefix"
        case .replaceOriginalName: return "Export Number"
        }
    }
}

private enum ExportPreset: String, CaseIterable, Identifiable {
    case web
    case email
    case social
    case archive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .web: return "Web"
        case .email: return "Email"
        case .social: return "Social"
        case .archive: return "Archive"
        }
    }

    var subtitle: String {
        switch self {
        case .web:
            return "Balanced quality and size for websites and uploads."
        case .email:
            return "Smaller files for quick sending and lightweight sharing."
        case .social:
            return "Clean exports tuned for posts and online sharing."
        case .archive:
            return "Higher detail when you want to preserve more visual quality."
        }
    }

    var summaryLine: String {
        switch self {
        case .web: return "2048 px • JPEG • balanced"
        case .email: return "1280 px • lighter • target size"
        case .social: return "1600 px • JPEG • crisp"
        case .archive: return "4096 px • high quality"
        }
    }
}

private enum ExportError: LocalizedError {
    case failedToLoadImage
    case failedToCreateData

    var errorDescription: String? {
        switch self {
        case .failedToLoadImage:
            return "Could not load image."
        case .failedToCreateData:
            return "Could not create export data."
        }
    }
}

// MARK: - Drag Reorder Delegate
private struct ThumbnailDropDelegate: DropDelegate {
    let item: ImageItem
    @Binding var items: [ImageItem]

    func performDrop(info: DropInfo) -> Bool {
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.text]).first else { return }

        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
            DispatchQueue.main.async {
                guard let data = data as? Data,
                      let string = String(data: data, encoding: .utf8),
                      let draggedID = UUID(uuidString: string),
                      let fromIndex = items.firstIndex(where: { $0.id == draggedID }),
                      let toIndex = items.firstIndex(where: { $0.id == item.id }),
                      fromIndex != toIndex else { return }

                withAnimation {
                    let moved = items.remove(at: fromIndex)
                    items.insert(moved, at: toIndex)
                }
            }
        }
    }
}

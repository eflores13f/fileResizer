//
//  ContentView.swift
//  FileResizer
//
//  Created by eflo on 3/5/26.
//
import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {

    @State private var droppedURLs: [URL] = []
    @State private var outputFolder: URL? = nil

    @State private var maxDimension: Double = 2048
    @State private var jpegQuality: Double = 0.85

    @State private var isProcessing = false
    @State private var progress: Double = 0
    @State private var log: String = "Drop images or folders to begin…\n"
    
    @State private var useTargetKB: Bool = false
    @State private var targetKB: Int = 500
    
    @State private var processedCount: Int = 0

    var body: some View {

        VStack(alignment: .leading, spacing: 12) {

            Text("FileResizer")
                .font(.system(size: 22, weight: .bold))

            DropZoneView(onDropURLs: { urls in

                let expanded = expandToImageFiles(urls)

                let existing = Set(droppedURLs)
                let newOnes = expanded.filter { !existing.contains($0) }

                droppedURLs.append(contentsOf: newOnes)

                log.append("Added \(newOnes.count) image(s) from \(urls.count) dropped item(s)\n")
            })
            .frame(height: 140)


            HStack {

                Text(
                    isProcessing
                     ? "Processing: \(processedCount)/\(droppedURLs.count)"
                     : "Images: \(droppedURLs.count)"
                )

                Spacer()

                Button("Clear") {
                    droppedURLs.removeAll()
                    progress = 0
                    log = "Cleared.\n"
                }
                .disabled(isProcessing || droppedURLs.isEmpty)
            }


            GroupBox(label: Text("Settings")) {

                VStack(alignment: .leading) {

                    HStack {

                        Text("Max Dimension: \(Int(maxDimension))px")

                        Slider(value: $maxDimension,
                               in: 256...6000,
                               step: 64)
                        .disabled(isProcessing)
                    }


                    HStack {

                        Text("JPEG Quality: \(String(format: "%.2f", jpegQuality))")

                        Slider(value: $jpegQuality,
                               in: 0.10...1.00,
                               step: 0.01)
                        .disabled(isProcessing || useTargetKB)
                    }
                    
                    Toggle("Compress under target size (KB)", isOn: $useTargetKB)
                        .disabled(isProcessing)

                    HStack {
                        Text("Target: \(targetKB) KB")
                        Stepper("", value: $targetKB, in: 50...5000, step: 50)
                            .labelsHidden()
                            .disabled(isProcessing || !useTargetKB)

                        Spacer()

                        Text(useTargetKB ? "Auto quality" : "Manual quality")
                            .foregroundStyle(.secondary)
                    }


                    HStack {

                        Text("Output:")

                        Text(outputFolder?.path ?? "Same as original (beside each file)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Button("Choose Folder") {

                            outputFolder = pickFolder()

                            if let outputFolder {
                                log.append("Output folder: \(outputFolder.path)\n")
                            }
                        }
                        .disabled(isProcessing)


                        Button("Open Output") {

                            if let folder = outputFolder {
                                NSWorkspace.shared.open(folder)
                            }
                        }
                        .disabled(outputFolder == nil)
                    }
                }
                .padding(.top, 6)
            }


            HStack(spacing: 12) {

                Button(isProcessing ? "Processing…" : "Resize & Export") {

                    Task {
                        await processBatch()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isProcessing || droppedURLs.isEmpty)


                ProgressView(value: progress)
                    .frame(maxWidth: .infinity)
            }


            GroupBox(label: Text("Log")) {

                ScrollView {

                    Text(log)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity,
                               alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 180)
            }

        }
        .padding(16)
        .frame(width: 640, height: 560)
    }

    // MARK: - Batch Processing
    
    @MainActor
    private func processBatch() async {

        isProcessing = true
        processedCount = 0         // at start
        processedCount += 1        // inside the loop
        progress = Double(processedCount) / Double(droppedURLs.count)   // update progress
    

        let total = Double(droppedURLs.count)
        var done = 0.0

        for url in droppedURLs {

            do {

                try resizeAndExport(url: url,
                                    maxDimension: CGFloat(maxDimension),
                                    jpegQuality: CGFloat(jpegQuality),
                                    outputFolder: outputFolder,
                                    useTargetKB: useTargetKB,
                                    targetKB: targetKB)

                log.append("✅ \(url.lastPathComponent)\n")

            } catch {

                log.append("❌ \(url.lastPathComponent) — \(error.localizedDescription)\n")
            }

            done += 1
            progress = done / total
        }

        log.append("Finished \(Int(done))/\(Int(total))\n")

        isProcessing = false
    }

    // MARK: - Core Work

    private func resizeAndExport(url: URL,
                                 maxDimension: CGFloat,
                                 jpegQuality: CGFloat,
                                 outputFolder: URL?,
                                 useTargetKB: Bool,
                                 targetKB: Int) throws {

        guard let image = NSImage(contentsOf: url) else {
            throw AppError.message("Could not read image")
        }

        let resized = ImageResizer.resize(nsImage: image,
                                          maxDimension: maxDimension)
        let outDir = outputFolder ?? url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let outURL = outDir.appendingPathComponent("\(base)-\(Int(maxDimension))w.jpg")

        if useTargetKB {
            try ImageResizer.writeJPEGUnderKB(nsImage: resized, to: outURL, targetKB: targetKB)
        } else {
            try ImageResizer.writeJPEG(nsImage: resized, to: outURL, quality: jpegQuality)
        }
    }

    // MARK: - Helpers

    private func pickFolder() -> URL? {

        let panel = NSOpenPanel()

        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        return panel.runModal() == .OK ? panel.url : nil
    }


    private func isSupportedImage(_ url: URL) -> Bool {

        let ext = url.pathExtension.lowercased()

        return ["jpg","jpeg","png","heic","tiff","bmp"].contains(ext)
    }


    private func isDirectory(_ url: URL) -> Bool {

        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }


    private func collectImagesRecursively(in folderURL: URL) -> [URL] {

        let fm = FileManager.default

        guard let enumerator = fm.enumerator(at: folderURL,
                                             includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [.skipsHiddenFiles]) else { return [] }

        var found: [URL] = []

        for case let fileURL as URL in enumerator {

            if isDirectory(fileURL) { continue }

            if isSupportedImage(fileURL) {
                found.append(fileURL)
            }
        }

        return found
    }


    private func expandToImageFiles(_ urls: [URL]) -> [URL] {

        var results: [URL] = []

        for url in urls {

            if isDirectory(url) {

                results.append(contentsOf: collectImagesRecursively(in: url))

            } else if isSupportedImage(url) {

                results.append(url)
            }
        }

        var seen = Set<URL>()

        return results.filter { seen.insert($0).inserted }
    }
}


// MARK: - Drag & Drop View

struct DropZoneView: View {

    var onDropURLs: ([URL]) -> Void

    @State private var isTargeted = false


    var body: some View {

        ZStack {

            RoundedRectangle(cornerRadius: 16)

                .strokeBorder(isTargeted ? .blue : .gray.opacity(0.5),
                              style: StrokeStyle(lineWidth: 2, dash: [8]))

            VStack(spacing: 6) {

                Text("Drag & Drop Images or Folders")
                    .font(.system(size: 16, weight: .semibold))

                Text("JPG • PNG • HEIC • TIFF")
                    .foregroundStyle(.secondary)
            }
        }

        .onDrop(of: [.fileURL],
                isTargeted: $isTargeted) { providers in

            var urls: [URL] = []

            let group = DispatchGroup()

            for provider in providers {

                group.enter()

                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier,
                                  options: nil) { item, _ in

                    defer { group.leave() }

                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data,
                                        relativeTo: nil) else { return }

                    urls.append(url)
                }
            }

            group.notify(queue: .main) {

                onDropURLs(urls)
            }

            return true
        }
    }
}


// MARK: - Errors

enum AppError: Error {

    case message(String)

    var localizedDescription: String {

        switch self {

        case .message(let msg):
            return msg
        }
    }
}


// MARK: - Image Processing

enum ImageResizer {

    static func resize(nsImage: NSImage,
                       maxDimension: CGFloat) -> NSImage {

        let originalSize = nsImage.size

        let maxSide = max(originalSize.width,
                          originalSize.height)

        guard maxSide > 0 else { return nsImage }

        let scale = min(1.0,
                        maxDimension / maxSide)

        let newSize = NSSize(width: originalSize.width * scale,
                             height: originalSize.height * scale)

        let newImage = NSImage(size: newSize)

        newImage.lockFocus()

        NSGraphicsContext.current?.imageInterpolation = .high

        nsImage.draw(in: NSRect(origin: .zero,
                                size: newSize),
                     from: NSRect(origin: .zero,
                                  size: originalSize),
                     operation: .copy,
                     fraction: 1.0)

        newImage.unlockFocus()

        return newImage
    }


    static func writeJPEG(nsImage: NSImage,
                          to url: URL,
                          quality: CGFloat) throws {

        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {

            throw AppError.message("Could not create bitmap representation")
        }

        let props: [NSBitmapImageRep.PropertyKey: Any] = [
            .compressionFactor: max(0.0,
                                    min(1.0,
                                        quality))
        ]

        guard let data = rep.representation(using: .jpeg,
                                            properties: props) else {

            throw AppError.message("Could not encode JPEG")
        }

        try data.write(to: url,
                       options: .atomic)
    }
    static func writeJPEGUnderKB(nsImage: NSImage, to url: URL, targetKB: Int) throws {
        guard let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            throw AppError.message("Could not create bitmap representation")
        }

        let targetBytes = targetKB * 1024

        // Binary search for best quality that stays under target size
        var low: CGFloat = 0.10
        var high: CGFloat = 0.99
        var bestData: Data? = nil

        for _ in 0..<12 {
            let mid = (low + high) / 2
            let props: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: mid]

            guard let data = rep.representation(using: .jpeg, properties: props) else { break }

            if data.count > targetBytes {
                high = mid
            } else {
                bestData = data
                low = mid
            }
        }

        if let bestData {
            try bestData.write(to: url, options: .atomic)
        } else {
            // If we couldn't get under target, write at minimum quality as fallback
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.10]) else {
                throw AppError.message("Could not encode JPEG")
            }
            try data.write(to: url, options: .atomic)
        }
    }}

/*
 * KSPhotoViewer
 * Copyright (C) 2026 KS
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO
import CoreImage
import CoreImage.CIFilterBuiltins
import AVKit
import AVFoundation
import ZIPFoundation // 🔥 นำเข้า Library สำหรับจัดการไฟล์ Zip

// MARK: - 1. Data Models
struct ImageFile: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let name: String
    let creationDate: Date
    let size: Int64
    
    // 🔥 เพิ่มตัวแปรสำหรับเก็บ "Path ของไฟล์ที่อยู่ข้างใน Zip"
    var zipEntryName: String? = nil
    
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

struct PhotoMetadata: Identifiable {
    let id = UUID()
    var filename: String = "-"
    var dimensions: String = "-"
    var size: String = "-"
    var iso: String = "-"
    var aperture: String = "-"
    var camera: String = "-"
}

enum SortOption {
    case name, date, size
}

struct ContentView: View {
    // --- State: Folder & Navigation ---
    @State private var folderFiles: [ImageFile] = []
    @State private var selectedFileID: UUID? = nil
    @State private var currentFolderName: String = "No Folder Selected"
    
    // --- Sorting & View Options ---
    @State private var sortOption: SortOption = .name
    @State private var sortAscending: Bool = true
    @State private var thumbnailSize: CGFloat = 50.0
    
    // --- State: Image & Editing ---
    @State private var currentImage: NSImage? = nil
    @State private var originalBaseImage: NSImage? = nil
    @State private var currentMetadata: PhotoMetadata = PhotoMetadata()
    @State private var showInspector: Bool = true
    @State private var currentZoom: CGFloat = 1.0
    
    // --- State: Media Player ---
    @State private var avPlayer: AVPlayer? = nil
    @State private var isMediaFile: Bool = false
    
    // --- Undo/Redo ---
    @State private var undoStack: [NSImage] = []
    @State private var redoStack: [NSImage] = []
    
    // --- File URL ---
    @State private var currentFileURL: URL? = nil
    
    // --- Settings ---
    @State private var enableAnimation: Bool = true
    
    // --- Modes ---
    @State private var isCropping: Bool = false
    @State private var isEditing: Bool = false
    
    // --- Edit Params ---
    @State private var brightness: Float = 0.0
    @State private var contrast: Float = 1.0
    @State private var saturation: Float = 1.0
    @State private var rotationAngle: Double = 0.0
    @State private var flipHorizontal: Bool = false
    @State private var flipVertical: Bool = false
    
    // --- Crop ---
    @State private var cropSelection: CGRect = CGRect(x: 50, y: 50, width: 200, height: 200)
    @State private var displayedImageSize: CGSize = .zero
    
    // --- Constants ---
    let minZoom: CGFloat = 0.1
    let maxZoom: CGFloat = 5.0
    let zoomStep: CGFloat = 0.5
    let maxUndoSteps = 20
    let context = CIContext()
    
    // Config: Toolbar Settings
    let iconSize: CGFloat = 18.0
    let dividerHeight: CGFloat = 22.0

    var body: some View {
        NavigationSplitView {
            // MARK: - Left Sidebar (File Browser)
            VStack(spacing: 0) {
                // --- Header ---
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "folder.fill").foregroundColor(.blue)
                        Text(currentFolderName).font(.headline).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(action: openFolderOnly) {
                            Image(systemName: "arrow.triangle.2.circlepath").font(.caption)
                        }.help("Change Folder").buttonStyle(.bordered).controlSize(.small)
                    }
                    
                    HStack {
                        Image(systemName: "photo").font(.caption).foregroundColor(.secondary)
                        Slider(value: $thumbnailSize, in: 30...120).controlSize(.mini)
                        Spacer()
                        HStack(spacing: 6) {
                            Menu {
                                Button(action: { changeSort(.name) }) { Label("Name", systemImage: sortOption == .name ? "checkmark" : "") }
                                Button(action: { changeSort(.date) }) { Label("Date", systemImage: sortOption == .date ? "checkmark" : "") }
                                Button(action: { changeSort(.size) }) { Label("Size", systemImage: sortOption == .size ? "checkmark" : "") }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(sortOptionLabel).font(.caption).fontWeight(.medium).fixedSize()
                                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 3).background(Color.secondary.opacity(0.1)).cornerRadius(6)
                            }.menuStyle(.borderlessButton).help("Sort By")
                            
                            Button(action: toggleSortOrder) {
                                Image(systemName: sortAscending ? "arrow.up" : "arrow.down").font(.caption)
                            }.buttonStyle(.borderless).help(sortAscending ? "Ascending" : "Descending").frame(width: 20)
                        }
                    }
                }
                .padding().background(Color(nsColor: .controlBackgroundColor))
                Divider()
                
                if folderFiles.isEmpty {
                    VStack(spacing: 15) {
                        Spacer()
                        Image(systemName: "folder").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.3))
                        Text("No Images Found").font(.caption).foregroundColor(.secondary)
                        Button("Open Folder") { openFolderOnly() }
                        Spacer()
                    }
                } else {
                    List(selection: $selectedFileID) {
                        ForEach(folderFiles) { file in
                            HStack(alignment: .center, spacing: 10) {
                                // ส่งค่า zipEntryName ไปให้ตัวโหลดรูปด้วย
                                AsyncThumbnailView(url: file.url, size: thumbnailSize, zipEntryName: file.zipEntryName)
                                    .frame(width: thumbnailSize, height: thumbnailSize).cornerRadius(4).shadow(radius: 1)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                                    HStack { Text(file.formattedSize); Spacer(); Text(file.creationDate, style: .date) }.font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4).tag(file.id)
                        }
                    }
                    .listStyle(.sidebar)
                    .onChange(of: selectedFileID) { newID in
                        if let id = newID, let file = folderFiles.first(where: { $0.id == id }) {
                            // สั่งโหลดรูป (รองรับทั้งไฟล์ปกติและไฟล์ใน Zip)
                            loadImage(from: file.url, zipEntryName: file.zipEntryName)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 280)
            
        } detail: {
            HStack(spacing: 0) {
                // MARK: - Center Canvas
                GeometryReader { geometry in
                    ZStack {
                        Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                        
                        if isMediaFile, let player = avPlayer {
                            VideoPlayer(player: player).onAppear { player.play() }.onDisappear { player.pause() }.padding()
                        } else if let image = currentImage {
                            ZStack(alignment: .topLeading) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .scaleEffect(isCropping ? 1.0 : currentZoom)
                                    .opacity(isCropping ? 0.6 : 1.0)
                                    .animation((enableAnimation && !isCropping) ? .spring(response: 0.4, dampingFraction: 0.7) : nil, value: currentZoom)
                                    .overlay(GeometryReader { imageGeo in Color.clear.onAppear { displayedImageSize = imageGeo.size }.onChange(of: imageGeo.size) { newValue in displayedImageSize = newValue } })
                                if isCropping { CropOverlay(selection: $cropSelection, imageSize: displayedImageSize) }
                            }
                            .coordinateSpace(name: "imageSpace").padding()
                            .gesture((isCropping || isEditing) ? nil : MagnificationGesture().onChanged { value in let newZoom = value; if newZoom >= minZoom && newZoom <= maxZoom { currentZoom = newZoom } })
                        } else {
                            VStack(spacing: 15) {
                                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 60)).foregroundColor(.secondary)
                                Text("KS Photo Viewer").font(.title2).foregroundColor(.secondary)
                                HStack {
                                    Button("Open File") { openSingleFile() }
                                    Button("Open Folder") { openFolderOnly() }
                                }.controlSize(.large)
                            }
                        }
                        
                        // Crop/Edit Controls
                        if currentImage != nil && !isMediaFile {
                            VStack {
                                Spacer()
                                if isCropping {
                                    HStack(spacing: 20) {
                                        Button(action: { isCropping = false }) { Label("Cancel", systemImage: "xmark").foregroundColor(.red) }.buttonStyle(.bordered)
                                        Button(action: performCrop) { Label("Done", systemImage: "checkmark").foregroundColor(.green) }.buttonStyle(.bordered)
                                    }.padding().background(.regularMaterial).cornerRadius(12).padding(.bottom, 20)
                                } else if isEditing {
                                    HStack(spacing: 20) {
                                        Button(action: cancelEdit) { Label("Cancel", systemImage: "xmark").foregroundColor(.red) }.buttonStyle(.bordered)
                                        Button(action: applyEdit) { Label("Done", systemImage: "checkmark").foregroundColor(.green) }.buttonStyle(.bordered)
                                    }.padding().background(.regularMaterial).cornerRadius(12).padding(.bottom, 20)
                                }
                            }
                        }
                    }
                }
                
                // MARK: - Right Inspector
                if showInspector {
                    VStack {
                        if isEditing {
                            EditPanel(brightness: $brightness, contrast: $contrast, saturation: $saturation, onRotate: rotateImage, onFlipH: { flipHorizontal.toggle(); applyFilters() }, onFlipV: { flipVertical.toggle(); applyFilters() }, onChange: applyFilters)
                        } else {
                            InspectorView(metadata: currentMetadata, enableAnimation: $enableAnimation)
                        }
                    }.frame(width: 260).background(.ultraThinMaterial).transition(.move(edge: .trailing))
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 8) {
                    Button(action: openSingleFile) { Label("Open", systemImage: "doc.text.image").font(.system(size: iconSize)) }.help("Open File")
                    Button(action: showSaveDialog) { Label("Save", systemImage: "square.and.arrow.down").font(.system(size: iconSize)) }.disabled(currentImage == nil || isMediaFile).help("Save Image")
                }
            }
            ToolbarItem(placement: .principal) {
                HStack(spacing: 12) {
                    HStack(spacing: 0) {
                        Button(action: performUndo) { Label("Undo", systemImage: "arrow.uturn.backward").font(.system(size: iconSize)) }.disabled(undoStack.isEmpty || isMediaFile)
                        Button(action: performRedo) { Label("Redo", systemImage: "arrow.uturn.forward").font(.system(size: iconSize)) }.disabled(redoStack.isEmpty || isMediaFile)
                    }
                    Divider().frame(height: dividerHeight)
                    HStack(spacing: 0) {
                        Button(action: zoomOut) { Label("Zoom Out", systemImage: "minus.magnifyingglass").font(.system(size: iconSize)) }.disabled(currentImage == nil || isMediaFile)
                        Button(action: resetZoom) { Label("Reset", systemImage: "arrow.up.left.and.arrow.down.right").font(.system(size: iconSize)) }.disabled(currentImage == nil || isMediaFile)
                        Button(action: zoomIn) { Label("Zoom In", systemImage: "plus.magnifyingglass").font(.system(size: iconSize)) }.disabled(currentImage == nil || isMediaFile)
                    }
                    Divider().frame(height: dividerHeight)
                    HStack(spacing: 0) {
                        Button(action: startCrop) { Label("Crop", systemImage: "crop").font(.system(size: iconSize)) }.disabled(currentImage == nil || isEditing || isMediaFile)
                        Button(action: startEdit) { Label("Edit", systemImage: "slider.horizontal.3").font(.system(size: iconSize)) }.disabled(currentImage == nil || isCropping || isMediaFile)
                    }
                    Divider().frame(height: dividerHeight)
                    Button(action: { withAnimation { showInspector.toggle() } }) { Label("Info", systemImage: "info.circle").font(.system(size: iconSize)) }.help("Toggle Info Panel")
                }
            }
        }
        .onOpenURL { url in
            if url.pathExtension.lowercased() == "zip" {
                loadZipContent(zipURL: url)
            } else {
                loadImage(from: url)
                let parentFolder = url.deletingLastPathComponent()
                loadFolderContent(folderURL: parentFolder, fileToSelect: url)
            }
        }
    }
    
    var sortOptionLabel: String {
        switch sortOption { case .name: return "Name"; case .date: return "Date"; case .size: return "Size" }
    }
    
    // MARK: - 📂 Open & Load Logic
    func openSingleFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image, .movie, .audio, .zip, .archive]; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                if url.pathExtension.lowercased() == "zip" {
                    loadZipContent(zipURL: url)
                } else {
                    loadImage(from: url)
                    let parentFolder = url.deletingLastPathComponent()
                    loadFolderContent(folderURL: parentFolder, fileToSelect: url)
                }
            }
        }
    }
    
    func openFolderOnly() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true // 🔥 อนุญาตให้เลือกไฟล์ได้ด้วย (สำหรับไฟล์ Zip)
        
        // กำหนดให้เลือกได้เฉพาะ โฟลเดอร์, ไฟล์ zip และ archive
        panel.allowedContentTypes = [.folder, .zip, .archive] 
        
        panel.begin { response in 
            if response == .OK, let url = panel.url { 
                // เช็คว่าสิ่งที่ผู้ใช้เลือกมาเป็น Zip หรือ โฟลเดอร์ปกติ
                if url.pathExtension.lowercased() == "zip" {
                    loadZipContent(zipURL: url)
                } else {
                    loadFolderContent(folderURL: url) 
                }
            } 
        }
    }
    
    // 🔥 อ่านเนื้อหาข้างในไฟล์ Zip (แก้ Warning เรื่อง Archive เรียบร้อยแล้ว)
    func loadZipContent(zipURL: URL) {
        self.currentFolderName = zipURL.lastPathComponent + " (ZIP)"
        self.currentFileURL = zipURL
        
        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read)
        } catch {
            print("ไม่สามารถเปิดไฟล์ Zip ได้: \(error.localizedDescription)")
            return
        }
        
        var newFiles: [ImageFile] = []
        
        for entry in archive {
            guard entry.type == .file else { continue }
            
            let ext = (entry.path as NSString).pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "heic", "tiff", "gif", "bmp", "webp"].contains(ext) {
                let name = (entry.path as NSString).lastPathComponent
                let size = Int64(entry.uncompressedSize)
                let date = Date() 
                
                newFiles.append(ImageFile(url: zipURL, name: name, creationDate: date, size: size, zipEntryName: entry.path))
            }
        }
        
        self.folderFiles = newFiles
        applySort()
        
        if let first = self.folderFiles.first {
            self.selectedFileID = first.id
            loadImage(from: first.url, zipEntryName: first.zipEntryName)
        }
    }
    
    func loadFolderContent(folderURL: URL, fileToSelect: URL? = nil) {
        self.currentFolderName = folderURL.lastPathComponent
        do {
            let resourceKeys: [URLResourceKey] = [.nameKey, .creationDateKey, .fileSizeKey, .isDirectoryKey]
            let fileURLs = try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: resourceKeys)
            var newFiles: [ImageFile] = []
            for url in fileURLs {
                let resourceValues = try url.resourceValues(forKeys: Set(resourceKeys))
                if resourceValues.isDirectory == true { continue }
                let ext = url.pathExtension.lowercased()
                
                if ["jpg", "jpeg", "png", "heic", "tiff", "gif", "bmp", "webp", "mp4", "mov", "mkv", "mp3", "m4a", "wav", "zip"].contains(ext) {
                    let name = resourceValues.name ?? url.lastPathComponent
                    let date = resourceValues.creationDate ?? Date.distantPast
                    let size = Int64(resourceValues.fileSize ?? 0)
                    newFiles.append(ImageFile(url: url, name: name, creationDate: date, size: size))
                }
            }
            self.folderFiles = newFiles
            applySort()
            
            if let targetURL = fileToSelect, let match = self.folderFiles.first(where: { $0.url == targetURL }) {
                self.selectedFileID = match.id
            } else if let first = self.folderFiles.first, fileToSelect == nil {
                self.selectedFileID = first.id
                if first.url.pathExtension.lowercased() == "zip" {
                    loadZipContent(zipURL: first.url)
                } else {
                    loadImage(from: first.url)
                }
            }
        } catch { print("Error reading folder: \(error)") }
    }

    // MARK: - 💾 Save Logic
    func showSaveDialog() {
        let alert = NSAlert(); alert.messageText = "Save Image"; alert.informativeText = "Choose how you want to save the changes."; alert.alertStyle = .informational
        alert.addButton(withTitle: "Save as New"); alert.addButton(withTitle: "Overwrite"); alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn { startSaveAsNewProcess() } else if response == .alertSecondButtonReturn { startOverwriteProcess() }
    }
    
    func startSaveAsNewProcess() {
        guard let originalURL = currentFileURL else { return }
        let directory = originalURL.deletingLastPathComponent()
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let extString = originalURL.pathExtension.lowercased()
        var allowedType: UTType = .jpeg
        switch extString { case "png": allowedType = .png; case "tiff", "tif": allowedType = .tiff; case "bmp": allowedType = .bmp; case "gif": allowedType = .gif; case "heic", "webp": allowedType = .jpeg; default: allowedType = .jpeg }
        let targetExt = (allowedType == .jpeg) ? "jpg" : extString
        var counter = 1; var candidateName = "\(baseName) - edited \(counter)"
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(candidateName).\(targetExt)").path) { counter += 1; candidateName = "\(baseName) - edited \(counter)" }
        
        let savePanel = NSSavePanel(); savePanel.canCreateDirectories = true; savePanel.directoryURL = directory; savePanel.nameFieldStringValue = candidateName; savePanel.allowedContentTypes = [allowedType]
        savePanel.begin { response in if response == .OK, let targetURL = savePanel.url { writeImageToURL(targetURL); self.currentFileURL = targetURL; self.currentMetadata.filename = targetURL.lastPathComponent; let parentFolder = targetURL.deletingLastPathComponent(); loadFolderContent(folderURL: parentFolder, fileToSelect: targetURL) } }
    }
    
    func startOverwriteProcess() { let confirm = NSAlert(); confirm.messageText = "Are you sure?"; confirm.informativeText = "Replace original file?"; confirm.alertStyle = .warning; confirm.addButton(withTitle: "Replace"); confirm.addButton(withTitle: "Cancel"); if confirm.runModal() == .alertFirstButtonReturn, let url = currentFileURL { writeImageToURL(url) } }
    
    func writeImageToURL(_ url: URL) {
        guard let image = currentImage else { return }
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage); bitmapRep.size = image.size
        let fileExtension = url.pathExtension.lowercased(); var fileType: NSBitmapImageRep.FileType = .jpeg; var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        switch fileExtension { case "png": fileType = .png; case "tiff", "tif": fileType = .tiff; properties = [.compressionMethod: NSBitmapImageRep.TIFFCompression.lzw]; case "bmp": fileType = .bmp; case "gif": fileType = .gif; default: fileType = .jpeg; properties = [.compressionFactor: 0.9] }
        guard let data = bitmapRep.representation(using: fileType, properties: properties) else { return }
        do { try data.write(to: url) } catch { print("Error saving file: \(error)") }
    }
    
    func performCrop() {
        guard let nsImage = currentImage else { return }
        var rect = NSRect(origin: .zero, size: nsImage.size)
        guard let cgImage = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return }
        recordChange(imageToSave: nsImage)
        
        let viewSize = displayedImageSize
        let widthRatio = CGFloat(cgImage.width) / viewSize.width
        let heightRatio = CGFloat(cgImage.height) / viewSize.height
        let cropWidth = cropSelection.width * widthRatio; let cropHeight = cropSelection.height * heightRatio; let cropX = cropSelection.minX * widthRatio; let cropY = cropSelection.minY * heightRatio 
        let cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
        
        if let cropped = cgImage.cropping(to: cropRect) {
            let newImage = NSImage(cgImage: cropped, size: NSSize(width: cropWidth, height: cropHeight)); self.currentImage = newImage; self.originalBaseImage = newImage
            var newMeta = currentMetadata; newMeta.dimensions = "\(Int(cropWidth)) x \(Int(cropHeight))"; self.currentMetadata = newMeta
        }
        isCropping = false
    }
    
    // 🔥 ฟังก์ชันโหลดไฟล์ (รองรับ Zip ด้วย do-catch อย่างถูกต้อง)
    func loadImage(from url: URL, zipEntryName: String? = nil) {
        undoStack.removeAll(); redoStack.removeAll(); currentZoom = 1.0; isEditing = false; isCropping = false
        avPlayer?.pause(); avPlayer = nil; currentImage = nil; originalBaseImage = nil
        self.currentFileURL = url
        
        // 📦 กรณี: เป็นรูปที่อยู่ในไฟล์ Zip
        if let entryPath = zipEntryName {
            self.isMediaFile = false
            
            do {
                let archive = try Archive(url: url, accessMode: .read)
                if let entry = archive[entryPath] {
                    var extractedData = Data()
                    _ = try archive.extract(entry) { dataChunk in
                        extractedData.append(dataChunk)
                    }
                    
                    if let image = NSImage(data: extractedData) {
                        self.currentImage = image
                        self.originalBaseImage = image
                        
                        let sizeFormatter = ByteCountFormatter(); sizeFormatter.countStyle = .file
                        let formattedSize = sizeFormatter.string(fromByteCount: Int64(entry.uncompressedSize))
                        
                        self.currentMetadata = PhotoMetadata(filename: (entryPath as NSString).lastPathComponent, dimensions: "\(Int(image.size.width)) x \(Int(image.size.height))", size: formattedSize, iso: "N/A (in Zip)", aperture: "N/A", camera: "Archive")
                    }
                }
            } catch { 
                print("Zip extract error: \(error.localizedDescription)") 
            }
            return
        }
        
        // 📁 กรณี: ไฟล์ปกติในโฟลเดอร์
        let ext = url.pathExtension.lowercased()
        let mediaExtensions = ["mp4", "mov", "mkv", "mp3", "m4a", "wav"]
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let sizeFormatter = ByteCountFormatter(); sizeFormatter.countStyle = .file
        let formattedSize = sizeFormatter.string(fromByteCount: fileSize)
        
        if mediaExtensions.contains(ext) {
            self.isMediaFile = true
            self.avPlayer = AVPlayer(url: url)
            self.currentMetadata = PhotoMetadata(filename: url.lastPathComponent, dimensions: "Media Format", size: formattedSize, iso: "-", aperture: "-", camera: "-")
        } else {
            self.isMediaFile = false
            if let image = NSImage(contentsOf: url) {
                self.currentImage = image; self.originalBaseImage = image
                var camModel="-"; var isoVal="-"; var apertureVal="-"
                if let src = CGImageSourceCreateWithURL(url as CFURL, nil) {
                    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String:Any]
                    if let tiff = props?[kCGImagePropertyTIFFDictionary as String] as? [String:Any] { camModel = "\((tiff[kCGImagePropertyTIFFMake as String] as? String) ?? "") \((tiff[kCGImagePropertyTIFFModel as String] as? String) ?? "")" }
                    if let exif = props?[kCGImagePropertyExifDictionary as String] as? [String:Any] { if let isos = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], let first = isos.first { isoVal = "ISO \(first)" }; if let f = exif[kCGImagePropertyExifFNumber as String] as? Double { apertureVal = String(format: "f/%.1f", f) } }
                }
                self.currentMetadata = PhotoMetadata(filename: url.lastPathComponent, dimensions: "\(Int(image.size.width)) x \(Int(image.size.height))", size: formattedSize, iso: isoVal, aperture: apertureVal, camera: camModel)
            }
        }
    }
    
    func changeSort(_ option: SortOption) { self.sortOption = option; applySort() }
    func toggleSortOrder() { self.sortAscending.toggle(); applySort() }
    func applySort() { switch sortOption { case .name: folderFiles.sort { sortAscending ? ($0.name.localizedStandardCompare($1.name) == .orderedAscending) : ($0.name.localizedStandardCompare($1.name) == .orderedDescending) }; case .date: folderFiles.sort { sortAscending ? ($0.creationDate < $1.creationDate) : ($0.creationDate > $1.creationDate) }; case .size: folderFiles.sort { sortAscending ? ($0.size < $1.size) : ($0.size > $1.size) } } }
    
    func navigateImage(direction: Int) {
        guard !isCropping && !isEditing, let currentID = selectedFileID, !folderFiles.isEmpty else { return }
        if let currentIndex = folderFiles.firstIndex(where: { $0.id == currentID }) {
            let nextIndex = currentIndex + direction
            if nextIndex >= 0 && nextIndex < folderFiles.count { let nextFile = folderFiles[nextIndex]; selectedFileID = nextFile.id }
        }
    }
    
    func recordChange(imageToSave: NSImage? = nil) { guard let image = imageToSave ?? currentImage else { return }; undoStack.append(image); redoStack.removeAll(); if undoStack.count > maxUndoSteps { undoStack.removeFirst() } }
    func performUndo() { guard !isCropping && !isEditing, let current = currentImage, !undoStack.isEmpty else { return }; redoStack.append(current); if let previousImage = undoStack.popLast() { currentImage = previousImage; originalBaseImage = previousImage; currentMetadata.dimensions = "\(Int(previousImage.size.width)) x \(Int(previousImage.size.height))" } }
    func performRedo() { guard !isCropping && !isEditing, let current = currentImage, !redoStack.isEmpty else { return }; undoStack.append(current); if let nextImage = redoStack.popLast() { currentImage = nextImage; originalBaseImage = nextImage; currentMetadata.dimensions = "\(Int(nextImage.size.width)) x \(Int(nextImage.size.height))" } }
    
    func startEdit() { originalBaseImage = currentImage; isEditing = true; showInspector = true; currentZoom = 1.0; brightness = 0.0; contrast = 1.0; saturation = 1.0; rotationAngle = 0.0; flipHorizontal = false; flipVertical = false }
    func cancelEdit() { currentImage = originalBaseImage; isEditing = false }
    func applyEdit() { if let baseImage = originalBaseImage { recordChange(imageToSave: baseImage) }; isEditing = false; if let newImg = currentImage { originalBaseImage = newImg } }
    func rotateImage() { rotationAngle += 90; if rotationAngle >= 360 { rotationAngle = 0 }; applyFilters() }
    
    func applyFilters() { guard let inputNSImage = originalBaseImage, let tiffData = inputNSImage.tiffRepresentation, let ciImage = CIImage(data: tiffData) else { return }; let filter = CIFilter.colorControls(); filter.inputImage = ciImage; filter.brightness = brightness; filter.contrast = contrast; filter.saturation = saturation; guard let outputCIImage = filter.outputImage else { return }; if let cgImage = context.createCGImage(outputCIImage, from: outputCIImage.extent) { let finalImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)); self.currentImage = transformImage(image: finalImage, degrees: rotationAngle, flipH: flipHorizontal, flipV: flipVertical) } }
    func transformImage(image: NSImage, degrees: Double, flipH: Bool, flipV: Bool) -> NSImage { var newSize = image.size; if degrees == 90 || degrees == 270 { newSize = NSSize(width: image.size.height, height: image.size.width) }; let newImage = NSImage(size: newSize); newImage.lockFocus(); let transform = NSAffineTransform(); transform.translateX(by: newSize.width / 2, yBy: newSize.height / 2); transform.rotate(byDegrees: CGFloat(-degrees)); let scaleX: CGFloat = flipH ? -1.0 : 1.0; let scaleY: CGFloat = flipV ? -1.0 : 1.0; transform.scaleX(by: scaleX, yBy: scaleY); transform.translateX(by: -image.size.width / 2, yBy: -image.size.height / 2); transform.concat(); image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0); newImage.unlockFocus(); return newImage }
    func startCrop() { guard displayedImageSize != .zero else { return }; let w = displayedImageSize.width * 0.5; let h = displayedImageSize.height * 0.5; let x = (displayedImageSize.width - w) / 2; let y = (displayedImageSize.height - h) / 2; cropSelection = CGRect(x: x, y: y, width: w, height: h); isCropping = true; currentZoom = 1.0 }
    func zoomIn() { let new = currentZoom + zoomStep; currentZoom = new <= maxZoom ? new : maxZoom }
    func zoomOut() { let new = currentZoom - zoomStep; currentZoom = new >= minZoom ? new : minZoom }
    func resetZoom() { currentZoom = 1.0 }
}

// MARK: - Subviews
struct AsyncThumbnailView: View {
    let url: URL
    let size: CGFloat
    var zipEntryName: String? = nil
    
    @State private var thumbnail: NSImage? = nil
    @State private var isFailed = false
    
    var body: some View {
        Group {
            if let thumb = thumbnail {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
            } else if isFailed {
                ZStack { Color.gray.opacity(0.1); Image(systemName: fallbackIcon).foregroundColor(.secondary) }
            } else {
                ZStack { Color.gray.opacity(0.1); ProgressView().scaleEffect(0.5) }
            }
        }
        .onAppear { loadThumbnail() }
        .onChange(of: size) { _ in loadThumbnail() }
        .onChange(of: url) { _ in thumbnail = nil; isFailed = false; loadThumbnail() }
        .onChange(of: zipEntryName) { _ in thumbnail = nil; isFailed = false; loadThumbnail() }
    }
    
    var fallbackIcon: String {
        if zipEntryName != nil { return "photo" }
        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "mkv"].contains(ext) { return "film" }
        if ["mp3", "m4a", "wav"].contains(ext) { return "music.note" }
        return "doc"
    }
    
    func loadThumbnail() {
        if zipEntryName != nil {
            DispatchQueue.main.async { self.isFailed = true }
            return
        }
        
        let currentURL = url
        let ext = currentURL.pathExtension.lowercased()
        
        if ["mp4", "mov", "mkv"].contains(ext) {
            Task {
                let asset = AVAsset(url: currentURL); let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true; generator.maximumSize = CGSize(width: size * 2, height: size * 2)
                do { let time = CMTime(seconds: 1.0, preferredTimescale: 600); let (cgImage, _) = try await generator.image(at: time); let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size)); await MainActor.run { if self.url == currentURL { self.thumbnail = nsImage } } } catch { await MainActor.run { if self.url == currentURL { self.isFailed = true } } }
            }
        } else if ["mp3", "m4a", "wav"].contains(ext) {
            DispatchQueue.main.async { self.isFailed = true }
        } else {
            DispatchQueue.global(qos: .userInteractive).async {
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: size * 2]
                if let source = CGImageSourceCreateWithURL(currentURL as CFURL, nil), let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) { let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: size, height: size)); DispatchQueue.main.async { if self.url == currentURL { self.thumbnail = nsImage } } } else { DispatchQueue.main.async { if self.url == currentURL { self.isFailed = true } } }
            }
        }
    }
}

struct EditPanel: View { @Binding var brightness: Float; @Binding var contrast: Float; @Binding var saturation: Float; var onRotate: () -> Void; var onFlipH: () -> Void; var onFlipV: () -> Void; var onChange: () -> Void; var body: some View { ScrollView { VStack(alignment: .leading, spacing: 25) { Text("Adjustments").font(.title3).fontWeight(.bold).padding(.top); GroupBox(label: Label("Tools", systemImage: "wrench.and.screwdriver")) { HStack(spacing: 15) { Button(action: { onRotate() }) { VStack { Image(systemName: "rotate.right"); Text("Rotate").font(.caption) } }.buttonStyle(.bordered); Button(action: { onFlipH() }) { VStack { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right"); Text("Flip H").font(.caption) } }.buttonStyle(.bordered); Button(action: { onFlipV() }) { VStack { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down"); Text("Flip V").font(.caption) } }.buttonStyle(.bordered); Spacer() }.padding(5) }; GroupBox(label: Label("Light & Color", systemImage: "slider.horizontal.3")) { VStack(spacing: 15) { SliderRow(label: "Brightness", value: $brightness, range: -0.5...0.5, icon: "sun.max", onChange: onChange); SliderRow(label: "Contrast", value: $contrast, range: 0.5...1.5, icon: "circle.lefthalf.filled", onChange: onChange); SliderRow(label: "Saturation", value: $saturation, range: 0.0...2.0, icon: "drop.fill", onChange: onChange) }.padding(5) }; Spacer() }.padding() } } }
struct SliderRow: View { var label: String; @Binding var value: Float; var range: ClosedRange<Float>; var icon: String; var onChange: () -> Void; var body: some View { VStack(alignment: .leading, spacing: 5) { HStack { Image(systemName: icon).foregroundColor(.secondary); Text(label).font(.caption).fontWeight(.medium); Spacer(); Text(String(format: "%.2f", value)).font(.caption).monospacedDigit() }; Slider(value: $value, in: range) { Text(label) } onEditingChanged: { _ in onChange() } } } }
struct CropOverlay: View { @Binding var selection: CGRect; var imageSize: CGSize; var body: some View { ZStack(alignment: .topLeading) { Rectangle().stroke(Color.white, lineWidth: 2).background(Color.black.opacity(0.1)).frame(width: selection.width, height: selection.height).offset(x: selection.minX, y: selection.minY).gesture(DragGesture().onChanged { value in let newX = value.location.x - (selection.width/2); let newY = value.location.y - (selection.height/2); let safeX = min(max(0, newX), imageSize.width - selection.width); let safeY = min(max(0, newY), imageSize.height - selection.height); selection.origin = CGPoint(x: safeX, y: safeY) }); Circle().fill(Color.blue).frame(width: 20, height: 20).shadow(radius: 2).offset(x: selection.minX + selection.width - 10, y: selection.minY + selection.height - 10).gesture(DragGesture(coordinateSpace: .named("imageSpace")).onChanged { value in let newW = min(max(50, value.location.x - selection.minX), imageSize.width - selection.minX); let newH = min(max(50, value.location.y - selection.minY), imageSize.height - selection.minY); selection.size = CGSize(width: newW, height: newH) }) } } }
struct InspectorView: View { var metadata: PhotoMetadata; @Binding var enableAnimation: Bool; var body: some View { ScrollView { VStack(alignment: .leading, spacing: 20) { Text("Info").font(.title3).fontWeight(.bold).padding(.top); GroupBox(label: Label("Settings", systemImage: "gearshape")) { Toggle("Smooth Zoom", isOn: $enableAnimation).toggleStyle(SwitchToggleStyle(tint: .blue)).padding(.vertical, 5) }; Group { InfoRow(label: "Filename", value: metadata.filename); InfoRow(label: "Size", value: metadata.size); InfoRow(label: "Dimensions", value: metadata.dimensions); Divider(); InfoRow(label: "Camera", value: metadata.camera); InfoRow(label: "ISO", value: metadata.iso); InfoRow(label: "Aperture", value: metadata.aperture) }; Spacer() }.padding() } } }
struct InfoRow: View { var label: String; var value: String; var body: some View { VStack(alignment: .leading) { Text(label).font(.caption).foregroundColor(.secondary); Text(value).font(.body) } } }
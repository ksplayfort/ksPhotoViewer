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
import AppKit // สำคัญ: ต้อง import AppKit เพื่อคุยกับระบบ

@main
struct KSPhotoViewerApp: App {
    
    // 1. เพิ่มส่วนนี้: สั่งให้แอปทำตัวเป็น "Regular App" (มีไอคอน มีหน้าต่าง)
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // 2. เพิ่มส่วนนี้: เมื่อหน้าต่างโผล่มา ให้เด้งมาอยู่หน้าสุดทันที
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
            
            // 🔥 เพิ่มเมนู About แบบ Custom เข้าไปแทนที่ของเดิมระบบ
            CommandGroup(replacing: .appInfo) {
                Button("About KSPhotoViewer") {
                    showAboutWindow()
                }
            }
        }
    }
}

// MARK: - About Window Management
func showAboutWindow() {
    // ป้องกันการเปิดหน้าต่าง About ซ้อนกันหลายหน้าต่าง
    for window in NSApplication.shared.windows {
        if window.title == "About KSPhotoViewer" {
            window.makeKeyAndOrderFront(nil)
            return
        }
    }
    
    let aboutView = AboutView()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 500, height: 450),
        styleMask: [.titled, .closable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.title = "About KSPhotoViewer"
    window.contentView = NSHostingView(rootView: aboutView)
    window.center()
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
}

// MARK: - About View (GPLv3 License & Disclaimer)
struct AboutView: View {
    var body: some View {
        VStack(spacing: 15) {
            // โลโก้แอป (ดึงจาก Assets)
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 90, height: 90)
            } else {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 60))
                    .foregroundColor(.accentColor)
            }
            
            Text("KSPhotoViewer")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 1.0")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Divider().padding(.horizontal, 40)
            
            // กล่องข้อความ License และ Disclaimer
            ScrollView {
                Text("""
                Copyright (C) 2026 KS
                
                This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

                This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

                You should have received a copy of the GNU General Public License along with this program. If not, see <https://www.gnu.org/licenses/>.
                """)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            .cornerRadius(8)
            .padding(.horizontal, 30)
            .frame(height: 180)
            
            HStack(spacing: 20) {
                Button("View License Online") {
                    if let url = URL(string: "https://www.gnu.org/licenses/gpl-3.0.html") {
                        NSWorkspace.shared.open(url)
                    }
                }
                
                Button("Close") {
                    if let window = NSApplication.shared.windows.first(where: { $0.title == "About KSPhotoViewer" }) {
                        window.close()
                    }
                }
                .keyboardShortcut(.defaultAction) // กด Enter ปิดได้
            }
            .padding(.bottom, 20)
        }
        .padding(.top, 30)
        .frame(width: 500, height: 450)
    }
}
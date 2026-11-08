// swift-tools-version: 5.9

// This is a Swift Playgrounds app package. Keep the AppleProductTypes import
// and the .iOSApplication product so Swift Playgrounds can build and run it.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "InkPad",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "InkPad",
            targets: ["AppModule"],
            bundleIdentifier: "com.mg554.inkpad",
            displayVersion: "0.1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .pencil),
            accentColor: .presetColor(.indigo),
            supportedDeviceFamilies: [
                .pad
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ],
            capabilities: [
                .microphone(purposeString: "InkPad records audio with your notes so you can play it back in step with your writing."),
                .speechRecognition(purposeString: "InkPad turns your recordings into text on this iPad, so you can search them and jump to each part."),
                .reminders(purposeString: "InkPad shows and edits your Reminders, and links reminders to your notes."),
                .camera(purposeString: "InkPad scans paper documents with the camera into notes.")
            ],
            appCategory: .productivity
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: "."
        )
    ]
)

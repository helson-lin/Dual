//
//  AppCloner.swift
//  Dual
//
//  Created by Codex on 2026/3/23.
//

import Foundation
import AppKit

enum AppClonerError: Error {
    case commandFailed(command: String, output: String)
    case invalidInfoPlist(path: String)
    case adminPrivilegeCancelled
    case adminAuthenticationFailed

    func localizedDescription(localeIdentifier: String?) -> String {
        switch self {
        case let .commandFailed(command, output):
            return L10n.string("cloner.error.commandFailed", localeIdentifier: localeIdentifier, command, output)
        case let .invalidInfoPlist(path):
            return L10n.string("cloner.error.invalidInfoPlist", localeIdentifier: localeIdentifier, path)
        case .adminPrivilegeCancelled:
            return L10n.string("cloner.error.adminCancelled", localeIdentifier: localeIdentifier)
        case .adminAuthenticationFailed:
            return L10n.string("cloner.error.adminAuthFailed", localeIdentifier: localeIdentifier)
        }
    }
}

private enum AppCloneProfile: Equatable {
    case generic
    case telegram
    case discord

    var needsIsolationCleanup: Bool {
        switch self {
        case .generic:
            return false
        case .telegram, .discord:
            return true
        }
    }

    var isolationCleanupNeedles: [String] {
        switch self {
        case .generic:
            return []
        case .telegram:
            return [
                "telegram",
                "tdesktop",
                "keepcoder"
            ]
        case .discord:
            return [
                "discord"
            ]
        }
    }

    var needsTelegramIdentityPatch: Bool {
        switch self {
        case .telegram:
            return true
        case .generic, .discord:
            return false
        }
    }
}

enum AppCloner {
    static func clone(
        sourceApp: String,
        destinationApp: String,
        bundleIdentifier: String,
        bundleName: String,
        clearDataBeforeClone: Bool,
        addCloneBadge: Bool,
        useAdminPrivileges: Bool,
        localeIdentifier: String?,
        logger: @escaping (String) -> Void
    ) async throws {
        logger(L10n.string("cloner.log.started", localeIdentifier: localeIdentifier))
        logger(L10n.string("cloner.log.source", localeIdentifier: localeIdentifier, sourceApp))
        logger(L10n.string("cloner.log.destination", localeIdentifier: localeIdentifier, destinationApp))

        let sourceBundleID = readBundleIdentifier(appPath: sourceApp)
        let profile = appProfile(sourceApp: sourceApp, sourceBundleIdentifier: sourceBundleID)
        let telegramIdentityLabel = profile.needsTelegramIdentityPatch ? telegramIdentityLabel(bundleIdentifier: bundleIdentifier) : nil
        let discordUserDataPath = profile == .discord ? discordUserDataPath(bundleIdentifier: bundleIdentifier) : nil


        if let sourceBundleID, sourceBundleID == bundleIdentifier {
            throw AppClonerError.commandFailed(
                command: "BundleID Check",
                output: L10n.string("cloner.error.bundleIdMatchesSource", localeIdentifier: localeIdentifier, sourceBundleID)
            )
        }

        let badgeIconURL: URL?
        if addCloneBadge {
            logger(L10n.string("cloner.log.createBadgeIcon", localeIdentifier: localeIdentifier))
            badgeIconURL = try createBadgeIcon(sourceApp: sourceApp)
        } else {
            badgeIconURL = nil
        }
        defer {
            if let badgeIconURL {
                try? FileManager.default.removeItem(at: badgeIconURL.deletingLastPathComponent())
            }
        }

        if clearDataBeforeClone {
            logger(L10n.string("cloner.log.clearingData", localeIdentifier: localeIdentifier))
            clearGenericCloneData(bundleIdentifier: bundleIdentifier, localeIdentifier: localeIdentifier, logger: logger)
            if profile == .discord {
                clearDiscordUserData(
                    bundleIdentifier: bundleIdentifier,
                    localeIdentifier: localeIdentifier,
                    logger: logger
                )
            }
        }

        if clearDataBeforeClone && profile.needsIsolationCleanup {
            logger(L10n.string("cloner.log.isolationCleanup", localeIdentifier: localeIdentifier))
            clearAppIsolationData(
                needles: profile.isolationCleanupNeedles,
                localeIdentifier: localeIdentifier,
                logger: logger
            )
        }

        if useAdminPrivileges {
            logger(L10n.string("cloner.log.usingAdmin", localeIdentifier: localeIdentifier))
            try cloneWithAdminPrivileges(
                sourceApp: sourceApp,
                destinationApp: destinationApp,
                bundleIdentifier: bundleIdentifier,
                bundleName: bundleName,
                badgeIconPath: badgeIconURL?.path,
                telegramIdentityLabel: telegramIdentityLabel,
                discordUserDataPath: discordUserDataPath,
                logger: logger
            )
            return
        }

        if FileManager.default.fileExists(atPath: destinationApp) {
            logger(L10n.string("cloner.log.destinationExists", localeIdentifier: localeIdentifier))
            try FileManager.default.removeItem(atPath: destinationApp)
        }

        logger(L10n.string("cloner.log.copyApp", localeIdentifier: localeIdentifier))
        try run("/usr/bin/ditto", ["--norsrc", "--noqtn", sourceApp, destinationApp], logger: logger)

        if let badgeIconURL {
            try installBadgeIcon(from: badgeIconURL, appPath: destinationApp)
        }
        let infoPlist = "\(destinationApp)/Contents/Info.plist"
        logger(L10n.string("cloner.log.writeInfoPlist", localeIdentifier: localeIdentifier))
        try updatePlist(
            infoPlistPath: infoPlist,
            sourceAppPath: sourceApp,
            bundleIdentifier: bundleIdentifier,
            bundleName: bundleName,
            addCloneBadge: addCloneBadge
        )
        if let telegramIdentityLabel {
            try patchTelegramIdentity(
                appPath: destinationApp,
                infoPlistPath: infoPlist,
                bundleName: bundleName,
                telegramIdentityLabel: telegramIdentityLabel
            )
        }
        if let discordUserDataPath {
            try patchPlistEnvironmentValue(
                infoPlistPath: infoPlist,
                key: "DISCORD_USER_DATA_DIR",
                value: discordUserDataPath
            )
        }

        renameElectronHelpers(
            appPath: destinationApp,
            sourceApp: sourceApp,
            newName: bundleName,
            bundleIdentifier: bundleIdentifier,
            localeIdentifier: localeIdentifier,
            logger: logger
        )
        renameMainExecutable(
            appPath: destinationApp,
            newName: bundleName,
            localeIdentifier: localeIdentifier,
            logger: logger
        )
        patchElectronAsarFuse(appPath: destinationApp, localeIdentifier: localeIdentifier, logger: logger)
        try installElectronLauncher(appPath: destinationApp, bundleIdentifier: bundleIdentifier)


        logger(L10n.string("cloner.log.clearExtendedAttributes", localeIdentifier: localeIdentifier))
        runAllowFailure(
            "/usr/bin/xattr",
            ["-cr", destinationApp],
            localeIdentifier: localeIdentifier,
            logger: logger
        )

        logger(L10n.string("cloner.log.reSign", localeIdentifier: localeIdentifier))
        try run(
            "/usr/bin/codesign",
            ["--force", "--deep", "--sign", "-", destinationApp],
            logger: logger
        )
    }

    private static func run(_ executable: String, _ arguments: [String], logger: (String) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        let command = ([executable] + arguments).joined(separator: " ")
        logger("$ \(command)")

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !output.isEmpty {
            logger(output)
        }

        guard process.terminationStatus == 0 else {
            throw AppClonerError.commandFailed(command: command, output: output)
        }
    }

    private static func appProfile(sourceApp: String, sourceBundleIdentifier: String?) -> AppCloneProfile {
        let appName = URL(fileURLWithPath: sourceApp)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()
        let bundleIdentifier = sourceBundleIdentifier?.lowercased() ?? ""
        let fingerprint = [appName, bundleIdentifier].joined(separator: " ")

        if fingerprint.contains("telegram") || fingerprint.contains("tdesktop") || fingerprint.contains("keepcoder.telegram") {
            return .telegram
        }

        if fingerprint.contains("discord") {
            return .discord
        }

        return .generic
    }

    private static func telegramIdentityLabel(bundleIdentifier: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in bundleIdentifier.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }

        let hex = String(hash, radix: 16, uppercase: false)
        let normalized = String(repeating: "0", count: max(0, 13 - hex.count)) + hex
        return "tg-\(String(normalized.prefix(13)))"
    }

    private static func discordUserDataPath(bundleIdentifier: String) -> String {
        NSHomeDirectory() + "/Library/Application Support/\(bundleIdentifier)"
    }

    private static func runAllowFailure(
        _ executable: String,
        _ arguments: [String],
        localeIdentifier: String?,
        logger: (String) -> Void
    ) {
        do {
            try run(executable, arguments, logger: logger)
        } catch {
            logger(L10n.string(
                "cloner.log.nonFatal",
                localeIdentifier: localeIdentifier,
                localizedErrorDescription(error, localeIdentifier: localeIdentifier)
            ))
        }
    }

    private static func updatePlist(
        infoPlistPath: String,
        sourceAppPath: String,
        bundleIdentifier: String,
        bundleName: String,
        addCloneBadge: Bool
    ) throws {
        let url = URL(fileURLWithPath: infoPlistPath)
        let data = try Data(contentsOf: url)

        var format = PropertyListSerialization.PropertyListFormat.xml
        guard var plist = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: &format) as? [String: Any] else {
            throw AppClonerError.invalidInfoPlist(path: infoPlistPath)
        }

        plist["CFBundleIdentifier"] = bundleIdentifier
        plist["CFBundleName"] = bundleName
        plist["CFBundleDisplayName"] = bundleName
        plist["DualSourceApplicationPath"] = sourceAppPath
        plist["DualCloneBadgeEnabled"] = addCloneBadge
        if addCloneBadge {
            plist["CFBundleIconFile"] = "DualCloneIcon.icns"
            plist.removeValue(forKey: "CFBundleIconName")
            plist.removeValue(forKey: "CFBundleIcons")
            plist.removeValue(forKey: "CFBundleIconFiles")
        }
        plist.removeValue(forKey: "ElectronAsarIntegrity")

        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
        try output.write(to: url, options: .atomic)
    }

    private static func createBadgeIcon(sourceApp: String) throws -> URL {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("dual-icon-\(UUID().uuidString)", isDirectory: true)
        let iconset = directory.appendingPathComponent("DualCloneIcon.iconset", isDirectory: true)
        try fileManager.createDirectory(at: iconset, withIntermediateDirectories: true)

        let sourceIcon = NSWorkspace.shared.icon(forFile: sourceApp)
        let variants = [
            ("icon_16x16.png", 16),
            ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32),
            ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128),
            ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256),
            ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512),
            ("icon_512x512@2x.png", 1024)
        ]

        for (filename, pixels) in variants {
            let png = try cloneBadgedPNG(sourceIcon: sourceIcon, pixels: pixels)
            try png.write(to: iconset.appendingPathComponent(filename), options: .atomic)
        }

        let output = directory.appendingPathComponent("DualCloneIcon.icns")
        try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", output.path], logger: { _ in })
        return output
    }

    private static func cloneBadgedPNG(sourceIcon: NSImage, pixels: Int) throws -> Data {
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixels,
                pixelsHigh: pixels,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ),
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw AppClonerError.commandFailed(command: "Create Clone Icon", output: "Failed to create \(pixels)px bitmap")
        }

        let size = NSSize(width: CGFloat(pixels), height: CGFloat(pixels))
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        sourceIcon.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)

        let side = CGFloat(pixels) * 0.3
        let inset = CGFloat(pixels) * 0.035
        let badgeRect = NSRect(
            x: CGFloat(pixels) - side - inset,
            y: CGFloat(pixels) - side - inset,
            width: side,
            height: side
        )
        let badge = NSBezierPath(ovalIn: badgeRect)
        NSColor.systemBlue.setFill()
        badge.fill()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        badge.lineWidth = max(1, CGFloat(pixels) * 0.018)
        badge.stroke()

        let symbolLineWidth = max(1, CGFloat(pixels) * 0.02)
        let symbolSize = side * 0.42
        let symbolOrigin = NSPoint(
            x: badgeRect.midX - symbolSize * 0.56,
            y: badgeRect.midY - symbolSize * 0.44
        )
        NSColor.white.setStroke()
        for offset in [CGFloat(0), symbolSize * 0.22] {
            let rect = NSRect(
                x: symbolOrigin.x + offset,
                y: symbolOrigin.y + offset,
                width: symbolSize * 0.78,
                height: symbolSize * 0.78
            )
            let square = NSBezierPath(roundedRect: rect, xRadius: symbolSize * 0.12, yRadius: symbolSize * 0.12)
            square.lineWidth = symbolLineWidth
            square.stroke()
        }

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AppClonerError.commandFailed(command: "Create Clone Icon", output: "Failed to encode \(pixels)px bitmap")
        }
        return png
    }

    private static func installBadgeIcon(from sourceURL: URL, appPath: String) throws {
        let resources = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let destination = resources.appendingPathComponent("DualCloneIcon.icns")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }

    private static func patchTelegramIdentity(
        appPath: String,
        infoPlistPath: String,
        bundleName: String,
        telegramIdentityLabel: String
    ) throws {
        let url = URL(fileURLWithPath: infoPlistPath)
        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.xml

        guard var plist = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: &format) as? [String: Any] else {
            throw AppClonerError.invalidInfoPlist(path: infoPlistPath)
        }

        plist["CFBundleGetInfoString"] = "\(bundleName) messaging app"
        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
        try output.write(to: url, options: .atomic)

        let binaryPath = appPath + "/Contents/MacOS/Telegram"
        try patchBinaryString(
            filePath: binaryPath,
            from: "Telegram Desktop",
            to: telegramIdentityLabel
        )
    }

    private static func patchPlistEnvironmentValue(
        infoPlistPath: String,
        key: String,
        value: String
    ) throws {
        let url = URL(fileURLWithPath: infoPlistPath)
        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.xml

        guard var plist = try PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: &format) as? [String: Any] else {
            throw AppClonerError.invalidInfoPlist(path: infoPlistPath)
        }

        var environment = plist["LSEnvironment"] as? [String: Any] ?? [:]
        environment[key] = value
        plist["LSEnvironment"] = environment

        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
        try output.write(to: url, options: .atomic)
    }

    private static func patchBinaryString(
        filePath: String,
        from: String,
        to: String
    ) throws {
        let url = URL(fileURLWithPath: filePath)
        var data = try Data(contentsOf: url)
        let fromData = Data(from.utf8)
        let toData = Data(to.utf8)

        guard fromData.count == toData.count else {
            throw AppClonerError.commandFailed(
                command: "Binary String Patch",
                output: "Replacement length mismatch"
            )
        }

        var didReplace = false
        var searchStart = data.startIndex
        while searchStart < data.endIndex,
              let range = data.range(of: fromData, in: searchStart..<data.endIndex) {
            data.replaceSubrange(range, with: toData)
            didReplace = true
            searchStart = range.lowerBound + toData.count
        }

        guard didReplace else {
            throw AppClonerError.commandFailed(
                command: "Binary String Patch",
                output: "Telegram Desktop marker not found"
            )
        }

        try data.write(to: url, options: .atomic)
    }

    /// Disable Electron's embedded ASAR integrity validation fuse.
    /// Electron apps store a fuse wire in the framework binary:
    ///   SENTINEL(32 bytes) + VERSION(1) + NUM_FUSES(1) + fuse bytes
    /// Fuse index 4 = EnableEmbeddedAsarIntegrityValidation.
    /// Flipping it from '1' to '0' prevents the SIGTRAP crash after re-signing.
    private static func patchElectronAsarFuse(
        appPath: String,
        localeIdentifier: String?,
        logger: (String) -> Void
    ) {
        let frameworksDir = appPath + "/Contents/Frameworks"
        let fm = FileManager.default

        guard let items = try? fm.contentsOfDirectory(atPath: frameworksDir) else { return }

        let sentinel = Data("dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX".utf8)

        for item in items where item.hasSuffix(".framework") {
            let name = (item as NSString).deletingPathExtension
            let candidates = [
                "\(frameworksDir)/\(item)/Versions/A/\(name)",
                "\(frameworksDir)/\(item)/\(name)"
            ]

            for binaryPath in candidates {
                guard fm.isReadableFile(atPath: binaryPath),
                      let data = try? Data(contentsOf: URL(fileURLWithPath: binaryPath), options: .mappedIfSafe)
                else { continue }

                guard let range = data.range(of: sentinel) else { continue }

                // Fuse wire: sentinel(32) + version(1) + count(1) + fuse bytes
                // Index 4 = EnableEmbeddedAsarIntegrityValidation
                let fuseOffset = range.upperBound + 2 + 4
                guard fuseOffset < data.count else { continue }

                if data[fuseOffset] == 0x31 { // ASCII '1' = enabled
                    do {
                        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: binaryPath))
                        handle.seek(toFileOffset: UInt64(fuseOffset))
                        handle.write(Data([0x30])) // ASCII '0' = disabled
                        try handle.close()
                        logger(L10n.string("cloner.log.disabledAsarValidation", localeIdentifier: localeIdentifier, name))
                    } catch {
                        logger(L10n.string(
                            "cloner.log.asarPatchFailed",
                            localeIdentifier: localeIdentifier,
                            localizedErrorDescription(error, localeIdentifier: localeIdentifier)
                        ))
                    }
                } else {
                    logger(L10n.string("cloner.log.asarAlreadyDisabled", localeIdentifier: localeIdentifier))
                }
                return
            }
        }
    }

    /// Rename the main executable to match the new bundle name.
    /// This changes the visible process name, which prevents process-name-based
    /// single-instance detection (e.g. Discord checks for a running "Discord" process).
    private static func renameMainExecutable(
        appPath: String,
        newName: String,
        localeIdentifier: String?,
        logger: (String) -> Void
    ) {
        let infoPlist = appPath + "/Contents/Info.plist"
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: infoPlist)),
            var fmt = Optional(PropertyListSerialization.PropertyListFormat.xml),
            var plist = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: &fmt) as? [String: Any],
            let originalExec = plist["CFBundleExecutable"] as? String,
            originalExec != newName
        else { return }

        let macosDir = appPath + "/Contents/MacOS"
        let oldPath = macosDir + "/" + originalExec
        let newPath = macosDir + "/" + newName

        guard FileManager.default.fileExists(atPath: oldPath) else { return }

        do {
            try FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
            plist["CFBundleExecutable"] = newName
            if let output = try? PropertyListSerialization.data(fromPropertyList: plist, format: fmt, options: 0) {
                try? output.write(to: URL(fileURLWithPath: infoPlist))
            }
            logger(L10n.string("cloner.log.helperRenamed", localeIdentifier: localeIdentifier, originalExec, newName))
        } catch {
            logger(L10n.string(
                "cloner.log.renameHelperFailed",
                localeIdentifier: localeIdentifier,
                localizedErrorDescription(error, localeIdentifier: localeIdentifier)
            ))
        }
    }

    /// Rename Electron helper apps to match the new bundle name.
    /// Electron looks for helpers by "{CFBundleName} Helper" in Frameworks/.
    private static func renameElectronHelpers(
        appPath: String,
        sourceApp: String,
        newName: String,
        bundleIdentifier: String,
        localeIdentifier: String?,
        logger: (String) -> Void
    ) {
        let sourcePlist = sourceApp + "/Contents/Info.plist"
        guard let sourceData = try? Data(contentsOf: URL(fileURLWithPath: sourcePlist)),
              let dict = try? PropertyListSerialization.propertyList(from: sourceData, options: [], format: nil) as? [String: Any],
              let originalName = dict["CFBundleName"] as? String,
              originalName != newName
        else { return }

        let frameworksDir = appPath + "/Contents/Frameworks"
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: frameworksDir) else { return }

        let prefix = originalName + " Helper"
        for item in items where item.hasPrefix(prefix) && item.hasSuffix(".app") {
            let suffix = String(item.dropFirst(originalName.count))
            let newItem = newName + suffix
            let oldPath = frameworksDir + "/" + item
            let newPath = frameworksDir + "/" + newItem

            do {
                try fm.moveItem(atPath: oldPath, toPath: newPath)
            } catch {
                logger(L10n.string(
                    "cloner.log.renameHelperFailed",
                    localeIdentifier: localeIdentifier,
                    localizedErrorDescription(error, localeIdentifier: localeIdentifier)
                ))
                continue
            }

            let oldExec = String(item.dropLast(4))
            let newExec = String(newItem.dropLast(4))
            let macosDir = newPath + "/Contents/MacOS"
            try? fm.moveItem(atPath: macosDir + "/" + oldExec, toPath: macosDir + "/" + newExec)

            let helperPlist = newPath + "/Contents/Info.plist"
            if let data = try? Data(contentsOf: URL(fileURLWithPath: helperPlist)) {
                var fmt = PropertyListSerialization.PropertyListFormat.xml
                if var plist = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainersAndLeaves, format: &fmt) as? [String: Any] {
                    plist["CFBundleExecutable"] = newExec
                    if let oldID = plist["CFBundleIdentifier"] as? String,
                       let r = oldID.range(of: ".helper") {
                        plist["CFBundleIdentifier"] = bundleIdentifier + String(oldID[r.lowerBound...])
                    }
                    if let output = try? PropertyListSerialization.data(fromPropertyList: plist, format: fmt, options: 0) {
                        try? output.write(to: URL(fileURLWithPath: helperPlist))
                    }
                }
            }
            logger(L10n.string("cloner.log.helperRenamed", localeIdentifier: localeIdentifier, item, newItem))
        }
    }

    private static func installElectronLauncher(appPath: String, bundleIdentifier: String) throws {
        guard FileManager.default.fileExists(atPath: appPath + "/Contents/Frameworks/Electron Framework.framework") else { return }
        let plist = appPath + "/Contents/Info.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: plist)),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let executable = values["CFBundleExecutable"] as? String else {
            throw AppClonerError.invalidInfoPlist(path: plist)
        }
        let binary = URL(fileURLWithPath: appPath + "/Contents/MacOS/" + executable)
        try FileManager.default.moveItem(at: binary, to: binary.appendingPathExtension("dual-original"))
        let launcher = """
        #!/bin/sh
        dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
        original=\(shellEscape(executable + ".dual-original"))
        profile=\(shellEscape(bundleIdentifier))
        exec "$dir/$original" --user-data-dir="$HOME/Library/Application Support/$profile" "$@"
        """
        try launcher.write(to: binary, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
    }

    private static func readBundleIdentifier(appPath: String) -> String? {
        let plistPath = appPath + "/Contents/Info.plist"
        guard
            let data = try? Data(contentsOf: URL(fileURLWithPath: plistPath)),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }
        return plist["CFBundleIdentifier"] as? String
    }

    private static func clearGenericCloneData(
        bundleIdentifier: String,
        localeIdentifier: String?,
        logger: (String) -> Void
    ) {
        let home = NSHomeDirectory()
        let cleanupPaths = [
            "\(home)/Library/Containers/\(bundleIdentifier)",
            "\(home)/Library/Application Scripts/\(bundleIdentifier)",
            "\(home)/Library/Preferences/\(bundleIdentifier).plist",
            "\(home)/Library/Caches/\(bundleIdentifier)",
            "\(home)/Library/Saved Application State/\(bundleIdentifier).savedState",
            "\(home)/Library/WebKit/\(bundleIdentifier)",
            "\(home)/Library/HTTPStorages/\(bundleIdentifier)"
        ]

        for path in cleanupPaths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            do {
                try FileManager.default.removeItem(atPath: path)
                logger(L10n.string("cloner.log.cleanedPath", localeIdentifier: localeIdentifier, path))
            } catch {
                logger(L10n.string(
                    "cloner.log.cleanupFailed",
                    localeIdentifier: localeIdentifier,
                    path,
                    localizedErrorDescription(error, localeIdentifier: localeIdentifier)
                ))
            }
        }
    }

    private static func clearDiscordUserData(
        bundleIdentifier: String,
        localeIdentifier: String?,
        logger: (String) -> Void
    ) {
        let path = discordUserDataPath(bundleIdentifier: bundleIdentifier)
        guard FileManager.default.fileExists(atPath: path) else { return }

        do {
            try FileManager.default.removeItem(atPath: path)
            logger(L10n.string("cloner.log.cleanedPath", localeIdentifier: localeIdentifier, path))
        } catch {
            logger(L10n.string(
                "cloner.log.cleanupFailed",
                localeIdentifier: localeIdentifier,
                path,
                localizedErrorDescription(error, localeIdentifier: localeIdentifier)
            ))
        }
    }

    private static func clearAppIsolationData(
        needles: [String],
        localeIdentifier: String?,
        logger: (String) -> Void
    ) {
        let home = NSHomeDirectory()
        let fm = FileManager.default

        let directoryRoots = [
            "\(home)/Library/Application Support",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Containers",
            "\(home)/Library/Application Scripts",
            "\(home)/Library/Caches",
            "\(home)/Library/Saved Application State",
            "\(home)/Library/WebKit",
            "\(home)/Library/HTTPStorages"
        ]

        for root in directoryRoots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items where matchesAnyNeedle(item, needles: needles) {
                let path = root + "/" + item
                do {
                    try fm.removeItem(atPath: path)
                    logger(L10n.string("cloner.log.cleanedPath", localeIdentifier: localeIdentifier, path))
                } catch {
                    logger(L10n.string(
                        "cloner.log.cleanupFailed",
                        localeIdentifier: localeIdentifier,
                        path,
                        localizedErrorDescription(error, localeIdentifier: localeIdentifier)
                    ))
                }
            }
        }

        let preferenceRoot = "\(home)/Library/Preferences"
        if let items = try? fm.contentsOfDirectory(atPath: preferenceRoot) {
            for item in items where matchesAnyNeedle(item, needles: needles) {
                let path = preferenceRoot + "/" + item
                do {
                    try fm.removeItem(atPath: path)
                    logger(L10n.string("cloner.log.cleanedPath", localeIdentifier: localeIdentifier, path))
                } catch {
                    logger(L10n.string(
                        "cloner.log.cleanupFailed",
                        localeIdentifier: localeIdentifier,
                        path,
                        localizedErrorDescription(error, localeIdentifier: localeIdentifier)
                    ))
                }
            }
        }
    }

    private static func matchesAnyNeedle(_ value: String, needles: [String]) -> Bool {
        let lowercased = value.lowercased()
        return needles.contains { lowercased.contains($0) }
    }

    private static func cloneWithAdminPrivileges(
        sourceApp: String,
        destinationApp: String,
        bundleIdentifier: String,
        bundleName: String,
        badgeIconPath: String?,
        telegramIdentityLabel: String?,
        discordUserDataPath: String?,
        logger: (String) -> Void
    ) throws {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("dual-clone-\(UUID().uuidString).sh")
        let scriptPath = scriptURL.path
        let infoPlist = destinationApp + "/Contents/Info.plist"
        let telegramPatchScript = telegramIdentityLabel.map { label in
            """
            /usr/bin/plutil -replace CFBundleGetInfoString -string \(shellEscape(bundleName + " messaging app")) \(shellEscape(infoPlist))
            /usr/bin/perl -0pi -e 's/Telegram Desktop/\(label)/g' \(shellEscape(destinationApp + "/Contents/MacOS/Telegram"))
            """
        } ?? ""
        let discordEnvironmentPatchScript = discordUserDataPath.map { path in
            """
            /usr/bin/python3 -c 'import plistlib,sys; p,k,v=sys.argv[1:4]; d=plistlib.load(open(p,"rb")); e=d.get("LSEnvironment") or {}; e[k]=v; d["LSEnvironment"]=e; h=open(p,"wb"); plistlib.dump(d,h); h.close()' \(shellEscape(infoPlist)) DISCORD_USER_DATA_DIR \(shellEscape(path))
            """
        } ?? ""
        let badgePatchScript = badgeIconPath.map { path in
            """
            /bin/mkdir -p \(shellEscape(destinationApp + "/Contents/Resources"))
            /usr/bin/ditto \(shellEscape(path)) \(shellEscape(destinationApp + "/Contents/Resources/DualCloneIcon.icns"))
            /usr/bin/plutil -replace CFBundleIconFile -string DualCloneIcon.icns \(shellEscape(infoPlist))
            /usr/bin/plutil -remove CFBundleIconName \(shellEscape(infoPlist)) 2>/dev/null || true
            /usr/bin/plutil -remove CFBundleIcons \(shellEscape(infoPlist)) 2>/dev/null || true
            /usr/bin/plutil -remove CFBundleIconFiles \(shellEscape(infoPlist)) 2>/dev/null || true
            """
        } ?? ""
        let script = """
        #!/bin/bash
        set -euo pipefail
        if [ -e \(shellEscape(destinationApp)) ]; then
          rm -rf \(shellEscape(destinationApp))
        fi
        /usr/bin/ditto --norsrc --noqtn \(shellEscape(sourceApp)) \(shellEscape(destinationApp))
        /usr/bin/plutil -replace CFBundleIdentifier -string \(shellEscape(bundleIdentifier)) \(shellEscape(infoPlist))
        /usr/bin/plutil -replace CFBundleName -string \(shellEscape(bundleName)) \(shellEscape(infoPlist))
        /usr/bin/plutil -replace CFBundleDisplayName -string \(shellEscape(bundleName)) \(shellEscape(infoPlist))
        /usr/bin/plutil -replace DualSourceApplicationPath -string \(shellEscape(sourceApp)) \(shellEscape(infoPlist))
        /usr/bin/plutil -replace DualCloneBadgeEnabled -bool \(badgeIconPath == nil ? "NO" : "YES") \(shellEscape(infoPlist))
        \(badgePatchScript)
        /usr/bin/plutil -remove ElectronAsarIntegrity \(shellEscape(infoPlist)) 2>/dev/null || true
        \(telegramPatchScript)
        \(discordEnvironmentPatchScript)
        ORIG_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" \(shellEscape(sourceApp + "/Contents/Info.plist")) 2>/dev/null || echo "")
        if [ -n "$ORIG_NAME" ] && [ "$ORIG_NAME" != \(shellEscape(bundleName)) ]; then
          FW_DIR=\(shellEscape(destinationApp))/Contents/Frameworks
          if [ -d "$FW_DIR" ]; then
            for helper in "$FW_DIR/${ORIG_NAME} Helper"*.app; do
              [ -d "$helper" ] || continue
              OLD_BASE=$(basename "$helper")
              HELPER_SUFFIX=${OLD_BASE#"$ORIG_NAME"}
              NEW_BASE=\(shellEscape(bundleName))"$HELPER_SUFFIX"
              mv "$helper" "$FW_DIR/$NEW_BASE"
              OLD_EXEC="${OLD_BASE%.app}"
              NEW_EXEC="${NEW_BASE%.app}"
              [ -f "$FW_DIR/$NEW_BASE/Contents/MacOS/$OLD_EXEC" ] && mv "$FW_DIR/$NEW_BASE/Contents/MacOS/$OLD_EXEC" "$FW_DIR/$NEW_BASE/Contents/MacOS/$NEW_EXEC"
              /usr/bin/plutil -replace CFBundleExecutable -string "$NEW_EXEC" "$FW_DIR/$NEW_BASE/Contents/Info.plist" 2>/dev/null || true
            done
          fi
        fi
        EXEC_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" \(shellEscape(infoPlist)) 2>/dev/null || echo "")
        if [ -n "$EXEC_NAME" ] && [ "$EXEC_NAME" != \(shellEscape(bundleName)) ]; then
          MACOS_DIR=\(shellEscape(destinationApp))/Contents/MacOS
          if [ -f "$MACOS_DIR/$EXEC_NAME" ]; then
            mv "$MACOS_DIR/$EXEC_NAME" \(shellEscape(destinationApp + "/Contents/MacOS/" + bundleName))
            /usr/bin/plutil -replace CFBundleExecutable -string \(shellEscape(bundleName)) \(shellEscape(infoPlist)) 2>/dev/null || true
          fi
        fi
        /usr/bin/perl -e '
        my $dest = $ARGV[0];
        my $sentinel = "dL7pKGdnNz796PbbjQWNKmHXBZaB9tsX";
        opendir(my $dh, "$dest/Contents/Frameworks") or exit 0;
        my @fws = grep { /\\.framework$/ } readdir($dh);
        closedir($dh);
        for my $fw (@fws) {
            (my $name = $fw) =~ s/\\.framework$//;
            for my $bp ("$dest/Contents/Frameworks/$fw/Versions/A/$name", "$dest/Contents/Frameworks/$fw/$name") {
                next unless -f $bp;
                open(my $fh, "+<:raw", $bp) or next;
                local $/;
                my $data = <$fh>;
                my $idx = index($data, $sentinel);
                next if $idx < 0;
                my $pos = $idx + length($sentinel) + 2 + 4;
                if ($pos < length($data) && substr($data, $pos, 1) eq "1") {
                    seek($fh, $pos, 0);
                    print $fh "0";
                }
                close($fh);
                exit 0;
            }
        }
        ' \(shellEscape(destinationApp)) 2>/dev/null || true
        if [ -d \(shellEscape(destinationApp + "/Contents/Frameworks/Electron Framework.framework")) ]; then
          EXEC_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" \(shellEscape(infoPlist)))
          MACOS_DIR=\(shellEscape(destinationApp + "/Contents/MacOS"))
          mv "$MACOS_DIR/$EXEC_NAME" "$MACOS_DIR/$EXEC_NAME.dual-original"
          printf '#!/bin/sh\\ndir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\\noriginal=%q\\nprofile=%q\\nexec "$dir/$original" --user-data-dir="$HOME/Library/Application Support/$profile" "$@"\\n' "$EXEC_NAME.dual-original" \(shellEscape(bundleIdentifier)) > "$MACOS_DIR/$EXEC_NAME"
          chmod 755 "$MACOS_DIR/$EXEC_NAME"
        fi
        /usr/bin/xattr -cr \(shellEscape(destinationApp)) >/dev/null 2>&1 || true
        /usr/bin/codesign --force --deep --sign - \(shellEscape(destinationApp))
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: scriptPath) }
        try run("/bin/chmod", ["+x", scriptPath], logger: logger)

        let osascriptCommand = "do shell script \(appleScriptString("/bin/bash \(scriptPath)")) with administrator privileges"
        logger("$ /usr/bin/osascript -e [administrator privileges script]")

        do {
            try run("/usr/bin/osascript", ["-e", osascriptCommand], logger: logger)
        } catch let error as AppClonerError {
            if case let .commandFailed(_, output) = error,
               isAdminAuthorizationCancelled(output: output) {
                throw AppClonerError.adminPrivilegeCancelled
            }
            if case let .commandFailed(_, output) = error,
               isAdminAuthenticationFailure(output: output) {
                throw AppClonerError.adminAuthenticationFailed
            }
            throw error
        }
    }

    private static func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func isAdminAuthorizationCancelled(output: String) -> Bool {
        let lowercased = output.lowercased()
        return lowercased.contains("user canceled") ||
            lowercased.contains("canceled") ||
            output.contains("用户已取消") ||
            output.contains("已取消")
    }

    private static func isAdminAuthenticationFailure(output: String) -> Bool {
        let lowercased = output.lowercased()
        return lowercased.contains("password") ||
            lowercased.contains("authentication") ||
            lowercased.contains("not authorized") ||
            output.contains("用户名或密码不正确") ||
            output.contains("认证失败") ||
            output.contains("授权失败") ||
            output.contains("(-60005)")
    }

    private static func localizedErrorDescription(_ error: Error, localeIdentifier: String?) -> String {
        if let appError = error as? AppClonerError {
            return appError.localizedDescription(localeIdentifier: localeIdentifier)
        }
        return error.localizedDescription
    }
}

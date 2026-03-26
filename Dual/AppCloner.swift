//
//  AppCloner.swift
//  Dual
//
//  Created by Codex on 2026/3/23.
//

import Foundation

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

enum AppCloner {
    static func clone(
        sourceApp: String,
        destinationApp: String,
        bundleIdentifier: String,
        bundleName: String,
        clearDataBeforeClone: Bool,
        useAdminPrivileges: Bool,
        localeIdentifier: String?,
        logger: @escaping (String) -> Void
    ) async throws {
        logger(L10n.string("cloner.log.started", localeIdentifier: localeIdentifier))
        logger(L10n.string("cloner.log.source", localeIdentifier: localeIdentifier, sourceApp))
        logger(L10n.string("cloner.log.destination", localeIdentifier: localeIdentifier, destinationApp))

        if let sourceBundleID = readBundleIdentifier(appPath: sourceApp), sourceBundleID == bundleIdentifier {
            throw AppClonerError.commandFailed(
                command: "BundleID Check",
                output: L10n.string("cloner.error.bundleIdMatchesSource", localeIdentifier: localeIdentifier, sourceBundleID)
            )
        }

        if clearDataBeforeClone {
            logger(L10n.string("cloner.log.clearingData", localeIdentifier: localeIdentifier))
            clearCloneData(bundleIdentifier: bundleIdentifier, localeIdentifier: localeIdentifier, logger: logger)
        }

        if useAdminPrivileges {
            logger(L10n.string("cloner.log.usingAdmin", localeIdentifier: localeIdentifier))
            try cloneWithAdminPrivileges(
                sourceApp: sourceApp,
                destinationApp: destinationApp,
                bundleIdentifier: bundleIdentifier,
                bundleName: bundleName,
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

        let infoPlist = "\(destinationApp)/Contents/Info.plist"
        logger(L10n.string("cloner.log.writeInfoPlist", localeIdentifier: localeIdentifier))
        try updatePlist(infoPlistPath: infoPlist, bundleIdentifier: bundleIdentifier, bundleName: bundleName)

        renameElectronHelpers(
            appPath: destinationApp,
            sourceApp: sourceApp,
            newName: bundleName,
            bundleIdentifier: bundleIdentifier,
            localeIdentifier: localeIdentifier,
            logger: logger
        )
        patchElectronAsarFuse(appPath: destinationApp, localeIdentifier: localeIdentifier, logger: logger)

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
        bundleIdentifier: String,
        bundleName: String
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
        plist.removeValue(forKey: "ElectronAsarIntegrity")

        let output = try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
        try output.write(to: url, options: .atomic)
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

    private static func clearCloneData(
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

    private static func cloneWithAdminPrivileges(
        sourceApp: String,
        destinationApp: String,
        bundleIdentifier: String,
        bundleName: String,
        logger: (String) -> Void
    ) throws {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("dual-clone-\(UUID().uuidString).sh")
        let scriptPath = scriptURL.path
        let infoPlist = destinationApp + "/Contents/Info.plist"
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
        /usr/bin/plutil -remove ElectronAsarIntegrity \(shellEscape(infoPlist)) 2>/dev/null || true
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

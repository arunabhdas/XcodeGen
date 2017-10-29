//
//  SpecValidation.swift
//  XcodeGenKit
//
//  Created by Yonas Kolb on 24/9/17.
//

import Foundation
import PathKit

extension ProjectSpec {

    public func validate() throws {

        var errors: [SpecValidationError.ValidationError] = []

        func validateSettings(_ settings: Settings) -> [SpecValidationError.ValidationError] {
            var errors: [SpecValidationError.ValidationError] = []
            for group in settings.groups {
                if let settings = settingGroups[group] {
                    errors += validateSettings(settings)
                } else {
                    errors.append(.invalidSettingsGroup(group))
                }
            }
            for config in settings.configSettings.keys {
                if !configs.contains(where: { $0.name.lowercased().contains(config.lowercased())}) {
                    errors.append(.invalidBuildSettingConfig(config))
                }
            }
            return errors
        }

        errors += validateSettings(settings)

        for fileGroup in fileGroups {
            if !(basePath + fileGroup).exists {
                errors.append(.invalidFileGroup(fileGroup))
            }
        }

        for (config, configFile) in configFiles {
            if !(basePath + configFile).exists {
                errors.append(.invalidConfigFile(configFile: configFile, config: config))
            }
            if getConfig(config) == nil {
                errors.append(.invalidConfigFileConfig(config))
            }
        }

        for settings in settingGroups.values {
            errors += validateSettings(settings)
        }

        for target in targets {
            for dependency in target.dependencies {
                if dependency.type == .target, getTarget(dependency.reference) == nil {
                    errors.append(.invalidTargetDependency(target: target.name, dependency: dependency.reference))
                }
            }

            for (config, configFile) in target.configFiles {
                if !(basePath + configFile).exists {
                    errors.append(.invalidTargetConfigFile(target: target.name, configFile: configFile, config: config))
                }
                if getConfig(config) == nil {
                    errors.append(.invalidConfigFileConfig(config))
                }
            }

            for source in target.sources {
                let sourcePath = basePath + source
                if !sourcePath.exists {
                    errors.append(.missingTargetSource(target: target.name, source: sourcePath.string))
                }
            }

            if let scheme = target.scheme {

                for configVariant in scheme.configVariants {
                    if !configs.contains(where: { $0.name.contains(configVariant) && $0.type == .debug }) {
                        errors.append(.invalidTargetSchemeConfigVariant(target: target.name, configVariant: configVariant, configType: .debug))
                    }
                    if !configs.contains(where: { $0.name.contains(configVariant) && $0.type == .release }) {
                        errors.append(.invalidTargetSchemeConfigVariant(target: target.name, configVariant: configVariant, configType: .release))
                    }
                }

                if scheme.configVariants.isEmpty {
                    if !configs.contains(where: { $0.type == .debug }) {
                        errors.append(.missingConfigTypeForGeneratedTargetScheme(target: target.name, configType: .debug))
                    }
                    if !configs.contains(where: { $0.type == .release }) {
                        errors.append(.missingConfigTypeForGeneratedTargetScheme(target: target.name, configType: .release))
                    }
                }

                for testTarget in scheme.testTargets {
                    if getTarget(testTarget) == nil {
                        errors.append(.invalidTargetSchemeTest(target: target.name, testTarget: testTarget))
                    }
                }
            }

            let scripts = target.prebuildScripts + target.postbuildScripts
            for script in scripts {
                if case let .path(pathString) = script.script {
                    let scriptPath = basePath + pathString
                    if !scriptPath.exists {
                        errors.append(.invalidBuildScriptPath(target: target.name, name: script.name, path: pathString))
                    }
                }
            }

            errors += validateSettings(target.settings)
        }

        for scheme in schemes {
            for buildTarget in scheme.build.targets {
                if getTarget(buildTarget.target) == nil {
                    errors.append(.invalidSchemeTarget(scheme: scheme.name, target: buildTarget.target))
                }
            }
            if let buildAction = scheme.run, getConfig(buildAction.config) == nil {
                errors.append(.invalidSchemeConfig(scheme: scheme.name, config: buildAction.config))
            }
            if let buildAction = scheme.test, getConfig(buildAction.config) == nil {
                errors.append(.invalidSchemeConfig(scheme: scheme.name, config: buildAction.config))
            }
            if let buildAction = scheme.profile, getConfig(buildAction.config) == nil {
                errors.append(.invalidSchemeConfig(scheme: scheme.name, config: buildAction.config))
            }
            if let buildAction = scheme.analyze, getConfig(buildAction.config) == nil {
                errors.append(.invalidSchemeConfig(scheme: scheme.name, config: buildAction.config))
            }
            if let buildAction = scheme.archive, getConfig(buildAction.config) == nil {
                errors.append(.invalidSchemeConfig(scheme: scheme.name, config: buildAction.config))
            }
        }

        if !errors.isEmpty {
            throw SpecValidationError(errors: errors)
        }
    }
}

public struct SpecValidationError: Error, CustomStringConvertible {

    public var errors: [ValidationError]

    public enum ValidationError: Error, CustomStringConvertible {
        case invalidTargetDependency(target: String, dependency: String)
        case missingTargetSource(target: String, source: String)
        case invalidTargetConfigFile(target: String, configFile: String, config: String)
        case invalidTargetSchemeConfigVariant(target: String, configVariant: String, configType: ConfigType)
        case invalidTargetSchemeTest(target: String, testTarget: String)
        case invalidSchemeTarget(scheme: String, target: String)
        case invalidSchemeConfig(scheme: String, config: String)
        case invalidConfigFile(configFile: String, config: String)
        case invalidBuildSettingConfig(String)
        case invalidSettingsGroup(String)
        case invalidBuildScriptPath(target: String, name: String?, path: String)
        case invalidFileGroup(String)
        case invalidConfigFileConfig(String)
        case missingConfigTypeForGeneratedTargetScheme(target: String, configType: ConfigType)

        public var description: String {
            switch self {
            case let .invalidTargetDependency(target, dependency): return "Target \(target.quoted) has invalid dependency: \(dependency.quoted)"
            case let .invalidTargetConfigFile(target, configFile, config): return "Target \(target.quoted) has invalid config file \(configFile.quoted) for config \(config.quoted)"
            case let .missingTargetSource(target, source): return "Target \(target.quoted) has a missing source directory \(source.quoted)"
            case let .invalidTargetSchemeConfigVariant(target, configVariant, configType): return "Target \(target.quoted) has an invalid scheme config variant which requires a config that has a \(configType.rawValue.quoted) type and contains the name \(configVariant.quoted)"
            case let .invalidTargetSchemeTest(target, test): return "Target \(target.quoted) scheme has invalid test \(test.quoted)"
            case let .invalidConfigFile(configFile, config): return "Invalid config file \(configFile.quoted) for config \(config.quoted)"
            case let .invalidSchemeTarget(scheme, target): return "Scheme \(scheme.quoted) has invalid build target \(target.quoted)"
            case let .invalidSchemeConfig(scheme, config): return "Scheme \(scheme.quoted) has invalid build configuration \(config.quoted)"
            case let .invalidBuildSettingConfig(config): return "Build setting has invalid build configuration \(config.quoted)"
            case let .invalidSettingsGroup(group): return "Invalid settings group \(group.quoted)"
            case let .invalidBuildScriptPath(target, name, path): return "Target \(target.quoted) has a script \(name != nil ? "\(name!.quoted) which has a " : "")path that doesn't exist \(path.quoted)"
            case let .invalidFileGroup(group): return "Invalid file group \(group.quoted)"
            case let .invalidConfigFileConfig(config): return "Config file has invalid config \(config.quoted)"
            case let .missingConfigTypeForGeneratedTargetScheme(target, configType): return "Target \(target.quoted) is missing a config of type \(configType.rawValue) to generate its scheme"
            }
        }
    }

    public var description: String {
        let title: String
        if errors.count == 1 {
            title = "Spec validation error: "
        } else {
            title = "\(errors.count) Spec validations errors:\n\t- "
        }
        return "\(title)" + errors.map { $0.description }.joined(separator: "\n\t- ")
    }
}
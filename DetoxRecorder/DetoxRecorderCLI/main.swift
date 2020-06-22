//
//  main.swift
//  DetoxRecorderCLI
//
//  Created by Leo Natan (Wix) on 5/27/20.
//  Copyright © 2020 Wix. All rights reserved.
//

import Foundation

LNUsageSetUtilName("detox recorder")

LNUsageSetIntroStrings([
	"Records UI interaction steps into a Detox test.",
	"",
	"After recording the test, add assertions that check if interface elements are in the expected state.",
	"",
	"If no app or simulator information is provided, the package.json will be used for obtaining the appropriate information."])

LNUsageSetExampleStrings([
	"detox recorder --bundleId \"com.example.myApp\" --simulatorId \"69D91B05-64F4-497B-A2FC-9A109B310F38\" --outputTestFile \"~/Desktop/RecordedTest.js\" --testName \"My Recorded Test\" --record",
	"detox recorder --configuration \"ios.sim.release\" --record"
])

LNUsageSetOptions([
	LNUsageOption(name: "record", shortcut: "r", valueRequirement: .none, description: "Start recording"),
	LNUsageOption(name: "outputTestFile", shortcut: "o", valueRequirement: .required, description: "The output file (required)"),
	LNUsageOption(name: "testName", shortcut: "n", valueRequirement: .required, description: "The test name (optional)"),
	LNUsageOption.empty(),
	LNUsageOption(name: "configuration", shortcut: "c", valueRequirement: .required, description: "The Detox configuration to use (optional, required if either app or simulator information is not provided"),
	LNUsageOption.empty(),
	LNUsageOption(name: "bundleId", shortcut: "b", valueRequirement: .required, description: "The app bundle identifier of an existing app to record (optional)"),
	LNUsageOption.empty(),
	LNUsageOption(name: "simulatorId", shortcut: "s", valueRequirement: .required, description: "The simulator identifier to use for recording (optional)"),
])

LNUsageSetHiddenOptions([
	LNUsageOption(name: "noExit", shortcut: "no", valueRequirement: .none, description: "Do not exit the app after completing the test recording"),
	LNUsageOption(name: "noInsertLibraries", shortcut: "no2", valueRequirement: .none, description: "Do not use DYLD_INSERT_LIBRARIES for injecting the Detox Recorder framework; the app is responsible for loading the framework"),
	LNUsageOption(name: "recorderFrameworkPath", shortcut: "fpath", valueRequirement: .required, description: "The Detox Recorder path to use, rather than the default"),
])

extension String: LocalizedError {
    public var errorDescription: String? { return self }
	
	func capitalizingFirstLetter() -> String {
		return prefix(1).capitalized + dropFirst()
	}
	
	mutating func capitalizeFirstLetter() {
		self = self.capitalizingFirstLetter()
	}
}

extension Process {
	var simctlArguments: [String]? {
		get {
			return Array(arguments![1..<arguments!.count])
		}
		set(simctlArguments) {
			var arguments = ["simctl"]
			if let simctlArguments = simctlArguments {
				arguments.append(contentsOf: simctlArguments)
			}
			
			self.arguments = arguments
		}
	}
	
	@discardableResult
	func launchAndWaitUntilExitAndReturnOutput() throws -> String {
		let out = Pipe()
		let err = Pipe()
		standardOutput = out
		standardError = err
		
		launch()
		
		let errFileHandle = err.fileHandleForReading
		let readFileHandle = out.fileHandleForReading
		let error = String(data: errFileHandle.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .newlines)
		let response = String(data: readFileHandle.readDataToEndOfFile(), encoding: .utf8)!.trimmingCharacters(in: .newlines)

		waitUntilExit()
		
		if(terminationStatus != 0) {
			throw error
		}
		
		return response
	}
}

class DetoxRecorderCLI
{
	static let detoxPackageJson : [String: Any] = {
		let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("package.json")
		do {
			let data = try Data(contentsOf: url)
			let jsonObj = try JSONSerialization.jsonObject(with: data, options: [])
			
			guard let dict = jsonObj as? [String: Any] else {
				throw "Unknown package.json file format."
			}
			
			guard let detox = dict["detox"] as? [String: Any] else {
				throw "Unable to find “detox” object in package.json."
			}
			
			return detox
		} catch {
			LNUsagePrintMessageAndExit(prependMessage: error.localizedDescription, logLevel: .error)
		}
	}()
	
	static func detoxConfig(_ configName: String) -> [String: Any] {
		guard let configs = DetoxRecorderCLI.detoxPackageJson["configurations"] as? [String: Any] else {
			LNUsagePrintMessageAndExit(prependMessage: "Key “configurations” is not found or unreadable in package.json", logLevel: .error)
		}
		
		guard let config = configs[configName] as? [String: Any] else {
			LNUsagePrintMessageAndExit(prependMessage: "Configuration “\(configName)” is not found or unreadable in package.json", logLevel: .error)
		}
		
		return config
	}
}

func whichURLFor(binaryName: String) throws -> URL {
	let whichProcess = Process()
	whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
	whichProcess.arguments = [binaryName]
	
	let response = (try? whichProcess.launchAndWaitUntilExitAndReturnOutput()) ?? ""
	if response.count == 0 {
		throw "\(binaryName) not found"
	}
	
	return URL(fileURLWithPath: response)
}

func xcrunSimctlProcess() -> Process {
	let xcrunSimctlProcess = Process()
	xcrunSimctlProcess.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
	do {
		xcrunSimctlProcess.executableURL = try whichURLFor(binaryName: "xcrun")
	} catch {
		LNUsagePrintMessageAndExit(prependMessage: "Xcode not installed.", logLevel: .error)
	}
	xcrunSimctlProcess.arguments = ["simctl"]
	return xcrunSimctlProcess
}

func applesimutilsProcess() -> Process {
	let applesimutilsProcess = Process()
//	do {
	applesimutilsProcess.executableURL = URL(fileURLWithPath: "/usr/local/bin/applesimutils") //try whichURLFor(binaryName: "applesimutils")
//	} catch {
//		LNUsagePrintMessageAndExit(prependMessage: "applesimutils is not installed", logLevel: .error)
//	}
	return applesimutilsProcess
}

func prepareappBundleId(bundleId: String?, config: String?, simulatorId: String) -> String {
	if let bundleId = bundleId {
		return bundleId
	} else {
		guard let appPath = DetoxRecorderCLI.detoxConfig(config!)["binaryPath"] as? String else {
			LNUsagePrintMessageAndExit(prependMessage: "Key “binaryPath” either not found or in unsupported format as found in package.json for the “\(config!)” configuration", logLevel: .error)
		}
		
		guard FileManager.default.fileExists(atPath: appPath) else {
			LNUsagePrintMessageAndExit(prependMessage: "Key “binaryPath” points to a path that does not exist", logLevel: .error)
		}
		
		let simctlInstall = xcrunSimctlProcess()
		simctlInstall.simctlArguments = ["install", simulatorId, appPath]
		do {
			_ = try simctlInstall.launchAndWaitUntilExitAndReturnOutput()
		} catch {
			LNUsagePrintMessageAndExit(prependMessage: "Failed installing app: \(error.localizedDescription)", logLevel: .error)
		}
		
		guard let data = try? Data(contentsOf: URL(fileURLWithPath: appPath).appendingPathComponent("Info.plist")), let infoPlist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
			LNUsagePrintMessageAndExit(prependMessage: "Unable to read the app's Info.plist", logLevel: .error)
		}
		
		guard let foundBundleId = infoPlist["CFBundleIdentifier"] as? String else {
			LNUsagePrintMessageAndExit(prependMessage: "Unable to find “CFBundleIdentifier” key in the app's Info.plist", logLevel: .error)
		}
		
		return foundBundleId
	}
}

func ensureSimulatorBooted(_ simulatorId: String) {
	let process = applesimutilsProcess()
	process.arguments = ["--list", "--byId", simulatorId]
	let jsonString = try? process.launchAndWaitUntilExitAndReturnOutput()
	let object : [[String: Any]]
	do {
		guard let jsonString = jsonString, let data = jsonString.data(using: .utf8) else {
			throw "err"
		}
		
		object = try JSONSerialization.jsonObject(with: data, options: []) as! [[String: Any]]
	} catch {
		LNUsagePrintMessageAndExit(prependMessage: "applesimutils failed obtaining information about the simulator.", logLevel: .error)
	}
	
	guard let device = object.first else {
		LNUsagePrintMessageAndExit(prependMessage: "No device found with simulator identifier \(simulatorId).", logLevel: .error)
	}
		
	if device["state"]! as! String != "Booted" {
		let bootProcess = xcrunSimctlProcess()
		bootProcess.simctlArguments = ["boot", simulatorId]
		bootProcess.launch()
		bootProcess.waitUntilExit()
	}
}

func prepareSimulatorId(simulatorId: String?, config: String?) -> String {
	if let simulatorId = simulatorId {
		ensureSimulatorBooted(simulatorId)
		return simulatorId
	}
	
	guard let deviceJson = DetoxRecorderCLI.detoxConfig(config!)["device"] as? [String: String] else {
		LNUsagePrintMessageAndExit(prependMessage: "Key “device” either not found or in unsupported format as found in package.json for the “\(config!)” configuration", logLevel: .error)
	}
	
	var arguments: [String] = ["--list"]
	deviceJson.forEach { key, value in
		arguments.append("--by\(key.capitalizingFirstLetter())")
		arguments.append(value)
	}
	
	let process = applesimutilsProcess()
	process.arguments = arguments
	let listResponseJson = (try? process.launchAndWaitUntilExitAndReturnOutput()) ?? ""
	guard let listResponse = try? JSONSerialization.jsonObject(with: listResponseJson.data(using: .utf8)!, options: []) as? [[String: Any]], listResponse.count != 0 else {
		LNUsagePrintMessageAndExit(prependMessage: "Unable to find simulator as described in package.json for the “\(config!)” configuration", logLevel: .error)
	}
	
	guard listResponse.count == 1 else {
		LNUsagePrintMessageAndExit(prependMessage: "Multiple simulators matched to description in package.json for the “\(config!)” configuration; ensure a more specific query", logLevel: .error)
	}
	
	guard let simulator = listResponse.first, let foundSimId = simulator["udid"] as? String else {
		LNUsagePrintMessageAndExit(prependMessage: "Unabled to parse simulator data returned from applesimutils", logLevel: .error)
	}
	
	ensureSimulatorBooted(foundSimId)
	return foundSimId
}

let parser = LNUsageParseArguments()

guard parser.object(forKey: "record") != nil else {
	LNUsagePrintMessageAndExit(prependMessage: nil, logLevel: .stdOut)
}

let bundleId = parser.object(forKey: "bundleId") as? String
let simId = parser.object(forKey: "simulatorId") as? String

let config = parser.object(forKey: "configuration") as? String

guard (bundleId != nil && simId != nil) || config != nil else {
	if bundleId == nil && config == nil {
		LNUsagePrintMessageAndExit(prependMessage: "You must either provide an app bundle identifier or a Detox configuration.", logLevel: .error)
	}
	
	if simId == nil && config == nil {
		LNUsagePrintMessageAndExit(prependMessage: "You must either provide a simulator identifier or a Detox configuration.", logLevel: .error)
	}
	
	LNUsagePrintMessageAndExit(prependMessage: "Bloop‽", logLevel: .error)
}

guard let outputTestFile = parser.object(forKey: "outputTestFile") as? String else {
	LNUsagePrintMessageAndExit(prependMessage: "You must provide an output test file path.", logLevel: .error)
}

let simulatorId = prepareSimulatorId(simulatorId: simId, config: config)
let appBundleId = prepareappBundleId(bundleId: bundleId, config: config, simulatorId: simulatorId)

var args = ["launch", simulatorId, appBundleId, "-DTXRecStartRecording", "1", "-DTXRecTestOutputPath", outputTestFile]

if let testName = parser.object(forKey: "testName") as? String {
	args.append(contentsOf: ["-DTXRecTestName", testName])
}

if parser.bool(forKey: "noExit") {
	args.append(contentsOf: ["-DTXRecNoExit", "1"])
}

let terminateProcess = xcrunSimctlProcess()
terminateProcess.simctlArguments = ["terminate", simulatorId, appBundleId]

_ = try? terminateProcess.launchAndWaitUntilExitAndReturnOutput()

let recordProcess = xcrunSimctlProcess()
recordProcess.simctlArguments = args
if parser.bool(forKey: "noInsertLibraries") {
	recordProcess.environment = [:]
} else {
	let frameworkUrl : URL
	if let frameworkOverridePath = parser.object(forKey: "recorderFrameworkPath") as? String {
		frameworkUrl = URL(fileURLWithPath: frameworkOverridePath, isDirectory: true)
	} else {
		frameworkUrl = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("DetoxRecorder.framework/")
	}
	recordProcess.environment = ["SIMCTL_CHILD_DYLD_INSERT_LIBRARIES": frameworkUrl.appendingPathComponent("DetoxRecorder").standardized.path]
}

do {
	try recordProcess.launchAndWaitUntilExitAndReturnOutput()
} catch {
	LNUsagePrintMessageAndExit(prependMessage: "Failed starting recording: \(error.localizedDescription)", logLevel: .error)
}

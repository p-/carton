// Copyright 2020 Carton contributors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import CartonHelpers
import SwiftToolchain
import TSCBasic

public enum Templates: String, CaseIterable {
  case basic
  case tokamak

  public var template: Template.Type {
    switch self {
    case .basic: return Basic.self
    case .tokamak: return Tokamak.self
    }
  }
}

public protocol Template {
  static var description: String { get }
  static func create(
    on fileSystem: FileSystem,
    project: Project,
    _ terminal: InteractiveWriter
  ) async throws
}

enum TemplateError: Error {
  case notImplemented
}

struct PackageDependency: CustomStringConvertible {
  let url: String
  let version: Version

  enum Version: CustomStringConvertible {
    case from(String)
    case branch(String)
    var description: String {
      switch self {
      case let .from(min):
        return #"from: "\#(min)""#
      case let .branch(branch):
        return #".branch("\#(branch)")"#
      }
    }
  }

  var description: String {
    #".package(url: "\#(url)", \#(version))"#
  }
}

struct TargetDependency: CustomStringConvertible {
  let name: String
  let package: String
  var description: String {
    #".product(name: "\#(name)", package: "\#(package)")"#
  }
}

extension Template {
  static func createPackage(
    type: PackageType,
    fileSystem: FileSystem,
    project: Project,
    _ terminal: InteractiveWriter
  ) async throws {
    try await Toolchain(fileSystem, terminal)
      .runPackageInit(name: project.name, type: type, inPlace: project.inPlace)
  }

  static func createManifest(
    fileSystem: FileSystem,
    project: Project,
    platforms: [String] = [],
    dependencies: [PackageDependency] = [],
    targetDepencencies: [TargetDependency] = [],
    _ terminal: InteractiveWriter
  ) throws {
    try fileSystem.writeFileContents(project.path.appending(component: "Package.swift")) {
      var content = """
      // swift-tools-version:5.6
      import PackageDescription
      let package = Package(
          name: "\(project.name)",\n
      """
      if !platforms.isEmpty {
        content += "    platforms: [\(platforms.joined(separator: ", "))],\n"
      }
      content += """
          products: [
              .executable(name: "\(project.name)", targets: ["\(project.name)"])
          ],
          dependencies: [
              \(dependencies.map(\.description).joined(separator: ",\n"))
          ],
          targets: [
              .executableTarget(
                  name: "\(project.name)",
                  dependencies: [
                      \(targetDepencencies.map(\.description).joined(separator: ",\n"))
                  ]),
              .testTarget(
                  name: "\(project.name)Tests",
                  dependencies: ["\(project.name)"]),
          ]
      )
      """
      content.write(to: $0)
    }
  }
}

// MARK: Templates

extension Templates {
  struct Basic: Template {
    static let description: String = "A simple SwiftWasm project."

    static func create(
      on fileSystem: FileSystem,
      project: Project,
      _ terminal: InteractiveWriter
    ) async throws {
      try fileSystem.changeCurrentWorkingDirectory(to: project.path)
      try await createPackage(type: .executable, fileSystem: fileSystem, project: project, terminal)
      try createManifest(
        fileSystem: fileSystem,
        project: project,
        dependencies: [
          .init(
            url: "https://github.com/swiftwasm/JavaScriptKit",
            version: .from(compatibleJSKitVersion.description)
          ),
        ],
        targetDepencencies: [
          .init(name: "JavaScriptKit", package: "JavaScriptKit"),
        ],
        terminal
      )
    }
  }
}

extension Templates {
  struct Tokamak: Template {
    static let description: String = "A simple Tokamak project."

    static func create(
      on fileSystem: FileSystem,
      project: Project,
      _ terminal: InteractiveWriter
    ) async throws {
      try fileSystem.changeCurrentWorkingDirectory(to: project.path)
      try await createPackage(type: .executable,
                        fileSystem: fileSystem,
                        project: project,
                        terminal)
      try createManifest(
        fileSystem: fileSystem,
        project: project,
        platforms: [".macOS(.v11)", ".iOS(.v13)"],
        dependencies: [
          .init(
            url: "https://github.com/TokamakUI/Tokamak",
            version: .from("0.11.0")
          ),
        ],
        targetDepencencies: [
          .init(name: "TokamakShim", package: "Tokamak"),
        ],
        terminal
      )

      let sources = project.path.appending(
        components: "Sources",
        project.name
      )

      for source in try fileSystem.getDirectoryContents(sources) {
        try fileSystem.removeFileTree(sources.appending(components: source))
      }

      try fileSystem.writeFileContents(sources.appending(components: "App.swift")) {
        """
        import TokamakDOM

        @main
        struct TokamakApp: App {
            var body: some Scene {
                WindowGroup("Tokamak App") {
                    ContentView()
                }
            }
        }

        struct ContentView: View {
            var body: some View {
                Text("Hello, world!")
            }
        }
        """
        .write(to: $0)
      }
    }
  }
}

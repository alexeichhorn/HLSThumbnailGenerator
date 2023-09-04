// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "HLSThumbnailGenerator",
	platforms: [.iOS("15.0")],
	products: [
		// Products define the executables and libraries a package produces, and make them visible to other packages.
		.library(
			name: "HLSThumanailGenerator",
			targets: ["HLSThumbnailGenerator"]),
	],
	targets: [
		.target(name: "HLSThumbnailGenerator")
	]
)

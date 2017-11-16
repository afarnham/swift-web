import HttpPipeline
import HttpPipelineTestSupport
import Optics
import Prelude
import SnapshotTesting
import XCTest

final class UrlFormEncoderTests: XCTestCase {
  func testEncoding_DeepObject() {
    assertSnapshot(
      matching: urlFormEncode(
        value: [
          "id": 42,
          "name": "Blob McBlob",
          "bio": "!*'();:@&=+$,/?%#[] ^",
          "favorite_colors": ["blue", "green"],
          "location": [
            "id": 12,
            "name": "Brooklyn",
            "neighborhoods": [
              ["id": 2, "name": "Williamsburg"],
              ["id": 3, "name": "Bed-Stuy"],
            ]
          ]
        ]
        )
        .sortedByFormEncdedKey()
    )
  }

  func testEncoding_Emtpy() {
    assertSnapshot(
      matching: urlFormEncode(
        value: [
          "id": 42,
          "name": "Blob McBlob",
          "empty_array": [],
          "empty_object": [:],
          ]
        )
        .sortedByFormEncdedKey()
    )
  }

  func testEncoding_RootArray_SimpleObjects() {
    assertSnapshot(
      matching: urlFormEncode(
        values: ["Functions & Purity", "Monoids", "Applicatives"],
        rootKey: "episodes"
        )
        .sortedByFormEncdedKey()
    )
  }

  func testEncoding_DoubleArray() {
    assertSnapshot(
      matching: urlFormEncode(
        values: [
          ["Functions", "Purity"],
          ["Semigroups", "Monoids"],
          ["Applicatives", "Monads"]
        ],
        rootKey: "episodes"
        )
        .sortedByFormEncdedKey()
    )
  }

  func testEncodingCodable() {
    let episode = EpisodeModel(
      id: 100, title: "Introduction to Functions",
      blurb: "Everything you wanted to know about functions.",
      categories: ["Functions", "Composition", "Curry"]
    )

    assertSnapshot(
      matching: urlFormEncode(value: episode)
        .sortedByFormEncdedKey()
    )
  }
}

private extension String {
  /// Helper to make sure that form encoded strings are in a well-defined order.
  /// TODO: need a more robust solution since key/value pairs inside this string should be order sensitive.
  func sortedByFormEncdedKey() -> String {
    return self.split(separator: "&")
      .sorted()
      .joined(separator: "&\n")
  }
}

private struct EpisodeModel: Codable {
  let id: Int
  let title: String
  let blurb: String
  let categories: [String]
}
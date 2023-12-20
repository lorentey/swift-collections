//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Collections open source project
//
// Copyright (c) 2022 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

#if !COLLECTIONS_SINGLE_MODULE
import _CollectionsUtilities
#endif

extension BitSet: _SortedCollection {
  /// Returns the current set (already sorted).
  ///
  /// - Complexity: O(1)
  public func sorted() -> BitSet { self }

  /// Returns the minimum element in this set.
  ///
  /// Bit sets are sorted, so the minimum element is always at the first
  /// position in the set.
  ///
  /// - Returns: The bit set's minimum element. If the sequence has no
  ///   elements, returns `nil`.
  ///
  /// - Complexity: O(1)
  @warn_unqualified_access
  public func min() -> Element? {
    first
  }

  /// Returns the maximum element in this set.
  ///
  /// Bit sets are sorted, so the maximum element is always at the last
  /// position in the set.
  ///
  /// - Returns: The bit set's maximum element. If the sequence has no
  ///   elements, returns `nil`.
  ///
  /// - Complexity: O(1)
  @warn_unqualified_access
  public func max() -> Element? {
    last
  }

  /// Returns the first index in this set that addresses a member greater than
  /// or equal to `value`, or `endIndex` if all elements in `self` are less than
  /// it.
  public func partitioningIndex(for value: Int) -> Index {
    // FIXME: This function has a bad name.
    // It comes from swift-algorithms, but it does not make it good.
    // https://swiftpackageindex.com/apple/swift-algorithms/1.2.0/documentation/algorithms/swift/collection/partitioningindex(where:)
    let i = _read { handle in handle.partitioningIndex(for: value) }
    return Index(_position: i)
  }
}

//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Collections open source project
//
// Copyright (c) 2021-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
//===----------------------------------------------------------------------===//

import _CollectionsUtilities

extension _Word {
  mutating func _combineSlice(
    from start: UInt,
    count: UInt,
    with other: _Word,
    using merger: (inout _Word, _Word) -> Void
  ) {
    assert(start + count <= UInt(_Word.capacity))
    let mask = _Word(upTo: count).shiftedUp(by: start)
    var value = self.intersection(mask).shiftedDown(by: start)
    merger(&value, other)
    value = value.shiftedUp(by: start).intersection(mask)
    self.formIntersection(mask.complement())
    self.formUnion(value)
  }
}

extension BitArray._UnsafeHandle {
  /// Return a (handle, range) pair that corresponds to the given slice of this
  /// handle, with all words outside the range removed.
  func rebasedSlice(_ range: Range<Int>) -> (handle: Self, range: Range<Int>) {
    assert(range.lowerBound >= 0 && range.upperBound <= count)

#if DEBUG
    let isMutable = self._mutable
#else
    let isMutable = true
#endif

    guard range.count > 0 else {
      let b = UnsafeBufferPointer<_Word>(start: nil, count: 0)
      let h = Self(words: b, count: 0, mutable: isMutable)
      let r = Range(uncheckedBounds: (0, 0))
      return (h, r)
    }

    let lower = _BitPosition(range.lowerBound).split
    let upper = _BitPosition(range.upperBound).endSplit
    let startOffset = _Word.capacity * lower.word

    let w = _words[lower.word ... upper.word]
    let h = Self(
      words: UnsafeBufferPointer(rebasing: w),
      count: UInt(range.upperBound - startOffset),
      mutable: isMutable)
    let r = Range(uncheckedBounds: (
      range.lowerBound - startOffset, 
      range.upperBound - startOffset))
    return (h, r)
  }
}

extension BitArray._UnsafeHandle {
  internal func _bitwiseCombine(
    with other: BitArray._UnsafeHandle,
    using merger: (inout _Word, _Word) -> Void
  ) {
    self.ensureMutable()
    precondition(self.count == other.count,
                 "Bitwise combinations require input arrays to have matching counts")
    guard self.count > 0 else { return }
    let src = other._words
    let dst = self._mutableWords
    if src._startsLE(than: dst) {
      for i in 0 ..< dst.count {
        merger(&dst[i], src[i])
      }
    } else {
      for i in (0 ..< dst.count).reversed() {
        merger(&dst[i], src[i])
      }
    }
    // Don't leave stray set bits after the end.
    let end = self.end.split
    if end.bit > 0 {
      dst[end.word].formIntersection(_Word(upTo: end.bit))
    }
  }

  internal func _bitwiseCombine(
    with otherRange: Range<Int>,
    in other: BitArray._UnsafeHandle,
    using merger: (inout _Word, _Word) -> Void
  ) {
    self.ensureMutable()
    precondition(self.count == otherRange.count,
                 "Bitwise combinations require input arrays to have matching counts")
    precondition(
      otherRange.lowerBound >= 0 && otherRange.upperBound <= other.count,
      "Bit range out of bounds")
    let dst = self._mutableWords
    var src = _ChunkedBitsIterator(other, in: otherRange)
    // Make sure we do not clobber data if src & dst overlap.
    if dst._startsLE(than: src.words) {
      var i = 0
      let (endWord, endBit) = self.end.split
      while i < endWord {
        merger(&dst[i], src.nextBits(count: UInt(_Word.capacity)))
        i += 1
      }
      if endBit > 0 {
        merger(&dst[i], src.nextBits(count: endBit))
        dst[i].formIntersection(_Word(upTo: endBit))
      }
    } else {
      src.jumpBack()
      let endBit = self.end.bit
      var i = dst.count - 1
      if endBit > 0 {
        merger(&dst[i], src.previousBits(count: endBit))
        dst[i].formIntersection(_Word(upTo: endBit))
        i -= 1
      }
      while i >= 0 {
        merger(&dst[i], src.previousBits(count: UInt(_Word.capacity)))
        i -= 1
      }
    }
  }

  internal func _bitwiseCombine(
    _ selfRange: Range<Int>,
    with other: BitArray._UnsafeHandle,
    using merger: (inout _Word, _Word) -> Void
  ) {
    _bitwiseCombine(
      selfRange, with: 0 ..< other.count, in: other, using: merger)
  }

  internal func _bitwiseCombine(
    _ selfRange: Range<Int>,
    with otherRange: Range<Int>,
    in other: BitArray._UnsafeHandle,
    using merger: (inout _Word, _Word) -> Void
  ) {
    ensureMutable()
    precondition(selfRange.count == otherRange.count,
                 "Bitwise combinations require input arrays to have matching counts")
    precondition(
      selfRange.lowerBound >= 0 && selfRange.upperBound <= self.count,
      "Bit range out of bounds")
    precondition(
      otherRange.lowerBound >= 0 && otherRange.upperBound <= other.count,
      "Bit range out of bounds")

    let (this, thisRange) = self.rebasedSlice(selfRange)
    let (other, otherRange) = other.rebasedSlice(otherRange)
    if thisRange.lowerBound == 0 {
      if otherRange.lowerBound == 0 {
        this._bitwiseCombine(with: other, using: merger)
        return
      }
      this._bitwiseCombine(with: otherRange, in: other, using: merger)
      return
    }
    var dst = _ChunkedBitsIterator(this, in: thisRange)
    var src = _ChunkedBitsIterator(other, in: otherRange)
    let dstWords = this._mutableWords

    // Make sure we do not clobber data if src & dst overlap.
    if dst.words._startsLE(than: src.words) {
      while let (start, count) = dst.nextChunkPosition() {
        dstWords[start.word]._combineSlice(
          from: start.bit,
          count: count,
          with: src.nextBits(count: count),
          using: merger)
      }
    } else {
      src.jumpBack()
      dst.jumpBack()
      while let (start, count) = dst.previousChunkPosition() {
        dstWords[start.word]._combineSlice(
          from: start.bit,
          count: count,
          with: src.nextBits(count: count),
          using: merger)
      }
    }
  }
}

extension BitArray {
  /// Update this bit array in place by performing a bitwise OR operation with
  /// the bits in another bit array.
  ///
  /// - Parameter source: A bit array of the same count as `self`.
  /// - Complexity: O(`count`) (amortized)
  public mutating func formBitwiseOr(with source: Self) {
    _update { dst in
      source._read { src in
        dst._bitwiseCombine(with: src) { $0.formUnion($1) }
      }
    }
    self._checkInvariants()
  }

  /// Update this bit array in place by performing a bitwise OR operation with
  /// the bits in the given subrange of another bit array.
  ///
  /// - Parameter source: A bit array slice of the same count as `self`.
  /// - Complexity: O(`count`)
  @inlinable
  public mutating func formBitwiseOr(
    with sourceRange: some RangeExpression<Int>, in source: BitArray
  ) {
    _formBitwiseOr(with: sourceRange.relative(to: self), in: source)
  }

  @usableFromInline
  internal mutating func _formBitwiseOr(
    with sourceRange: Range<Int>, in source: BitArray
  ) {
    _update { dst in
      source._read { src in
        dst._bitwiseCombine(with: sourceRange, in: src) {
          $0.formUnion($1)
        }
      }
    }
    self._checkInvariants()
  }

  /// Update this bit array in place by performing a bitwise OR operation over
  /// its specified subrange with the bits in another bit array slice.
  ///
  /// - Parameter targetRange: A subrange of `self`.
  /// - Parameter sourceRange: A subrange of `source`. `targetRange` and
  ///     `sourceRange` must have the same count.
  /// - Parameter source: A bit array.
  /// - Complexity: O(`other.count`)
  public mutating func formBitwiseOr(
    _ targetRange: some RangeExpression<Int>,
    with sourceRange: some RangeExpression<Int>,
    in source: BitArray
  ) {
    _formBitwiseOr(
      targetRange.relative(to: self),
      with: sourceRange.relative(to: source),
      in: source)
  }

  @usableFromInline
  internal mutating func _formBitwiseOr(
    _ targetRange: Range<Int>,
    with sourceRange: Range<Int>,
    in source: BitArray
  ) {
    _update { dst in
      source._read { src in
        dst._bitwiseCombine(targetRange, with: sourceRange, in: src) {
          $0.formUnion($1)
        }
      }
    }
    self._checkInvariants()
  }

  /// Update this bit array in place by performing a bitwise OR operation over
  /// its specified subrange with the bits of another subrange of the same
  /// array.
  ///
  /// - Parameter targetRange: The range of bits to update in this array.
  /// - Parameter sourceRange: Another range of bits, providing the data to
  ///     operate with. `sourceRange` and `targetRange` must have the same count.
  /// - Complexity: O(`targetRange.count`) (amortized)
  @inlinable
  public mutating func formBitwiseOr(
    _ targetRange: some RangeExpression<Int>,
    with sourceRange: some RangeExpression<Int>
  ) {
    _formBitwiseOr(
      targetRange.relative(to: self),
      with: sourceRange.relative(to: self))
  }

  @usableFromInline
  internal mutating func _formBitwiseOr(
    _ targetRange: Range<Int>,
    with sourceRange: Range<Int>
  ) {
    _update { handle in
      handle._bitwiseCombine(targetRange, with: sourceRange, in: handle) {
        $0.formUnion($1)
      }
    }
    self._checkInvariants()
  }
}

extension BitArray {
  /// Update this bit array in place by performing a bitwise AND operation with
  /// the bits in another bit array.
  ///
  /// - Parameter source: A bit array of the same count as `self`.
  /// - Complexity: O(`count`) (amortized)
  public mutating func formBitwiseAnd(with source: Self) {
    _update { dst in
      source._read { src in
        dst._bitwiseCombine(with: src) { $0.formIntersection($1) }
      }
    }
    self._checkInvariants()
  }

  /// Update this bit array in place by performing a bitwise AND operation with
  /// the bits in the given subrange of another bit array.
  ///
  /// - Parameter source: A bit array slice of the same count as `self`.
  /// - Complexity: O(`count`)
  @inlinable
  public mutating func formBitwiseAnd(
    with sourceRange: some RangeExpression<Int>, in source: BitArray
  ) {
    _formBitwiseAnd(with: sourceRange.relative(to: self), in: source)
  }

  @usableFromInline
  internal mutating func _formBitwiseAnd(
    with sourceRange: Range<Int>, in source: BitArray
  ) {
    _update { dst in
      source._read { src in
        dst._bitwiseCombine(with: sourceRange, in: src) {
          $0.formIntersection($1)
        }
      }
    }
    self._checkInvariants()
  }

  /// Update this bit array in place by performing a bitwise AND operation over
  /// its specified subrange with the bits in another bit array slice.
  ///
  /// - Parameter targetRange: A subrange of `self`.
  /// - Parameter sourceRange: A subrange of `source`. `targetRange` and
  ///     `sourceRange` must have the same count.
  /// - Parameter source: A bit array.
  /// - Complexity: O(`other.count`)
  public mutating func formBitwiseAnd(
    _ targetRange: some RangeExpression<Int>,
    with sourceRange: some RangeExpression<Int>,
    in source: BitArray
  ) {
    _formBitwiseAnd(
      targetRange.relative(to: self),
      with: sourceRange.relative(to: source),
      in: source)
  }

  @usableFromInline
  internal mutating func _formBitwiseAnd(
    _ targetRange: Range<Int>,
    with sourceRange: Range<Int>,
    in source: BitArray
  ) {
    _update { dst in
      source._read { src in
        dst._bitwiseCombine(targetRange, with: sourceRange, in: src) {
          $0.formIntersection($1)
        }
      }
    }
    self._checkInvariants()
  }

  /// Update this bit array in place by performing a bitwise AND operation over
  /// its specified subrange with the bits of another subrange of the same
  /// array.
  ///
  /// - Parameter targetRange: The range of bits to update in this array.
  /// - Parameter sourceRange: Another range of bits, providing the data to
  ///     operate with. `sourceRange` and `targetRange` must have the same count.
  /// - Complexity: O(`targetRange.count`) (amortized)
  @inlinable
  public mutating func formBitwiseAnd(
    _ targetRange: some RangeExpression<Int>,
    with sourceRange: some RangeExpression<Int>
  ) {
    _formBitwiseAnd(
      targetRange.relative(to: self),
      with: sourceRange.relative(to: self))
  }

  @usableFromInline
  internal mutating func _formBitwiseAnd(
    _ targetRange: Range<Int>,
    with sourceRange: Range<Int>
  ) {
    _update { handle in
      handle._bitwiseCombine(targetRange, with: sourceRange, in: handle) {
        $0.formIntersection($1)
      }
    }
    self._checkInvariants()
  }
}

extension BitArray {
  /// Update this bit array in place by performing a bitwise XOR operation with
  /// the bits in another bit array.
  ///
  /// - Parameter source: A bit array of the same count as `self`.
  /// - Complexity: O(`count`) (amortized)
  public mutating func formBitwiseXor(with source: Self) {
    _update { dst in
      source._read { src in
        dst._bitwiseCombine(with: src) { $0.formSymmetricDifference($1) }
      }
    }
    self._checkInvariants()
  }

  /// Update this bit array in place by performing a bitwise AND operation with
  /// the bits in the given subrange of another bit array.
  ///
  /// - Parameter source: A bit array slice of the same count as `self`.
  /// - Complexity: O(`count`)
  @inlinable
  public mutating func formBitwiseXor(
    with sourceRange: some RangeExpression<Int>, in source: BitArray
  ) {
    _formBitwiseXor(with: sourceRange.relative(to: self), in: source)
  }

  @usableFromInline
  internal mutating func _formBitwiseXor(
    with sourceRange: Range<Int>, in source: BitArray
  ) {
    _update { dst in
      source._read { src in
        dst._bitwiseCombine(with: sourceRange, in: src) {
          $0.formSymmetricDifference($1)
        }
      }
    }
    self._checkInvariants()
  }

  /// Update this bit array in place by performing a bitwise AND operation over
  /// its specified subrange with the bits in another bit array slice.
  ///
  /// - Parameter targetRange: A subrange of `self`.
  /// - Parameter sourceRange: A subrange of `source`. `targetRange` and
  ///     `sourceRange` must have the same count.
  /// - Parameter source: A bit array.
  /// - Complexity: O(`other.count`)
  public mutating func formBitwiseXor(
    _ targetRange: some RangeExpression<Int>,
    with sourceRange: some RangeExpression<Int>,
    in source: BitArray
  ) {
    _formBitwiseXor(
      targetRange.relative(to: self),
      with: sourceRange.relative(to: source),
      in: source)
  }

  @usableFromInline
  internal mutating func _formBitwiseXor(
    _ targetRange: Range<Int>,
    with sourceRange: Range<Int>,
    in source: BitArray
  ) {
    _update { dst in
      source._read { src in
        dst._bitwiseCombine(targetRange, with: sourceRange, in: src) {
          $0.formSymmetricDifference($1)
        }
      }
    }
    self._checkInvariants()
  }

  /// Update this bit array in place by performing a bitwise AND operation over
  /// its specified subrange with the bits of another subrange of the same
  /// array.
  ///
  /// - Parameter targetRange: The range of bits to update in this array.
  /// - Parameter sourceRange: Another range of bits, providing the data to
  ///     operate with. `sourceRange` and `targetRange` must have the same count.
  /// - Complexity: O(`targetRange.count`) (amortized)
  @inlinable
  public mutating func formBitwiseXor(
    _ targetRange: some RangeExpression<Int>,
    with sourceRange: some RangeExpression<Int>
  ) {
    _formBitwiseXor(
      targetRange.relative(to: self),
      with: sourceRange.relative(to: self))
  }

  @usableFromInline
  internal mutating func _formBitwiseXor(
    _ targetRange: Range<Int>,
    with sourceRange: Range<Int>
  ) {
    _update { handle in
      handle._bitwiseCombine(targetRange, with: sourceRange, in: handle) {
        $0.formSymmetricDifference($1)
      }
    }
    self._checkInvariants()
  }
}

extension BitArray {
  /// Update this bit array by forming the complement of each bit in it.
  ///
  /// - Complexity: O(`count`)
  public mutating func toggleAll() {
    _update { handle in
      let w = handle._mutableWords
      for i in 0 ..< handle._words.count {
        w[i].formComplement()
      }
      let p = handle.end
      if p.bit > 0 {
        w[p.word].subtract(_Word(upTo: p.bit).complement())
      }
    }
    _checkInvariants()
  }

  /// Update this bit array by forming the complement of each of its bits within
  /// the specified subrange.
  ///
  /// - Complexity: O(`range.count`) (amortized)
  @inlinable
  public mutating func toggleAll(in range: some RangeExpression<Int>) {
    _toggleAll(in: range.relative(to: self))
  }

  @usableFromInline
  internal mutating func _toggleAll(in range: Range<Int>) {
    precondition(range.upperBound <= count, "Range out of bounds")
    _update { handle in
      let words = handle._mutableWords
      let start = _BitPosition(range.lowerBound)
      let end = _BitPosition(range.upperBound)
      if start.word == end.word {
        let bits = _Word(from: start.bit, to: end.bit)
        words[start.word].formSymmetricDifference(bits)
        return
      }
      words[start.word].formSymmetricDifference(
        _Word(upTo: start.bit).complement())
      for i in stride(from: start.word + 1, to: end.word, by: 1) {
        words[i].formComplement()
      }
      if end.bit > 0 {
        words[end.word].formSymmetricDifference(_Word(upTo: end.bit))
      }
    }
  }
}

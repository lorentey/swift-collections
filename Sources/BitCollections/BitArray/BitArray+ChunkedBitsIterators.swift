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

#if !COLLECTIONS_SINGLE_MODULE
import _CollectionsUtilities
#endif
/// Iterator that visits maximally long word chunks within a bit region of a
/// buffer of words.
internal struct _ChunkedBitsIterator {
  internal typealias _BitPosition = _UnsafeBitSet.Index

  internal let words: UnsafeBufferPointer<_Word>
  internal let start: _BitPosition
  internal let end: _BitPosition
  internal var position: _BitPosition

  internal init(
    _ words: UnsafeBufferPointer<_Word>,
    in range: Range<Int>
  ) {
    assert(range.lowerBound >= 0)
    assert(range.upperBound <= words.count * _Word.capacity)
    self.words = words
    self.start = _BitPosition(range.lowerBound)
    self.end = _BitPosition(range.upperBound)
    self.position = start
  }

  internal init(
    _ handle: BitArray._UnsafeHandle,
    in range: Range<Int>
  ) {
    self.init(handle._words, in: range)
  }

  internal mutating func jumpFront() {
    self.position = start
  }

  internal mutating func jumpBack() {
    self.position = end
  }

  internal mutating func nextBits(count: UInt) -> _Word {
    assert(count > 0 && count <= _Word.capacity)
    let (w1, c1) = nextChunk(maxBitCount: count)!
    let remainder = count - c1
    guard remainder > 0 else { return w1 }
    let (w2, c2) = nextChunk(maxBitCount: remainder)!
    assert(remainder == c2)
    return w1.union(w2.shiftedUp(by: c1))
  }

  internal mutating func previousBits(count: UInt) -> _Word {
    assert(count > 0 && count <= _Word.capacity)
    let (w1, c1) = previousChunk(maxBitCount: count)!
    let remainder = count - c1
    guard remainder > 0 else { return w1 }
    let (w2, c2) = previousChunk(maxBitCount: remainder)!
    assert(remainder == c2)
    return w1.shiftedUp(by: c2).union(w2)
  }

  internal mutating func nextChunk(
    maxBitCount: UInt = UInt(_Word.capacity)
  ) -> (bits: _Word, count: UInt)? {
    guard let (start, count) = nextChunkPosition(maxBitCount: maxBitCount) else {
      return nil
    }
    let (w, b) = start.split
    let value = words[w].shiftedDown(by: b).intersection(_Word(upTo: count))
    return (value, count)
  }

  internal mutating func previousChunk(
    maxBitCount: UInt = UInt(_Word.capacity)
  ) -> (bits: _Word, count: UInt)? {
    guard let (start, count) = previousChunkPosition(
      maxBitCount: maxBitCount
    ) else {
      return nil
    }
    let (w, b) = start.split
    let value = words[w].shiftedDown(by: b).intersection(_Word(upTo: count))
    return (value, count)
  }

  internal mutating func nextChunkPosition(
    maxBitCount: UInt = UInt(_Word.capacity)
  ) -> (start: _BitPosition, count: UInt)? {
    assert(maxBitCount > 0)
    guard position < end else { return nil }
    let p = position
    let limit = min(end, _BitPosition(p.value + maxBitCount))
    if p.word == limit.word {
      position = limit
      return (start: p, count: limit.bit - p.bit)
    }
    let c = UInt(_Word.capacity) - p.bit
    position.value += c
    return (start: p, count: c)
  }

  internal mutating func previousChunkPosition(
    maxBitCount: UInt = UInt(_Word.capacity)
  ) -> (start: _BitPosition, count: UInt)? {
    assert(maxBitCount > 0)
    guard position > start else { return nil }
    let p = position
    let limit = (
      p.value >= start.value + maxBitCount
      ? _BitPosition(p.value  - maxBitCount)
      : start)
    let (w, b) = p.endSplit
    if w == limit.word {
      position = limit
      return (start: limit, count: b - limit.bit)
    }
    let c = b
    position.value -= c
    return (start: position, count: c)
  }
}

extension IteratorProtocol where Element == Bool {
  internal mutating func _nextChunk(
    maximumCount: UInt = UInt(_Word.capacity)
  ) -> (bits: _Word, count: UInt) {
    assert(maximumCount <= _Word.capacity)
    var bits = _Word.empty
    var c: UInt = 0
    while let v = next() {
      if v { bits.insert(c) }
      c += 1
      if c == maximumCount { break }
    }
    return (bits, c)
  }
}

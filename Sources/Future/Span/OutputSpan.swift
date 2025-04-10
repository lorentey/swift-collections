//===--- OutputSpan.swift -------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

// `OutputSpan` is a reference to a contiguous region of memory that starts with
// some number of initialized `Element` instances followed by uninitialized
// memory. It provides operations to access the items it stores, as well as to
// add new elements and to remove existing ones.
@safe
@frozen
public struct OutputSpan<Element: ~Copyable>: ~Copyable, ~Escapable {
  @usableFromInline
  internal let _pointer: UnsafeMutableRawPointer?
  
  public let capacity: Int
  
  @usableFromInline
  internal var _count: Int = 0
  
  @_alwaysEmitIntoClient
  @inlinable
  deinit {
    guard _count > 0 else { return }
    unsafe _start().withMemoryRebound(
      to: Element.self, capacity: _count
    ) {
      [ workaround = _count ] in
      _ = unsafe $0.deinitialize(count: workaround)
    }
  }
  
  @_alwaysEmitIntoClient
  @lifetime(borrow start)
  internal init(
    _uncheckedStart start: UnsafeMutableRawPointer?,
    capacity: Int,
    initializedCount: Int
  ) {
    unsafe _pointer = start
    self.capacity = capacity
    _count = count
  }
}

@available(*, unavailable)
extension OutputSpan: Sendable {}

extension OutputSpan where Element: ~Copyable {
  @_alwaysEmitIntoClient
  @_transparent
  internal func _start() -> UnsafeMutableRawPointer {
    unsafe _pointer.unsafelyUnwrapped
  }
  @_alwaysEmitIntoClient
  @_transparent
  internal func _tail() -> UnsafeMutableRawPointer {
    unsafe _start().advanced(by: _count &* MemoryLayout<Element>.stride)
  }

  @_alwaysEmitIntoClient
  public var freeCapacity: Int { capacity &- _count }

  @_alwaysEmitIntoClient
  public var count: Int { _count }

  @_alwaysEmitIntoClient
  public var isEmpty: Bool { _count == 0 }

  @_alwaysEmitIntoClient
  public var isFull: Bool { _count == capacity }
}

extension OutputSpan where Element: ~Copyable  {
  @_alwaysEmitIntoClient
  @lifetime(immortal)
  public init() {
    unsafe _pointer = nil
    capacity = 0
    _count = 0
  }

  @_alwaysEmitIntoClient
  @lifetime(borrow buffer)
  internal init(
    _uncheckedBuffer buffer: UnsafeMutableBufferPointer<Element>,
    initializedCount: Int
  ) {
    unsafe _pointer = .init(buffer.baseAddress)
    capacity = buffer.count
    _count = count
  }

  @_alwaysEmitIntoClient
  @lifetime(borrow buffer)
  public init(
    _buffer buffer: UnsafeMutableBufferPointer<Element>,
    initializedCount: Int = 0
  ) {
    precondition(
      ((Int(bitPattern: buffer.baseAddress) &
        (MemoryLayout<Element>.alignment&-1)) == 0),
      "OutputSpan cannot have improper alignment")
    precondition(
      initializedCount >= 0 && initializedCount <= buffer.count,
      "OutputSpan count outside its capacity")
    unsafe self.init(
      _uncheckedBuffer: buffer, initializedCount: initializedCount)
  }

  @_alwaysEmitIntoClient
  @lifetime(borrow pointer)
  public init(
    _start pointer: UnsafeMutablePointer<Element>,
    capacity: Int,
    initializedCount: Int = 0
  ) {
    precondition(capacity >= 0, "OutputSpan capacity cannot be negative")
    let buf = unsafe UnsafeMutableBufferPointer(start: pointer, count: capacity)
    let os = unsafe OutputSpan(_buffer: buf, initializedCount: initializedCount)
    self = unsafe _overrideLifetime(os, borrowing: pointer)
  }
}

extension OutputSpan {

  @_alwaysEmitIntoClient
  @lifetime(borrow buffer)
  public init(
    _buffer buffer: borrowing Slice<UnsafeMutableBufferPointer<Element>>,
    initializedCount: Int = 0
  ) {
    let rebased = unsafe UnsafeMutableBufferPointer(rebasing: buffer)
    let os = unsafe OutputSpan(_buffer: rebased, initializedCount: initializedCount)
    self = unsafe _overrideLifetime(os, borrowing: buffer)
  }
}

extension OutputSpan where Element: BitwiseCopyable {

  @_alwaysEmitIntoClient
  @lifetime(borrow bytes)
  public init(
    _bytes bytes: UnsafeMutableRawBufferPointer,
    initializedCount: Int = 0 // FIXME: Beware, unit mismatch
  ) {
    precondition(
      ((Int(bitPattern: bytes.baseAddress) &
        (MemoryLayout<Element>.alignment&-1)) == 0),
      "OutputSpan cannot have improper alignment")
    let (byteCount, stride) = (bytes.count, MemoryLayout<Element>.stride)
    let (count, remainder) = byteCount.quotientAndRemainder(dividingBy: stride)
    precondition(remainder == 0, "OutputSpan must not end on a partial element")
    let pointer = bytes.baseAddress
    let os = unsafe OutputSpan(
      _uncheckedStart: pointer,
      capacity: count,
      initializedCount: initializedCount)
    self = unsafe _overrideLifetime(os, borrowing: bytes)
  }

  @_alwaysEmitIntoClient
  @lifetime(borrow buffer)
  public init(
    _bytes buffer: borrowing Slice<UnsafeMutableRawBufferPointer>,
    initializedCount: Int = 0 // FIXME: Beware, unit mismatch
  ) {
    let rebased = unsafe UnsafeMutableRawBufferPointer(rebasing: buffer)
    let os = unsafe OutputSpan(_bytes: rebased, initializedCount: initializedCount)
    self = unsafe _overrideLifetime(os, borrowing: buffer)
  }
}

extension OutputSpan where Element: ~Copyable {

  @_alwaysEmitIntoClient
  @lifetime(self: copy self)
  public mutating func append(_ value: consuming Element) {
    precondition(_count < capacity, "OutputSpan capacity overflow")
    unsafe _tail().initializeMemory(as: Element.self, to: value)
    _count &+= 1
  }

  @_alwaysEmitIntoClient
  public mutating func removeLast() -> Element? {
    guard _count > 0 else { return nil }
    _count &-= 1
    return unsafe _tail().withMemoryRebound(to: Element.self, capacity: 1, { unsafe $0.move() })
  }

  @_alwaysEmitIntoClient
  public mutating func removeAll() {
    _ = unsafe _start().withMemoryRebound(to: Element.self, capacity: _count) {
      unsafe $0.deinitialize(count: _count)
    }
    _count = 0
  }
}

//MARK: bulk-update functions
extension OutputSpan {

  @_alwaysEmitIntoClient
  @lifetime(self: copy self)
  public mutating func append(repeating repeatedValue: Element, count: Int) {
    precondition(count <= freeCapacity, "OutputSpan capacity overflow")
    unsafe _tail().withMemoryRebound(to: Element.self, capacity: count) {
      unsafe $0.initialize(repeating: repeatedValue, count: count)
    }
    _count &+= count
  }

  /// Returns `true` if it has reached the end of the iterator without filling
  /// up all free capacity in the target span.
  @_alwaysEmitIntoClient
  @lifetime(self: copy self)
  @discardableResult
  public mutating func append(
    fromContentsOf elements: inout some IteratorProtocol<Element>
  ) -> Bool {
    while _count < capacity {
      guard let element = elements.next() else { return true }
      unsafe _tail().initializeMemory(as: Element.self, to: element)
      _count &+= 1
    }
    return false
  }

  @_alwaysEmitIntoClient
  @lifetime(self: copy self)
  public mutating func append(
    fromContentsOf source: some Sequence<Element>
  ) {
    let void: Void? = source.withContiguousStorageIfAvailable {
      unsafe append(fromContentsOf: $0)
    }
    if void != nil {
      return
    }

    let freeCapacity = freeCapacity
    var (iterator, copied) = unsafe _tail().withMemoryRebound(
      to: Element.self, capacity: freeCapacity
    ) {
      let suffix = unsafe UnsafeMutableBufferPointer(start: $0, count: freeCapacity)
      return unsafe source._copyContents(initializing: suffix)
    }
    precondition(iterator.next() == nil, "OutputSpan capacity overflow")
    precondition(_count + copied <= capacity, "Invalid Sequence._copyContents")
    _count &+= copied
  }

  @_alwaysEmitIntoClient
  @lifetime(self: copy self)
  public mutating func append(
    fromContentsOf source: UnsafeBufferPointer<Element>
  ) {
    guard !source.isEmpty else { return }
    precondition(source.count <= freeCapacity, "OutputSpan capacity overflow")
    unsafe _tail().initializeMemory(
      as: Element.self, from: source.baseAddress!, count: source.count)
    _count += source.count
  }

  @available(SwiftStdlib 6.2, *) // For Span
  @_alwaysEmitIntoClient
  @lifetime(self: copy self)
  public mutating func append(
    fromContentsOf source: Span<Element>
  ) {
    guard !source.isEmpty else { return }
    precondition(source.count <= freeCapacity, "OutputSpan capacity overflow")
    let tail = unsafe _start().advanced(by: _count&*MemoryLayout<Element>.stride)
    _ = unsafe source.withUnsafeBufferPointer {
      unsafe tail.initializeMemory(
        as: Element.self, from: $0.baseAddress!, count: $0.count
      )
    }
    _count += source.count
  }

  @available(SwiftStdlib 6.2, *) // For Span
  @_alwaysEmitIntoClient
  @lifetime(self: copy self)
  public mutating func append(fromContentsOf source: borrowing MutableSpan<Element>) {
    unsafe source.withUnsafeBufferPointer { unsafe append(fromContentsOf: $0) }
  }
}

extension OutputSpan where Element: ~Copyable {
  @_alwaysEmitIntoClient
  @lifetime(self: copy self)
  public mutating func moveAppend(
    fromContentsOf source: inout Self
  ) {
    guard !source.isEmpty else { return }
    unsafe source.withUnsafeMutableBuffer { buffer, count in
      unsafe self.moveAppend(fromContentsOf: buffer.extracting(..<count))
      count = 0
    }
  }

  @_alwaysEmitIntoClient
  @lifetime(self: copy self)
  public mutating func moveAppend(
    fromContentsOf source: UnsafeMutableBufferPointer<Element>
  ) {
    guard !source.isEmpty else { return }
    precondition(source.count <= freeCapacity, "OutputSpan capacity overflow")
    let offset = self._count &* MemoryLayout<Element>.stride
    let tail = unsafe self._start().advanced(by: offset)
    unsafe tail.moveInitializeMemory(
      as: Element.self, from: source.baseAddress!, count: source.count)
    self._count += count
  }
}

extension OutputSpan {

  @_alwaysEmitIntoClient
  @lifetime(self: copy self)
  public mutating func moveAppend(
    fromContentsOf source: Slice<UnsafeMutableBufferPointer<Element>>
  ) {
    unsafe moveAppend(
      fromContentsOf: UnsafeMutableBufferPointer(rebasing: source)
    )
  }
}

extension OutputSpan where Element: BitwiseCopyable {
// TODO: alternative append() implementations for BitwiseCopyable elements
}

extension OutputSpan where Element: ~Copyable {

  @available(SwiftStdlib 6.2, *)
  @_alwaysEmitIntoClient
  public var span: Span<Element> {
    @lifetime(borrow self)
    borrowing get {
      let pointer = unsafe _pointer?.assumingMemoryBound(to: Element.self)
      let buffer = unsafe UnsafeBufferPointer(start: pointer, count: _count)
      let span = unsafe Span(_unsafeElements: buffer)
      return unsafe _overrideLifetime(span, borrowing: self)
    }
  }

#if compiler(>=6.3) // FIXME: Turn this on once we have a new enough toolchain
  @available(SwiftStdlib 6.2, *)
  @_alwaysEmitIntoClient
  public var mutableSpan: MutableSpan<Element> {
    @lifetime(&self)
    mutating get {
      let pointer = unsafe _pointer?.assumingMemoryBound(to: Element.self)
      let buffer = unsafe UnsafeMutableBufferPointer(
        start: pointer, count: _count
      )
      let span = unsafe MutableSpan(_unsafeElements: buffer)
      return unsafe _overrideLifetime(span, mutating: &self)
    }
  }
#endif
}

extension OutputSpan where Element: ~Copyable {
  @lifetime(copy self)
  public mutating func withUnsafeMutableBuffer<E: Error, R: ~Copyable>(
    _ body: (UnsafeMutableBufferPointer<Element>, inout Int) throws(E) -> R
  ) throws(E) -> R {
    guard !isEmpty else {
      let buffer = unsafe UnsafeMutableBufferPointer<Element>(start: nil, count: 0)
      var count = 0
      let result = unsafe try body(buffer, &count)
      precondition(count == 0, "OutputSpan count outside its capacity")
      return result
    }
    return unsafe try _start().withMemoryRebound(
      to: Element.self, capacity: capacity
    ) { p throws(E) in
      let buffer = unsafe UnsafeMutableBufferPointer(start: p, count: capacity)
      var count = self._count
      defer {
        precondition(
          count >= 0 && count <= self.capacity,
          "OutputSpan count outside its capacity")
        self._count = count
      }
      return unsafe try body(buffer, &count)
    }
  }
}

extension OutputSpan where Element: ~Copyable {
  @_alwaysEmitIntoClient
  public consuming func finalize(
    for buffer: UnsafeMutableRawBufferPointer
  ) -> Int {
    precondition(
      unsafe buffer.baseAddress == self._pointer
      && buffer.count == self.capacity,
      "OutputSpan cannot be replaced")
    let count = self._count
    discard self
    return count
  }
  
  @_alwaysEmitIntoClient
  public consuming func finalize(
    for buffer: UnsafeMutableBufferPointer<Element>
  ) -> Int {
    unsafe finalize(for: UnsafeMutableRawBufferPointer(buffer))
  }
}

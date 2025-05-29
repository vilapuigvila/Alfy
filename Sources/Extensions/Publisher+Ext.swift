//
//  File.swift
//  Alfy
//
//  Created by albert vila on 29/5/25.
//

import Combine

extension Publisher where Failure == Never {
  public func weakAssign<O: AnyObject>(
      to keyPath: ReferenceWritableKeyPath<O, Output>,
      on object: O
  ) -> AnyCancellable {
      sink { [weak object] value in
          object?[keyPath: keyPath] = value
      }
  }
}

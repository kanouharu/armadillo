// Copyright (c) 2016, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library observe.src.auto_observable;

import 'dart:async';
import 'dart:collection';

import 'package:observable/observable.dart';
import 'package:smoke/smoke.dart' as smoke;

import 'dirty_check.dart' show dirtyCheckObservables, registerObservable;
import 'metadata.dart' show ObservableProperty;

abstract class AutoObservable implements ChangeNotifier {
  /// Performs dirty checking of objects that inherit from [AutoObservable].
  /// This scans all observed objects using mirrors and determines if any fields
  /// have changed. If they have, it delivers the changes for the object.
  static void dirtyCheck() => dirtyCheckObservables();

  StreamController<List<ChangeRecord>> _changes;

  Map<Symbol, Object> _values;
  List<ChangeRecord> _records;

  /// The stream of change records to this object. Records will be delivered
  /// asynchronously.
  ///
  /// [deliverChanges] can be called to force synchronous delivery.
  @override
  Stream<List<ChangeRecord>> get changes {
    if (_changes == null) {
      _changes = new StreamController.broadcast(
          sync: true, onListen: observed, onCancel: unobserved);
    }
    return _changes.stream;
  }

  /// True if this object has any observers, and should call
  /// [notifyChange] for changes.
  @override
  bool get hasObservers => _changes != null && _changes.hasListener;

  @override
  void observed() {
    // Register this object for dirty checking purposes.
    registerObservable(this);

    var values = new Map<Symbol, Object>();

    // Note: we scan for @observable regardless of whether the base type
    // actually includes this mixin. While perhaps too inclusive, it lets us
    // avoid complex logic that walks "with" and "implements" clauses.
    var queryOptions = new smoke.QueryOptions(
        includeInherited: true,
        includeProperties: false,
        withAnnotations: const [ObservableProperty]);
    for (var decl in smoke.query(this.runtimeType, queryOptions)) {
      var name = decl.name;
      // Note: since this is a field, getting the value shouldn't execute
      // user code, so we don't need to worry about errors.
      values[name] = smoke.read(this, name);
    }

    _values = values;
  }

  /// Release data associated with observation.
  @override
  void unobserved() {
    // Note: we don't need to explicitly unregister from the dirty check list.
    // This will happen automatically at the next call to dirtyCheck.
    if (_values != null) {
      _values = null;
    }
  }

  /// Synchronously deliver pending [changes]. Returns true if any records were
  /// delivered, otherwise false.
  // TODO(jmesserly): this is a bit different from the ES Harmony version, which
  // allows delivery of changes to a particular observer:
  // http://wiki.ecmascript.org/doku.php?id=harmony:observe#object.deliverchangerecords
  //
  // The rationale for that, and for async delivery in general, is the principal
  // that you shouldn't run code (observers) when it doesn't expect to be run.
  // If you do that, you risk violating invariants that the code assumes.
  //
  // For this reason, we need to match the ES Harmony version. The way we can do
  // this in Dart is to add a method on StreamSubscription (possibly by
  // subclassing Stream* types) that immediately delivers records for only
  // that subscription. Alternatively, we could consider using something other
  // than Stream to deliver the multicast change records, and provide an
  // Observable->Stream adapter.
  //
  // Also: we should be delivering changes to the observer (subscription) based
  // on the birth order of the observer. This is for compatibility with ES
  // Harmony as well as predictability for app developers.
  @override
  bool deliverChanges() {
    if (_values == null || !hasObservers) return false;

    // Start with manually notified records (computed properties, etc),
    // then scan all fields for additional changes.
    var records = _records;
    _records = null;

    _values.forEach((name, oldValue) {
      var newValue = smoke.read(this, name);
      if (oldValue != newValue) {
        if (records == null) records = [];
        records.add(new PropertyChangeRecord(this, name, oldValue, newValue));
        _values[name] = newValue;
      }
    });

    if (records == null) return false;

    _changes.add(new UnmodifiableListView<ChangeRecord>(records));
    return true;
  }

  /// Notify that the field [name] of this object has been changed.
  ///
  /// The [oldValue] and [newValue] are also recorded. If the two values are
  /// equal, no change will be recorded.
  ///
  /// For convenience this returns [newValue].
  @override
  /*=T*/ notifyPropertyChange/*<T>*/(
      Symbol field, /*=T*/ oldValue, /*=T*/ newValue) {
    if (hasObservers && oldValue != newValue) {
      notifyChange(new PropertyChangeRecord(this, field, oldValue, newValue));
    }
    return newValue;
  }

  /// Notify observers of a change.
  ///
  /// For most objects [AutoObservable.notifyPropertyChange] is more
  /// convenient, but collections sometimes deliver other types of changes
  /// such as a [ListChangeRecord].
  ///
  /// Notes:
  /// - This is *not* required for fields if you mixin or extend
  ///   [AutoObservable], but you can use it for computed properties.
  /// - Unlike [Observable] this will not schedule [deliverChanges]; use
  ///   [AutoObservable.dirtyCheck] instead.
  @override
  void notifyChange([ChangeRecord record]) {
    if (record == null || !hasObservers) return;
    if (_records == null) _records = [];
    _records.add(record);
  }
}

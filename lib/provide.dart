// Copyright 2018 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/widgets.dart';

/// [ProviderNode] makes a set of [providers] available to any widgets below
/// it in the widget tree.
///
/// Types provided by parent ProviderNodes will be used if not provided in the
/// current node.
class ProviderNode extends StatefulWidget {
  /// The widget tree for which the [providers] are made available.
  final Widget child;

  /// The values made available to the [child].
  final Providers providers;

  /// Whether or not to dispose the providers when this node is removed
  /// from the tree.
  final bool dispose;

  /// Constructor.
  const ProviderNode(
      {@required this.child, @required this.providers, this.dispose = true});

  @override
  State<StatefulWidget> createState() => _ProviderNodeState(
      child: child, providers: providers, disposeProviders: dispose);
}

class _ProviderNodeState extends State<ProviderNode> {
  /// The widget tree for which the [providers] are made available.
  final Widget child;

  /// The values made available to the [child].
  final Providers providers;

  /// Whether or not to dispose the providers when this node is removed
  /// from the tree.
  final bool disposeProviders;

  _ProviderNodeState(
      {@required this.child,
      @required this.providers,
      @required this.disposeProviders});

  @override
  Widget build(BuildContext context) {
    return _InheritedProviders(
        child: child,
        providers: providers,
        parent: _InheritedProviders.of(context));
  }

  @override
  Future<void> dispose() async {
    super.dispose();
    if (disposeProviders) {
      await providers.dispose();
    }
  }
}

/// A [ProviderScope] provides a separate type-space for a provider, thus
/// allowing more than one provider of the same type.
///
/// This should always be initialized as a static const and passed around.
/// The name is only used for descriptive purposes.
class ProviderScope {
  final String _name;

  /// Constructor
  const ProviderScope(this._name);

  @override
  String toString() {
    return "Scope ('$_name')";
  }
}

/// Providers are the values passed to the [ProviderNodes].
///
/// Providers can be added to using either convenience functions such as
/// [provideValue] or by passing in Providers.
class Providers {
  // The Provider for each given [Type] should return that type, but we can't
  // enforce that here directy. We can use APIs to make sure it's type-safe.
  final Map<ProviderScope, Map<Type, Provider<dynamic>>> _providers = {};

  /// Creates a new empty provider.
  Providers();

  /// The default scope in which any type not with a defined scope resides.
  static const ProviderScope defaultScope = ProviderScope('_default');

  /// Creates a provider with the included providers.
  ///
  /// If a scope is provided, the values will be under that scope.
  factory Providers.withProviders(Map<Type, Provider<dynamic>> providers,
          {ProviderScope scope}) =>
      Providers()..provideAll(providers, scope: scope);

  /// Add a provider for a single type.
  ///
  /// Will override any existing provider of that type in this node with the
  /// given scope. If no [scope] is passed in, the default one will be used.
  void provide<T>(Provider<T> provider, {ProviderScope scope}) {
    // This should never happen.
    assert(provider.type == T);

    _providersForScope(scope)[T] = provider;
  }

  /// Provide many providers at once.
  ///
  /// Prefer using [provide] and [provideFrom] because that catches type
  /// errors at compile-time.
  void provideAll(Map<Type, Provider> providers, {ProviderScope scope}) {
    for (var entry in providers.entries) {
      if (entry.key != entry.value.type) {
        if (entry.value.type == dynamic) {
          throw ArgumentError('Not able to infer the type of provider for'
              ' ${entry.key} automatically. Add type argument to provider.');
        }
        throw ArgumentError('Type mismatch between ${entry.key} and provider '
            'of ${entry.value.type}.');
      }
    }

    _providersForScope(scope).addAll(providers);
  }

  /// Add in all the providers from another Providers.
  void provideFrom(Providers other) {
    for (final scope in other._providers.keys) {
      provideAll(other._providersForScope(scope), scope: scope);
    }
  }

  /// Syntactic sugar around adding a value based provider.
  ///
  /// If this value is [Listenable], widgets that use this value can be rebuilt
  /// on change. If no [scope] is passed in, the default one will be used.
  void provideValue<T>(T value, {ProviderScope scope}) {
    provide(Provider.value(value), scope: scope);
  }

  /// Disposes of any streams or stored values in the providers.
  Future<void> dispose() async {
    for (final scopeMap in _providers.values) {
      for (final provider in scopeMap.values) {
        await provider.dispose();
      }
    }
  }

  /// Provider in this case will always be of the provider type, but there is no
  /// way to make this type safe.
  ///
  /// Internal users should cast this whenever possible.
  @visibleForTesting
  Provider getFromType(Type type, {ProviderScope scope}) {
    return _providersForScope(scope)[type];
  }

  Map<Type, Provider<dynamic>> _providersForScope(scope) =>
      _providers[scope ?? defaultScope] ??= {};
}

/// A Provider provides a value on request.
///
/// If a provider implements [Listenable], it will be listened to by the
/// [Provide] widget to rebuild on change. Other than the built in providers,
/// one can implement Provider to provide caching or linkages.
///
/// When a Provider is instantiated within a [providers.provide] call, the type
/// can be inferred and therefore the type can be ommited, but otherwise,
/// [T] is required.
///
/// Provider should be implemented and not extended.
abstract class Provider<T> {
  /// Returns the value provided by the provider.
  ///
  /// Because providers could potentially initialize the value each time [get]
  /// is called, this should be called as infrequently as possible.
  T get(BuildContext context);

  /// Returns a stream of changes to the underlying value.
  Stream<T> stream(BuildContext context);

  /// Disposes of any resources or listeners held on by the provider.
  Future<void> dispose();

  /// The type that is provided by the provider.
  Type get type;

  /// Creates a provider with the value provided to it.
  factory Provider.value(T value) => _ValueProvider(value);

  /// Creates a provider which will initialize using the [ProviderFunction]
  /// the first time the value is requested.
  ///
  /// The context can be used to obtain other values from the provider. However,
  /// care should be taken with this to not have circular dependencies.
  factory Provider.function(ProviderFunction<T> function) =>
      _LazyProvider<T>(function);

  /// Creates a provider that provides a new value for each
  /// requestor of the value.
  factory Provider.withFactory(ProviderFunction<T> function) =>
      _FactoryProvider<T>(function);

  /// Creates a provider that listens to a stream and caches the last
  /// received value of the stream.
  ///
  /// This provider notifies for rebuild after every release.
  factory Provider.stream(Stream<T> stream, {T initialValue}) =>
      _StreamProvider<T>(stream, initialValue: initialValue);
}

/// Base mixin for providers.
abstract class TypedProvider<T> implements Provider<T> {
  /// The type of the provider
  @override
  Type get type => T;
}

/// A widget that obtains the given value from the nearest provider and rebuilds
/// using the [builder] whenever it changes.
///
/// Either the provider or the value must implement [Listenable]. To obtain a
/// value without listening to changes, the static [Provide.value<T>] function
/// should be used instead.
///
/// To improve performance by having less rebuilds, the part of the tree rebuilt
/// by builder should be minimized by putting as much of the tree in [child] as
/// possible, or using the static function.
/// If no scope is provided, the default one will be used.
class Provide<T> extends StatelessWidget {
  /// Called whenever there is a change.
  final ValueBuilder<T> builder;

  /// The part of the widget tree not rebuilt on change.
  final Widget child;

  /// The scope from which the type is requested
  final ProviderScope scope;

  /// Constructor.
  const Provide({@required this.builder, this.child, this.scope});

  /// Used to obtain provided values without listening to their changes.
  static T value<T>(BuildContext context, {ProviderScope scope}) {
    final provider = _InheritedProviders.of(context).getValue<T>(scope: scope);
    assert(provider != null);

    return provider.get(context);
  }

  /// Used to obtain provided values in the form of a stream that sends its
  /// value on change.
  static Stream<T> stream<T>(BuildContext context, {ProviderScope scope}) {
    final provider = _InheritedProviders.of(context).getValue<T>(scope: scope);
    assert(provider != null);

    return provider.stream(context);
  }

  @override
  Widget build(BuildContext context) {
    final provider = _InheritedProviders.of(context).getValue<T>(scope: scope);
    final value = provider.get(context);
    final listenable = _getListenable(provider, value);

    if (provider is Listenable) {
      return ListeningBuilder(
        listenable: listenable,
        child: child,
        builder: (buildContext, child) =>
            builder(buildContext, child, provider.get(context)),
      );
    } else if (value is Listenable) {
      return ListeningBuilder(
        listenable: listenable,
        child: child,
        builder: (buildContext, child) => builder(buildContext, child, value),
      );
    }

    throw ArgumentError('Either the type or the provider of it must'
        ' implement listenable. To get a non-listenable value, use the static'
        ' Provide.value<T>.');
  }
}

/// Pass in value as well to avoid calling provider.get multiple times because
/// that could have side effects for some provider types.
Listenable _getListenable(Provider provider, dynamic value) =>
    provider is Listenable ? provider : value is Listenable ? value : null;

/// Widget that rebuilds on change using multiple values provided by a
/// [ProviderNode].
///
/// [ProvideMulti] is the functional equivalent of chained [Provide] widgets.
/// It will call builder whenever any of the requested values changes.
///
/// As with [Provide], the builder should just build as little as possible to
/// optimize performance.
class ProvideMulti extends StatelessWidget {
  /// A set of requested values per scope
  final Map<ProviderScope, List<Type>> requestedScopedValues;

  /// Is called each time any of the [requestedValues] changes
  final MultiValueBuilder builder;

  /// The part of the widget tree not rebuilt on change.
  final Widget child;

  /// Both [requestedValues] and [requestedScopedValues] can be passed
  /// in at the same time.
  ProvideMulti({
    @required this.builder,
    this.child,
    List<Type> requestedValues,
    Map<ProviderScope, List<Type>> requestedScopedValues,
  }) : requestedScopedValues = {}
          ..addAll(requestedScopedValues ?? {})
          ..putIfAbsent(Providers.defaultScope, () => requestedValues ?? []);

  @override
  Widget build(BuildContext context) {
    final providers = _InheritedProviders.of(context);

    final values = <ProviderScope, Map<Type, dynamic>>{};
    final listenables = <Listenable>[];

    for (final providerScope in requestedScopedValues.keys) {
      for (final type in requestedScopedValues[providerScope]) {
        final provider = providers.getFromType(type, scope: providerScope);
        final value = provider.get(context);
        listenables.add(_getListenable(provider, value));
        (values[providerScope] ??= {})[type] = value;
      }
    }

    return ListeningBuilder(
      listenable: _MergedListenable(listenables),
      child: child,
      builder: (buildContext, child) =>
          builder(buildContext, child, _update(context, values)),
    );
  }

  // When the provider is the one that is changing instead of the value,
  // the values in the map returned need to be updated.
  ProvidedValues _update(
      BuildContext context, Map<ProviderScope, Map<Type, dynamic>> values) {
    final providers = _InheritedProviders.of(context);

    for (final providerScope in requestedScopedValues.keys) {
      for (final type in requestedScopedValues[providerScope]) {
        final provider = providers.getFromType(type, scope: providerScope);
        if (provider is Listenable) {
          final value = provider.get(context);
          values[providerScope][type] = value;
        }
      }
    }

    return ProvidedValues._(values);
  }
}

/// A container for the values passed to the [MultiValueBuilder].
class ProvidedValues {
  final Map<ProviderScope, Map<Type, dynamic>> _values;

  /// Should only be called by ProvideMulti.
  ProvidedValues._(this._values);

  /// Gets the value in question.
  /// [T] must be a type passed in as part of [requestedValues].
  T get<T>({ProviderScope scope}) =>
      _values[scope ?? Providers.defaultScope][T];
}

/// Builds a child for a [Provide] widget.
typedef ValueBuilder<T> = Widget Function(
  BuildContext context,
  Widget child,
  T value,
);

/// Builds a child for a [ProvideMulti] widget.
typedef MultiValueBuilder = Widget Function(
  BuildContext context,
  Widget child,
  ProvidedValues values,
);

/// Contains a value which will never be disposed.
class _ValueProvider<T> extends TypedProvider<T> {
  final T _value;
  StreamController _streamController;

  @override
  T get(BuildContext context) => _value;

  @override
  Stream<T> stream(BuildContext context) {
    final value = _value;
    if (value is Listenable) {
      _streamController ??= StreamController<T>.broadcast();
      value.addListener(_streamListener);
    } else {
      throw UnsupportedError(
          'Cannot create stream from a value that is not Listenable');
    }

    return _streamController.stream;
  }

  _ValueProvider(this._value);

  @override
  Future<void> dispose() async {
    final value = _value;
    if (value is Listenable) {
      value.removeListener(_streamListener);
    }
    await _streamController?.close();
  }

  void _streamListener() {
    _streamController?.add(_value);
  }
}

/// Function that returns an instance of T when called.
typedef ProviderFunction<T> = T Function(BuildContext context);

/// Is initialized on demand, and disposed when no longer needed
/// if [dispose] is set to true.
/// When obtained statically, the value will never be disposed.
class _LazyProvider<T> extends ChangeNotifier with TypedProvider<T> {
  final ProviderFunction<T> _initalizer;

  T _value;
  StreamController _streamController;

  _LazyProvider(this._initalizer);

  @override
  Future<void> dispose() async {
    final value = _value;
    if (value is Listenable) {
      value..removeListener(_streamListener)..removeListener(notifyListeners);
    }
    await _streamController?.close();
    _value = null;
    super.dispose();
  }

  @override
  T get(BuildContext context) {
    // Need to have a local copy for casting because
    // dart requires it.
    T value;
    if (_value == null) {
      value = _value ??= _initalizer(context);
      if (value is Listenable) {
        value.addListener(notifyListeners);
      }
    }
    return _value;
  }

  @override
  Stream<T> stream(BuildContext context) {
    final value = _value;
    if (value is Listenable) {
      _streamController ??= StreamController<T>.broadcast();
      value.addListener(_streamListener);
    } else {
      throw UnsupportedError(
          'Cannot create stream from a value that is not Listenable');
    }

    return _streamController.stream;
  }

  void _streamListener() {
    _streamController?.add(_value);
  }
}

/// A provider who's value is obtained from providerFunction for each time the
/// value is requested.
///
/// This provider doesn't keep any values itself, so those values are disposed
/// when the containing widget is disposed.
class _FactoryProvider<T> with TypedProvider<T> {
  final ProviderFunction<T> providerFunction;

  _FactoryProvider(this.providerFunction);

  @override
  T get(BuildContext context) => providerFunction(context);

  @override
  Stream<T> stream(BuildContext context) =>
      throw UnsupportedError('Stream not supported for factory providers');

  @override
  Future<void> dispose() async {}
}

/// Provider that takes a stream.
///
/// This provider will always listen and cache the last value received from
/// the stream, and notify listeners when there's a change.
class _StreamProvider<T> extends ChangeNotifier with TypedProvider<T> {
  final Stream<T> _stream;
  T _lastValue;
  StreamSubscription _listener;

  /// Immediately starts listening to the stream and caching values.
  _StreamProvider(Stream<T> stream, {T initialValue})
      : _lastValue = initialValue,
        _stream = stream.isBroadcast ? stream : stream.asBroadcastStream() {
    _listener = _stream.listen((data) {
      if (_lastValue != data) {
        _lastValue = data;
        notifyListeners();
      }
    });
  }

  @override
  Stream<T> stream(BuildContext context) => _stream;

  @override
  T get(BuildContext context) => _lastValue;

  @override
  Future<void> dispose() async {
    await _listener.cancel();
    super.dispose();
  }
}

/// Put in the widget tree through [ProviderNode].
///
/// Used to be able to find through inheritFromWidgetOfExactType.
class _InheritedProviders extends InheritedWidget {
  /// The next _InheritedProvider up in the widget tree.
  /// The topmost one will always be null.
  final _InheritedProviders parent;

  final Providers providers;

  const _InheritedProviders({Widget child, this.providers, this.parent})
      : super(child: child);

  /// Finds the closest _InheritedProviders widget abocve the current widget.
  static _InheritedProviders of(BuildContext context) {
    final widget = context.inheritFromWidgetOfExactType(_InheritedProviders);
    return widget is _InheritedProviders ? widget : null;
  }

  @override
  bool updateShouldNotify(_InheritedProviders oldWidget) {
    return parent?.updateShouldNotify(oldWidget.parent) ??
        false || providers != oldWidget.providers;
  }

  /// This is more type-safe than getFromType.
  Provider<T> getValue<T>({ProviderScope scope}) {
    return providers.getFromType(T, scope: scope) ??
        parent?.getValue<T>(scope: scope);
  }

  /// Needed because this works at runtime for ProvideMulti.
  Provider getFromType(Type type, {ProviderScope scope}) {
    return providers.getFromType(type, scope: scope) ??
        parent?.getFromType(type, scope: scope);
  }
}

/// Widget that rebuilds part of the widget tree whenever
/// the [listenable] changes.
///
/// [builder] is called on [listenable] changing. [child] is not rebuilt,
/// but is passed to the [builder].
/// This has identical behavior to [AnimatedBuilder], but is clearer about
/// intent.
class ListeningBuilder extends AnimatedWidget {
  /// Constructs a new [ListeningBuilder].
  const ListeningBuilder({
    @required Listenable listenable,
    @required this.builder,
    Key key,
    this.child,
  })  : assert(builder != null),
        super(key: key, listenable: listenable);

  /// Called every time the listenable changes value.
  final TransitionBuilder builder;

  /// The child widget to pass to the [builder].
  ///
  /// If a [builder] callback's return value contains a subtree that does not
  /// depend on the listenable, it's more efficient to build that subtree once
  /// instead of rebuilding it on every change.
  ///
  /// If the pre-built subtree is passed as the [child] parameter, the
  /// [ListeningBuilder] will pass it back to the [builder] function so that it
  /// can be incorporated into the build.
  ///
  /// Using this pre-built child is entirely optional, but can improve
  /// performance significantly in some cases and is therefore a good practice.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}

/// Listenable that only listens to its children when it has listeners.
///
/// The default implementation of Listenable.merge only removes
/// on disposal, which isn't called by the listening widgets, thus
/// causing a potential memory leak.
class _MergedListenable extends ChangeNotifier {
  final List<Listenable> _children;

  _MergedListenable(this._children);

  @override
  void dispose() {
    if (hasListeners) {
      _unlisten();
    }
    super.dispose();
  }

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) {
      for (final child in _children) {
        child?.addListener(notifyListeners);
      }
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _unlisten();
    }
  }

  void _unlisten() {
    for (final child in _children) {
      child?.removeListener(notifyListeners);
    }
  }
}

**NOTE 2019-02-21:** There's a discussion in the Flutter community over the difference between this
package, `package:provider`, and `package:scoped_model`. There is a possibility that (some)
of these efforts will merge. Learn more in issue
[#3](https://github.com/google/flutter-provide/issues/3).

If you must choose a package today, it's safer to go with `package:scoped_model` than with this
package.

Watch the issue above or follow [Flutter's Twitter account](https://twitter.com/flutterio)
for updates.

---

This package contains classes to allow the passing of data down the widget tree.
It is designed as a replacement for `ScopedModel` that allows for more
flexible handling of data types and data.

## Key widgets and static methods

  * `Provide<T>` - Widget used to obtain values from a `ProviderNode` higher up
  in the widget tree and rebuild on change. The `Provide<T>` widget should
  only be used with `Stream`s or `Listenable`s. Equivalent to
  `ScopedModelDescendant` in `ScopedModel`.

  * `Provide.value<T>` - Static method used to get a value from a `ProviderNode`
  using the `BuildContext`. This will not rebuild on change. Similar to manually
  writing a static `.of()` method for an `InheritedWidget`.

  * `Provide.stream<T>` - Static method used to get a `Stream` from a
  `ProviderNode`. Only works if either `T` is listenable, or if the
  `Provider` comes from a `Stream`.

  * `Provider<T>` - A class that returns a typed value on demand. Stored in
  a `ProviderNode` to allow retrieval using `Provide`.

  * `ProviderNode` - The equivalent of the `ScopedModel` widget. Contains
  `Providers` which can be found as an `InheritedWidget`.

## Usage

This is a simple example of a counter app:

```dart

/// A provide widget can rebuild on changes to any class that implements
/// the listenable interface.
///
/// Here, we mixin ChangeNotifier so we don't need to manage listeners
/// ourselves.
///
/// Extending ValueNotifier<int> would be another simple way to do this.
class Counter with ChangeNotifier {
  int _value;

  int get value => _value;

  Counter(this._value);

  void increment() {
    _value++;
    notifyListeners();
  }
}

/// CounterApp which obtains a counter from the widget tree and uses it.
class CounterApp extends StatelessWidget {
  // The widgets here get the value of Counter in three different
  // ways.
  //
  // - Provide<Counter> creates a widget that rebuilds on change
  // - Provide.value<Counter> obtains the value directly
  // - Provide.stream<Counter> returns a stream
  @override
  Widget build(BuildContext context) {
    // Gets the Counter from the nearest ProviderNode that contains a Counter.
    // This does not cause this widget to rebuild when the counter changes.
    final currentCounter = Provide.value<Counter>(context);

    return Column(children: [
      // Simplest way to retrieve the provided value.
      //
      // Each time the counter changes, this will get rebuilt. This widget
      // requires the value to be a Listenable or a Stream. Otherwise
      Provide<Counter>(
        builder: (context, child, counter) => Text('${counter.value}'),
      ),

      // This widget gets the counter as a stream of changes.
      // The stream is filtered so that this only rebuilds on even numbers.
      StreamBuilder<Counter>(
          initialData: currentCounter,
          stream: Provide.stream<Counter>(context)
              .where((counter) => counter.value % 2 == 0),
          builder: (context, snapshot) =>
              Text('Last even value: ${snapshot.data.value}')),

      // This button just needs to call a method on Counter. No need to rebuild
      // it as the value of Counter changes. Therefore, we can use the value of
      // `Provide.value<Counter>` from above.
      FlatButton(child: Text('increment'), onPressed: currentCounter.increment),

      Text('Another widget that does not depend on the Counter'),
    ]);
  }
}

void main() {
    // The class that contains all the providers. This shouldn't change after
    // being used.
    //
    // In this case, the Counter gets instantiated the first time someone uses
    // it, and lives as a singleton after that.
    final providers = Providers()
      ..provide(Provider.function((context) => Counter(0)));

    runApp(ProviderNode(
      providers: providers,
      child: CounterApp(),
    ));
}

```

## How it works
Similar to `ScopedModel`, this relies on `InheritedWidget`s in order to
propagate data up and down the widget tree. However, unlike `ScopedModel`,
rather than storing a single concrete type, a `ProviderNode` contains a map of
`Type`s to `Provider`s. This means that a single node can contain any number of
providers, and that a provider of a type doesn't have to be of the exact
concrete type.

Somewhere in the tree, there is a `ProviderNode`, which contains a set of
`Provider`s. When a `Provide` widget is created, it searches up the widget tree
for a `ProviderNode` that contains a provider for its requested type. It then
listens for any changes to that requested type.

There are also static methods that operate on `BuildContext` that allow any
widget's build function to get data from `ProviderNode`s without listening to
changes directly.


## Useful widgets to use with Provider
* [ChangeNotifier](https://docs.flutter.io/flutter/foundation/ChangeNotifier-class.html)
  — Easy way to implement Listenable. The equivalent of `Model` from
  `ScopedModel`.

* [ValueNotifier](https://docs.flutter.io/flutter/foundation/ValueNotifier-class.html)
  — Wrapping your mutable state in `ValueNotifier<T>` can save you from
  missing `notifyListener` calls.

* [StreamBuilder](https://docs.flutter.io/flutter/widgets/StreamBuilder-class.html)
  — Can be used with `Provide.stream` to have widgets that rebuild on
  stream changes.


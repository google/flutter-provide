// Copyright 2018 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:provide/provide.dart';
import 'package:scoped_model/scoped_model.dart';
import 'package:test/test.dart' as package_test;

const ProviderScope scope1 = ProviderScope('scope1');
const ProviderScope scope2 = ProviderScope('scope2');

void main() {
  Providers providers;

  setUp(() {
    providers = Providers();
  });

  group('Providers', () {
    BuildContext buildContext;

    setUp(() {
      buildContext = MockBuildContext();
    });

    test('disposes all of its providers', () async {
      final mock1 = MockProvider<int>();
      when(mock1.type).thenReturn(int);
      final mock2 = MockProvider<int>();
      when(mock2.type).thenReturn(int);

      providers..provide(mock1)..provide(mock2, scope: scope2);

      await providers.dispose();

      verify(mock1.dispose()).called(1);
      verify(mock2.dispose()).called(1);
    });

    test('can set and retreive a single value', () {
      const value = 'value';
      const otherValue = 'otherValue';

      providers.provideValue(value);
      final provider = providers.getFromType(String);
      expect(provider.get(buildContext), value);

      providers.provideValue(otherValue);
      final otherProvider = providers.getFromType(String);
      expect(otherProvider.get(buildContext), otherValue);
    });
    test('can provide and retreive various kinds of providers', () async {
      final streamController = StreamController<String>.broadcast();
      var functionCounter = 0;
      var factoryCounter = 0;

      providers
        ..provide(Provider.withFactory((buildContext) {
          return factoryCounter++;
        }))
        ..provideAll({
          String: Provider<String>.stream(streamController.stream),
          SampleClass: Provider<SampleClass>.function((buildContext) {
            final value = SampleClass('function $functionCounter');
            functionCounter++;
            return value;
          }),
        })
        ..provide(SampleProvider());

      // Must wait one async cycle for value to propagate.
      streamController.add('stream');
      await new Future.delayed(Duration.zero);

      expect(providers.getFromType(String).get(buildContext), 'stream');
      expect(providers.getFromType(String).get(buildContext), 'stream');

      // Must wait one async cycle for value to propagate.
      streamController.add('stream2');
      await new Future.delayed(Duration.zero);

      expect(providers.getFromType(String).get(buildContext), 'stream2');

      expect(providers.getFromType(SampleClass).get(buildContext).value,
          'function 0');
      expect(providers.getFromType(SampleClass).get(buildContext).value,
          'function 0');

      expect(providers.getFromType(int).get(buildContext), 0);
      expect(providers.getFromType(int).get(buildContext), 1);

      expect(providers.getFromType(double).get(buildContext), 1.1);

      // Copied providers should have the same providers as original.
      final copiedProviders = Providers()..provideFrom(providers);
      expect(copiedProviders.getFromType(String).get(buildContext), 'stream2');
      expect(copiedProviders.getFromType(SampleClass).get(buildContext).value,
          'function 0');
      expect(copiedProviders.getFromType(int).get(buildContext), 2);
      expect(copiedProviders.getFromType(double).get(buildContext), 1.1);

      await streamController.close();
    });
    test('Throws errors when type incorrect', () {
      // incorrect type
      expect(() => providers.provideAll({String: Provider.value(32)}),
          throwsA(package_test.TypeMatcher<ArgumentError>()));
      // provider type not inferred
      expect(() => providers.provideAll({String: Provider.value('')}),
          throwsA(package_test.TypeMatcher<ArgumentError>()));
    });

    test('can handle multiple scopes', () {
      providers
        ..provideValue(1, scope: scope1)
        ..provide(Provider.value(2), scope: scope2)
        ..provideValue(360);

      expect(providers.getFromType(int).get(buildContext), 360);
      expect(providers.getFromType(int, scope: scope1).get(buildContext), 1);
      expect(providers.getFromType(int, scope: scope2).get(buildContext), 2);

      final other = Providers()..provideFrom(providers);
      expect(other.getFromType(int).get(buildContext), 360);
      expect(other.getFromType(int, scope: scope1).get(buildContext), 1);
      expect(other.getFromType(int, scope: scope2).get(buildContext), 2);

      // overwriting in the same scope
      providers.provideValue(3, scope: scope1);
      expect(providers.getFromType(int, scope: scope1).get(buildContext), 3);

      providers.provideAll(
          {double: Provider<double>.function((buildContext) => 1.0)},
          scope: scope2);

      expect(
          providers.getFromType(double, scope: scope2).get(buildContext), 1.0);
    });
  });

  group('Provide', () {
    FakeModel model;
    SampleClass sampleClass;
    ValueNotifier<String> notifier;
    StreamController<int> broadcastController;
    StreamController<double> singleStreamController;

    setUp(() async {
      model = FakeModel();
      sampleClass = SampleClass('value');
      notifier = ValueNotifier<String>('valueNotifier');
      broadcastController = StreamController<int>.broadcast();
      singleStreamController = StreamController<double>();

      providers
        ..provideValue(model)
        ..provideValue(notifier)
        ..provide(Provider.stream(broadcastController.stream))
        ..provide(Provider.stream(singleStreamController.stream), scope: scope1)
        ..provideValue(sampleClass, scope: scope2)
        // a provider that uses other provided values when accessed
        ..provide(Provider.function((context) => SampleClass(
            Provide.value<SampleClass>(context, scope: scope2).value)));

      broadcastController.add(1);
      singleStreamController.add(1.0);

      // wait for the values to propagate
      await Future.delayed(Duration.zero);
    });

    testWidgets('can get static values', (tester) async {
      await tester.pumpWidget(ProviderNode(
          providers: providers,
          child: TesterWidget(
              expectedInt: 1,
              expectedDouble: 1.0,
              expectedSampleClass: sampleClass,
              expectedModel: model,
              expectedString: 'valueNotifier')));
    });

    testWidgets('can get initial value from stream', (tester) async {
      final broadcastController = StreamController<int>.broadcast();
      final providers = Providers()
        ..provide(Provider.stream(broadcastController.stream, initialValue: 3));
      var buildCalled = false;

      final widget = ProviderNode(
          providers: providers,
          child: CallbackWidget((context) {
            buildCalled = true;
            expect(Provide.value<int>(context), 3);
          }));

      await tester.pumpWidget(widget);
      expect(buildCalled, isTrue);
      await broadcastController.close();
    });

    testWidgets('can get streams', (tester) async {
      var buildCalled = false;

      Stream<double> doubleStream;
      Stream<int> intStream;
      Stream<ValueNotifier<String>> stringStream;

      final widget = ProviderNode(
          providers: providers,
          child: CallbackWidget((context) {
            buildCalled = true;
            doubleStream = Provide.stream<double>(context, scope: scope1);
            intStream = Provide.stream<int>(context);
            stringStream = Provide.stream<ValueNotifier<String>>(context);
          }));

      await tester.pumpWidget(widget);
      expect(buildCalled, isTrue);

      expect(doubleStream, emitsInOrder([2.0, 3.0, 4.0]));
      singleStreamController..add(2.0)..add(3.0)..add(4.0);

      expect(intStream, emitsInOrder([2, 3, 4]));
      broadcastController..add(2)..add(3)..add(4);

      expect(stringStream.map((notifier) => notifier.value),
          emitsInOrder(['two', 'three', 'four']));
      notifier.value = 'two';
      await tester.pumpAndSettle();
      notifier.value = 'three';
      await tester.pumpAndSettle();
      notifier.value = 'four';
    });

    testWidgets('can get listened values', (tester) async {
      var buildCalled = false;
      var expectedValue = 0;

      final widget = ProviderNode(
        providers: providers,
        child: Provide<FakeModel>(builder: (context, child, value) {
          expect(value.value, expectedValue);
          buildCalled = true;
          return Container();
        }),
      );

      await tester.pumpWidget(widget);
      expect(buildCalled, isTrue);

      buildCalled = false;
      expectedValue++;
      model.increment();

      await tester.pumpAndSettle();
      expect(buildCalled, isTrue);
    });

    testWidgets('can get multi level dependencies', (tester) async {
      var buildCalled = false;
      final expectedValue = sampleClass.value;

      final widget = ProviderNode(
        providers: providers,
        child: Provide<SampleClass>(builder: (context, child, value) {
          expect(value.value, expectedValue);
          buildCalled = true;
          return Container();
        }),
      );

      await tester.pumpWidget(widget);
      expect(buildCalled, isTrue);
    });

    testWidgets('can get listened streams', (tester) async {
      var buildCalled = false;
      var expectedValue = 1.0;

      final widget = ProviderNode(
        providers: providers,
        child: Provide<double>(
            scope: scope1,
            builder: (context, child, value) {
              expect(value, expectedValue);
              buildCalled = true;
              return Container();
            }),
      );

      await tester.pumpWidget(widget);
      expect(buildCalled, isTrue);

      buildCalled = false;
      expectedValue = 2.0;
      singleStreamController.add(2.0);
      await tester.pumpAndSettle();
      expect(buildCalled, isTrue);
    });

    testWidgets('disposes streams when done', (tester) async {
      var buildCalled = false;

      final widget = ProviderNode(
          providers: providers,
          child: CallbackWidget((context) {
            Provide.stream<FakeModel>(context);
            buildCalled = true;
          }));
      await tester.pumpWidget(widget);
      expect(buildCalled, true);
      expect(broadcastController.hasListener, isTrue);
      expect(model.listenerCount, 1);
      await tester.pumpWidget(Container());
      expect(broadcastController.hasListener, isFalse);
      expect(model.listenerCount, 0);
    });

    testWidgets('does not streams if dispose is false', (tester) async {
      var buildCalled = false;

      final widget = ProviderNode(
          dispose: false,
          providers: providers,
          child: CallbackWidget((context) {
            Provide.stream<FakeModel>(context);
            buildCalled = true;
          }));
      await tester.pumpWidget(widget);
      expect(buildCalled, true);
      expect(broadcastController.hasListener, isTrue);
      expect(model.listenerCount, 1);
      await tester.pumpWidget(Container());
      expect(broadcastController.hasListener, isTrue);
      expect(model.listenerCount, 1);
    });

    testWidgets('can get many listened values', (tester) async {
      var buildCalled = false;

      var expectedString = 'valueNotifier';
      var expectedInt = 1;
      var expectedDouble = 1.0;

      final widget = ProviderNode(
        providers: providers,
        child: ProvideMulti(
            requestedValues: [
              // This seems to be a bug; can't parse a generic type in an array literal?
              ValueNotifier<String>('').runtimeType,
              int,
            ],
            requestedScopedValues: {
              scope1: [double]
            },
            builder: (context, child, value) {
              expect(value.get<ValueNotifier<String>>().value, expectedString);
              expect(value.get<int>(), expectedInt);
              expect(value.get<double>(scope: scope1), expectedDouble);

              buildCalled = true;
              return Container();
            }),
      );

      await tester.pumpWidget(widget);
      expect(buildCalled, isTrue);

      buildCalled = false;
      expectedString = 'updated';
      notifier.value = 'updated';
      await tester.pumpAndSettle();
      expect(buildCalled, isTrue);

      buildCalled = false;
      expectedInt = 2;
      broadcastController.add(2);
      await tester.pumpAndSettle();
      expect(buildCalled, isTrue);

      buildCalled = false;
      expectedDouble = 2.0;
      singleStreamController.add(2.0);
      await tester.pumpAndSettle();
      expect(buildCalled, isTrue);
    });

    testWidgets('does not rebuild child', (tester) async {
      var childBuilds = 0;
      var builderBuilds = 0;

      final callbackChild = CallbackWidget((_) {
        childBuilds++;
      });

      await tester.pumpWidget(ProviderNode(
          providers: providers,
          child: Provide<FakeModel>(
              builder: (context, child, model) {
                return CallbackWidget((_) {
                  builderBuilds++;
                }, child: child);
              },
              child: callbackChild)));
      expect(childBuilds, 1);
      expect(builderBuilds, 1);

      await tester.pumpAndSettle();
      expect(childBuilds, 1);
      expect(builderBuilds, 1);

      model.increment();
      await tester.pumpAndSettle();
      expect(childBuilds, 1);
      expect(builderBuilds, 2);
    });

    tearDown(() {
      singleStreamController.close();
      broadcastController.close();
    });
  });
}

class MockBuildContext extends Mock implements BuildContext {}

class MockProvider<T> extends Mock implements Provider<T> {}

class SampleClass {
  String value;
  SampleClass(this.value);
}

class SampleProvider extends TypedProvider<double> {
  @override
  double get(BuildContext context) => 1.1;

  @override
  Stream<double> stream(BuildContext context) => null;

  @override
  Future<void> dispose() async => null;
}

class FakeModel extends Model {
  int _value = 0;

  int get value => _value;

  void increment() {
    _value++;
    notifyListeners();
  }
}

class FakeModel2 extends FakeModel {}

class CallbackWidget extends StatelessWidget {
  final void Function(BuildContext) callback;
  final Widget child;

  const CallbackWidget(this.callback, {this.child});

  @override
  Widget build(BuildContext context) {
    callback(context);
    return child ?? Container();
  }
}

class TesterWidget extends StatelessWidget {
  final int expectedInt;
  final double expectedDouble;
  final String expectedString;
  final SampleClass expectedSampleClass;
  final FakeModel expectedModel;

  const TesterWidget(
      {this.expectedDouble,
      this.expectedSampleClass,
      this.expectedInt,
      this.expectedModel,
      this.expectedString});

  @override
  Widget build(BuildContext context) {
    expect(Provide.value<int>(context), expectedInt);
    expect(Provide.value<double>(context, scope: scope1), expectedDouble);
    expect(Provide.value<ValueNotifier<String>>(context).value, expectedString);
    expect(Provide.value<FakeModel>(context), expectedModel);
    expect(Provide.value<SampleClass>(context, scope: scope2),
        expectedSampleClass);

    return Container();
  }
}

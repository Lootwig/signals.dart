import 'package:signals/signals_flutter.dart';
import 'package:flutter/material.dart';

//ignore_for_file: unused_local_variable
void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Flutter',
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with SignalsMixin {
  late final counter = this.createSignal(1);

  Signal field() => counter;

  Signal get sameFileGetter => Signal(1);

  @override
  Widget build(BuildContext context) {
    var counter3 = Counter(1);
    //final counterX = () => sameFileGetter;
    final counter2 = sameFileGetter;

    final third = counter3;
    final other = Counter(2).y;
    final nun = counter3.externalGetter;
    this.createSignal(123);

    Signal(33);
    final n = Signal(1);
    return Text('Count: $third $n');
  }
}

class NoConstructor {
  final iCreateANewFieldWhenInstantiated = Signal(3);
}

class Counter extends ValueNotifier<int> {
  Counter(super.value);

  final x = Signal(4);
  final y = Counter(1).x;

  Signal get externalGetter => Signal(1);
}

class WithLateMapSignal {
  MapSignal get signal => MapSignal({});
  //late final signal = MapSignal({});
}

extension on BuildContext {
  T read<T>() => Object as T;
}

class ReadingWidget extends StatelessWidget {
  const ReadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    context.read<WithLateMapSignal>().signal;
    final WithLateMapSignal(:signal) = context.read<WithLateMapSignal>();
    Signal(33);
    return Column(
      children: [
        Watch(
          (c) {
            return Row(
              children: [Text(signal.value['']!), Text('${signal['']!}')],
            );
          },
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart' show ErrorSeverity;
import 'package:analyzer/error/listener.dart';
// ignore: implementation_imports
import 'package:analyzer/src/dart/ast/utilities.dart';
// ignore: implementation_imports
import 'package:analyzer/src/dart/micro/utils.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:signals/signals.dart';
import 'package:signals_lint/src/lints/extensions.dart';
import 'package:signals_lint/src/utils.dart';
import 'package:stream_transform/stream_transform.dart';

class DebugMessage extends LintCode {
  const DebugMessage(String message)
      : super(
          name: 'debug',
          errorSeverity: ErrorSeverity.INFO,
          problemMessage: message,
        );
}

extension on Stopwatch {
  String get format {
    try {
      return (elapsedMilliseconds / 1000).toStringAsFixed(3);
    } finally {
      reset();
    }
  }
}

extension<T> on Iterable<T> {
  Iterable<T> whereNotIn(Iterable<T> other) =>
      toSet().difference(other.toSet());
}

extension on AnalysisSession {
  Stream<ResolvedLibraryResult> _recurseExports(
    ResolvedLibraryResult resolvedResult, [
    Set<ResolvedLibraryResult>? resolvedResults,
  ]) {
    final results = {resolvedResult, ...?resolvedResults};
    final exports = resolvedResult.element.libraryExports
        .mapNonNull((e) => e.exportedLibrary)
        .whereNotIn(results.map((l) => l.element));
    return Stream.fromIterable(exports)
        .concurrentAsyncMap(getResolvedLibraryByElement)
        .whereType<ResolvedLibraryResult>()
        .concurrentAsyncExpand((result) async* {
      yield result;
      yield* _recurseExports(result, {result, ...results});
    });
  }

  Future<ResolvedLibraryResult> _resolveFlutterSignalsLib() async {
    final libraryPath = uriConverter
        .uriToPath(Uri.parse('package:signals/signals_flutter.dart'));
    if (libraryPath == null) {
      throw Exception('Could not resolve signals_flutter library.');
    }

    final resolvedSignalsLibrary = await getResolvedLibrary(libraryPath)
        .asyncCast<ResolvedLibraryResult>();
    if (resolvedSignalsLibrary == null) {
      throw Exception('Could not resolve signals_flutter library.');
    }
    return resolvedSignalsLibrary;
  }
}

class SignalsAvoidCreateInBuildMethod extends DartLintRule {
  final entryPoints = <Element>{};

  SignalsAvoidCreateInBuildMethod() : super(code: const DebugMessage('pg'));

  @override
  Future<void> startUp(
    CustomLintResolver resolver,
    CustomLintContext context,
  ) async {
    await super.startUp(resolver, context);
    final decodedFile = (await resolver.getResolvedUnitResult());

    final session = decodedFile.session;
    final resolvedSignalsLibrary = await session._resolveFlutterSignalsLib();

    final signalLibs =
        await session._recurseExports(resolvedSignalsLibrary).toSet();

    final visitor = EntryPointVisitor(entryPoints);
    final epSignal = entryPoints.toSignal();
    final entryPointCount = epSignal
        .select((set) => set.value.length)
        .select((signal) => signal.value > (signal.previousValue ?? 0))
      ..subscribe((_) => print('abc'));
    for (final node in [
      ...signalLibs.expand((e) => e.units),
      decodedFile,
    ]) {
      do {
        node.unit.declarations.accept(visitor);
      } while (entryPointCount.value);
    }
    epSignal.dispose();
  }

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    print('starting run');
    void logAt(AstNode node, String message) {
      reporter.atNode(node, DebugMessage(message));
    }

    final r = context.registry;

    r.addInstanceCreationExpression(
      (node) {
        if (!node.withinBuild()) return;
        final constructors = entryPoints
            .whereType<ConstructorElement>()
            .map((e) => e.returnType)
            .nonNulls
            .map(TypeChecker.fromStatic)
            .toSet();

        final calls = constructors
            .where((checker) => checker.isExactlyType(node.staticType!))
            .toSet();
        if (calls.isNotEmpty) {
          if (!node.staticType.isSignal) {
            logAt(node,
                'While not itself a signal, this class creates new signals on instantiation. Consider accessing an instance created outside the build.');
          } else
            logAt(
              node,
              'Move this instantiation out of the build() method into the Widget\'s state.',
            );
        }
      },
    );

    r.addIdentifier(
      (node) {
        if (!node.withinBuild()) return;
        if (entryPoints.contains(node.staticElement)) {
          logAt(
            node,
            'This invocation causes a Signal to be instantiated (either directly or as a side-effect).',
          );
        }
      },
    );

    r.addPatternAssignment(
      (node) {
        print('found pattern at ${node.pattern.matchedValueType}');
      },
    );
  }
}

class EntryPointVisitor extends GeneralizingAstVisitor<void> {
  final Set<Element> entryPoints;

  EntryPointVisitor(this.entryPoints);

  @override
  visitInvocationExpression(InvocationExpression node) {
    if (entryPoints.contains(switch (node) {
      MethodInvocation(:final methodName) => methodName.staticElement,
      FunctionExpressionInvocation(:final staticElement) => staticElement,
      _ => null,
    })) {
      final references = _findPublicReferences(node);
      entryPoints.addAll(references);
    }
    return super.visitInvocationExpression(node);
  }

  @override
  visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node
        case ConstructorDeclaration(
          isSignal: true,
          declaredElement: != null && final element
        )) {
      entryPoints.add(element);
      entryPoints.addAll(_findPublicReferences(node));
    }
    return super.visitConstructorDeclaration(node);
  }

  @override
  visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (node.staticType?.isSignal ?? false) {
      entryPoints.addAll(_findPublicReferences(node));
    }
    return super.visitInstanceCreationExpression(node);
  }

  @override
  visitFieldDeclaration(FieldDeclaration node) {
    final classDeclaration = node.parent.safeCast<ClassDeclaration>();
    if (node.fields.variables
            .mapNonNull((v) => v.initializer?.staticType?.isSignal)
            .contains(true) &&
        classDeclaration != null) {
      final ClassDeclaration(:members, :declaredElement) = classDeclaration;
      members
          .whereType<ConstructorDeclaration>()
          .mapNonNull((d) => d.declaredElement)
        //..forEach((_) => print(node))
        ..forEach(entryPoints.add);
      if (declaredElement?.unnamedConstructor
          case final Element unnamedConstructor) {
        entryPoints.add(unnamedConstructor);
      } else {
        print('no unnamed for $node');
      }
    }
    return super.visitFieldDeclaration(node);
  }

  Set<Element> _findPublicReferences(AstNode node) {
    final declarations = _getParents(node)
        .whereType<Declaration>()
        .mapNonNull((d) => d.declaredElement)
        .whereType<ExecutableElement>();

    if (declarations.every((e) => e.isPrivate)) {
      final root = node.root;
      for (final privateElement in declarations) {
        final collector = ReferencesCollector(privateElement);
        root.accept(collector);
        final refs = collector.references
            .mapNonNull((r) => NodeLocator(r.offset).searchWithin(root));
        return refs.expand(_findPublicReferences).toSet();
      }
    } else {
      return {...declarations.where((element) => element.isPublic)};
    }
    return {};
  }
}

extension<T> on Iterable<T> {
  Iterable<Out> mapNonNull<Out extends Object>(Out? Function(T t) f) {
    return map(f).nonNulls;
  }
}

List<AstNode> _getParents(AstNode node) {
  final list = <AstNode>[];
  AstNode? e = node;
  while (e != null) {
    list.add(e);
    e = e.parent;
  }
  return list;
}

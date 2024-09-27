import 'dart:async';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/error.dart' show ErrorSeverity;
import 'package:analyzer/error/listener.dart';
// ignore: implementation_imports
import 'package:analyzer/src/dart/ast/utilities.dart';
// ignore: implementation_imports
import 'package:analyzer/src/dart/micro/utils.dart';
import 'package:collection/collection.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:signals_lint/src/lints/extensions.dart';

class DebugMessage extends LintCode {
  const DebugMessage(String message)
      : super(
          name: 'debug',
          errorSeverity: ErrorSeverity.INFO,
          problemMessage: message,
        );
}

class SignalsAvoidCreateInBuildMethod extends DartLintRule {
  final entryPoints = <Declaration>{};

  SignalsAvoidCreateInBuildMethod() : super(code: const DebugMessage('pg'));

  @override
  Future<void> startUp(
      CustomLintResolver resolver, CustomLintContext context) async {
    final t = DateTime.now();
    super.startUp(resolver, context);
    final result = (await resolver.getResolvedUnitResult());

    final session = result.session;
    final lib =
        (await session.getLibraryByUri('package:signals/signals_flutter.dart'));
    if (lib is! LibraryElementResult) return;
    final res = (await session.getResolvedLibraryByElement(lib.element));
    if (res is! ResolvedLibraryResult) return;

    final libs = <ResolvedLibraryResult>{};
    Future<void> recurseExports(LibraryElement element) async {
      final newItems = await element.libraryExports
          .map((e) => e.exportedLibrary)
          .nonNulls
          .whereNot((l) => libs.map((lib) => lib.element).contains(l))
          .map((l) => session.getResolvedLibraryByElement(l))
          .wait;
      final next = newItems.whereType<ResolvedLibraryResult>();
      libs.addAll(next);
      await next.map((r) => recurseExports(r.element)).wait;
    }

    await recurseExports(res.element);

    final units = [res, ...libs].expand((e) => e.units).toList();
    for (final node in [...units, result]) {
      while (true) {
        final hits = {...entryPoints};
        final visitor = EntryPointVisitor(hits);
        node.unit.declarations.accept(visitor);
        if (hits.length > entryPoints.length) {
          final bb = hits
              .difference(entryPoints)
              .where((n) =>
                  n.declaredElement?.librarySource?.fullName.contains('p2') ??
                  false)
              .join('\n');
          //if (bb.isNotEmpty) print('\nfound new refs: ${bb}');
          entryPoints.addAll(hits);
        } else {
          break;
        }
      }
    }
    final ms = (Duration(
                milliseconds: DateTime.now().millisecondsSinceEpoch -
                    t.millisecondsSinceEpoch)
            .inMilliseconds /
        1000);
    print('that took ${ms.toStringAsFixed(3)}s');
  }

  @override
  void run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) {
    void logAt(AstNode node, String message) {
      reporter.atNode(node, DebugMessage(message));
    }

    final r = context.registry;

    r.addInstanceCreationExpression(
      (node) {
        if (!node.withinBuild()) return;
        final constructors = entryPoints
            .whereType<ConstructorDeclaration>()
            .map((e) => e.declaredElement?.returnType)
            .nonNulls
            .map(TypeChecker.fromStatic)
            .toSet();

        final calls = constructors
            .where((checker) => checker.isExactlyType(node.staticType!))
            .toSet();
        if (calls.isNotEmpty) {
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
        final refs =
            entryPoints.where((e) => e.declaredElement == node.staticElement);
        if (refs.isNotEmpty) {
          logAt(
            node,
            'This invocation causes a Signal to be instantiated (either directly or as a side-effect).',
          );
        }
      },
    );
  }
}

class EntryPointVisitor extends GeneralizingAstVisitor {
  final Set<Declaration> entryPoints;

  EntryPointVisitor(this.entryPoints);

  @override
  visitInvocationExpression(InvocationExpression node) {
    if (entryPoints.any((e) {
      return switch (node) {
        MethodInvocation(:final methodName) =>
          methodName.staticElement == e.declaredElement,
        FunctionExpressionInvocation(:final staticElement) =>
          staticElement == e.declaredElement,
        _ => false,
      };
    })) {
      final references = _findPublicReferences(node);
      entryPoints.addAll(references);
    }
    return super.visitInvocationExpression(node);
  }

  @override
  visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.isSignal) {
      entryPoints.add(node);
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
}

Set<Declaration> _findPublicReferences(AstNode node) {
  final declarationParents = _getParents(node)
      .whereType<Declaration>()
      .where((d) => d.declaredElement is ExecutableElement);
  final elements = declarationParents.mapNonNull((d) => d.declaredElement);
  if (elements.every((e) => e.isPrivate)) {
    final root = node.root;
    for (final p in elements) {
      final rc = ReferencesCollector(p);
      root.accept(rc);
      final refs = rc.references
          .mapNonNull((r) => NodeLocator(r.offset).searchWithin(root));
      return refs.expand((r) => _findPublicReferences(r)).toSet();
    }
  } else {
    return declarationParents
        .where((d) => d.declaredElement?.isPublic ?? false)
        .toSet();
  }
  return {};
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

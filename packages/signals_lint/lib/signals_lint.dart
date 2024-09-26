/// Signals linter
library signals_lint;

import 'dart:async';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/src/dart/micro/utils.dart';
import 'package:analyzer/src/dart/ast/utilities.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/error/listener.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'src/fixes/wrap_with_watch.dart';
import 'src/lints/avoid_create_in_build_method.dart';

PluginBase createPlugin() => _SignalsPlugin();

class _SignalsPlugin extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
        //SignalsAvoidCreateInBuildMethod(),
        PlaygroundLint()
      ];

  @override
  List<Assist> getAssists() => [
        WrapWithWatch(),
      ];
}

List<AstNode> getParents(AstNode node) {
  final list = <AstNode>[];
  AstNode? e = node;
  while (e != null) {
    list.add(e);
    e = e.parent;
  }
  return list;
}

class B extends GeneralizingAstVisitor {
  final Set<Declaration> eps;

  B(this.eps);

  @override
  visitConstructorDeclaration(ConstructorDeclaration node) {
    eps.addAll(findPublicReferences(node));
    return super.visitConstructorDeclaration(node);
  }

  @override
  visitInstanceCreationExpression(InstanceCreationExpression node) {
    eps.addAll(findPublicReferences(node));
    return super.visitInstanceCreationExpression(node);
  }
}

class PlaygroundLint extends DartLintRule {
  final entryPoints = <Declaration>{};

  PlaygroundLint() : super(code: DebugMessage('pg'));

  @override
  Future<void> startUp(
      CustomLintResolver resolver, CustomLintContext context) async {
    super.startUp(resolver, context);
    if (entryPoints.isNotEmpty) return;
    var session = (await resolver.getResolvedUnitResult()).session;
    final lib =
        (await session.getLibraryByUri('package:example/playground.dart'));
    if (lib is! LibraryElementResult) return;
    final res = (await session.getResolvedLibraryByElement(lib.element));
    if (res is! ResolvedLibraryResult) return;

    for (final node in res.units.map((u) => u.unit)) {
      var visitor = B(entryPoints);
      node.accept(visitor);
    }
  }

  @override
  void run(CustomLintResolver resolver, ErrorReporter reporter,
      CustomLintContext context) {
    if (resolver.source.uri.path.contains('playground')) {
      return;
    }

    var r = context.registry;

    r.addInstanceCreationExpression(
      (node) {
        print(
          '$node calls lib: ${entryPoints.map((ep) => ep.declaredElement).contains(node.constructorName.staticElement)}',
        );
      },
    );

    r.addInvocationExpression(
      (node) {
        print('$node invokes ${node.function}');
      },
    );
  }
}

Set<Declaration> findPublicReferences(AstNode node) {
  var declarationParents = getParents(node)
      .whereType<Declaration>()
      .where((d) => d.declaredElement is ExecutableElement);
  var elements = declarationParents.mapNonNull((d) => d.declaredElement);
  if (elements.every((e) => e.isPrivate)) {
    final root = node.root;
    for (final p in elements) {
      final rc = ReferencesCollector(p);
      root.accept(rc);
      final refs = rc.references
          .mapNonNull((r) => NodeLocator(r.offset).searchWithin(root));
      return refs.expand((r) => findPublicReferences(r)).toSet();
    }
  } else {
    return declarationParents
        .where((d) => d.declaredElement?.isPublic ?? false)
        .toSet();
  }
  return {};
}

extension on AstNode {
  T? ancestor<T extends AstNode>(bool? Function(T t) test) {
    return thisOrAncestorMatching((node) {
      if (node case T() when test(node) ?? false) return true;
      return false;
    });
  }
}

extension<T> on Iterable<T> {
  Iterable<Out> mapNonNull<Out extends Object>(Out? Function(T t) f) {
    return map(f).nonNulls;
  }
}

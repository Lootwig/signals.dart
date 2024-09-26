import 'dart:async';

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/visitor.dart';
import 'package:analyzer/error/error.dart' show ErrorSeverity;
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/dart/micro/utils.dart';
import 'package:build/build.dart';
import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:signals_lint/src/lints/definitions.dart';
import 'package:signals_lint/src/lints/extensions.dart';
import 'package:signals_lint/src/utils.dart';

class DebugMessage extends LintCode {
  const DebugMessage(String message)
      : super(
          name: 'debug',
          errorSeverity: ErrorSeverity.INFO,
          problemMessage: message,
        );
}

class SignalsAvoidCreateInBuildMethod extends DartLintRule {
  final visitor = SignalConstructorElementVisitor();
  final entryPoints = <Declaration>{};

  SignalsAvoidCreateInBuildMethod() : super(code: lintCode);

  @override
  Future<void> startUp(
    CustomLintResolver resolver,
    CustomLintContext context,
  ) async {
    super.startUp(resolver, context);
    final unitResult = (await resolver.getResolvedUnitResult());
    final analysisSession = unitResult.session;
    final signalsLib = await analysisSession
        .getLibraryByUri('package:signals/signals_flutter.dart');
    final libraryElement = signalsLib.safeCast<LibraryElementResult>()?.element;
    if (libraryElement != null) {
      final resolved =
          await analysisSession.getResolvedLibraryByElement(libraryElement);
      if (resolved case ResolvedLibraryResult()) {
        resolved.element.accept(visitor);
        final collector = InvocationFinder(visitor.constructors);

        final resolvedLibs = await visitor.exportedLibs
            .map((e) => analysisSession.getResolvedLibraryByElement(e))
            .wait;
        for (final u in resolvedLibs
            .whereType<ResolvedLibraryResult>()
            .expand((res) => res.units)) {
          u.unit.root.accept(collector);
        }
        entryPoints.addAll(collector.invocations
                .map((i) => i.thisOrAncestorMatching<Declaration>((a) =>
                    a is Declaration && (a.declaredElement?.isPublic ?? false)))
                .nonNulls
            //    .map((e) => e.declaredElement!.location)
            );
        print(entryPoints.map((ep) => ep).join('\n\n'));
        print(visitor.constructors
            .where((ep) => ep.displayName == 'Signal')
            .map((c) => c.location)
            .join('\n'));
      }
    }
  }

  @override
  Future<void> run(
    CustomLintResolver resolver,
    ErrorReporter reporter,
    CustomLintContext context,
  ) async {
    int lineOf(AstNode node) =>
        resolver.lineInfo.getLocation(node.offset).lineNumber;
    void logOver(int o, int l, String message) {
      reporter.atOffset(offset: o, length: l, errorCode: DebugMessage(message));
    }

    void logAt(AstNode node, String message) {
      reporter.atNode(node, DebugMessage(message));
    }

    //reporter.atOffset(offset: 44, length: 83, errorCode: lintCode);

    /*
    final libraryElement =
        (await resolver.getResolvedUnitResult()).libraryElement;
    final f = BuildMethodFinder();
    libraryElement.accept(f);*/

    //print('i got ${entryPoints.length} points');
    context.registry.addCompilationUnitMember((node) {
      var directiveUris = node.parent
          .safeCast<CompilationUnit>()
          ?.declaredElement
          ?.libraryImports
          .map((i) => i.uri)
          .whereType<DirectiveUriWithLibrary>()
          .where((uri) => uri.library.name == signalsPackage);
      if (directiveUris?.isEmpty ?? true) {
        return;
      }
      void log(String message) => logAt(node, message);
      //final refs = visitor.constructors.map(
      if (node is ClassDeclaration) {
        //print('${node.members}');
        node.members
            .whereType<Declaration>()
            .expand((e) => e.childEntities)
            .whereType<VariableDeclarationList>()
            .expand((e) => e.variables)
            .map((v) => v.initializer)
            .whereType<InvocationExpression>()
            .forEach((e) {
          //final any = visitor.constructors
          //    .any((c) => c == e.constructorName.staticElement);

          //final sc = entryPoints.singleWhere(
          //    (ep) => ep.declaredElement?.displayName == 'createSignal');

          print('${e.function}');
          //print('${e.constructorName.staticElement?.location == sc.location}');
          //entryPoints.where((ep) => ep);
        });
      }
      final refs = entryPoints.map((e) => e.declaredElement).map(
        (constructor) {
          //print('checking refs to ${constructor!}');
          final collector = ReferencesCollector(constructor!);
          node.accept(collector);
          return collector.references.isEmpty
              ? null
              : (constructor.displayName, collector.references);
        },
      ).nonNulls;
      if (refs.isNotEmpty) {
        for (final (name, matches) in refs) {
          for (final match in matches) {
            //print('${match.offset} ${match.length}');
            logOver(match.offset, match.length, "node references $name");
          }
        }
      }
    });
    //context.addPostRunCallback(() => print('$i members'));
  }
}

class InvocationFinder extends GeneralizingAstVisitor<void> {
  final invocations = <AstNode>{};
  final Set<ConstructorElement> targets;
  final accessPoints = <AstNode>{};

  InvocationFinder(this.targets) {
    print('${targets.map((t) => t.displayName).join(', ')}');
  }

  @override
  void visitConstructorName(ConstructorName node) {
    if (targets.contains(node.staticElement?.declaration)) {
      invocations.add(node);
    }
    super.visitConstructorName(node);
  }

  @override
  void visitInvocationExpression(InvocationExpression node) {
    if (node.isSignal) {
      //print('invoking ${node}');
      if (node.function case final SimpleIdentifier i) {}
    }
    super.visitInvocationExpression(node);
  }
}

class BuildMethodFinder extends RecursiveElementVisitor<void> {
  final buildMethodElements = <MethodElement>[];

  @override
  void visitMethodElement(MethodElement element) {
    if (element.isWidgetBuildMethod()) {
      buildMethodElements.add(element);
    }
    element.visitChildren(this);
  }
}

class SignalConstructorElementVisitor extends GeneralizingElementVisitor<void> {
  final constructors = <ConstructorElement>{};
  final exportedLibs = <LibraryElement>{};

  @override
  void visitLibraryElement(LibraryElement element) {
    exportedLibs.add(element);
    element.library.exportedLibraries
        .toSet()
        .difference(exportedLibs)
        .forEach(visitLibraryElement);
    super.visitLibraryElement(element);
  }

  @override
  void visitConstructorElement(ConstructorElement element) {
    if (element.extendsSignal) {
      constructors.add(element);
    }
    super.visitConstructorElement(element);
  }
}

Future<AstNode?> findAstNodeForElement(Element element) async {
  final libraryElement = element.library;
  if (libraryElement == null) return null;
  final parsedLibrary =
      await element.session?.getResolvedLibraryByElement(libraryElement);
  if (parsedLibrary is! ResolvedLibraryResult) return null;

  final declaration = parsedLibrary.getElementDeclaration(element);
  return declaration?.node;
}

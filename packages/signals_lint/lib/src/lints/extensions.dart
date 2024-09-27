import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:signals_lint/src/lints/definitions.dart';

extension AstNodeX on AstNode {
  bool withinBuild() => _isWidgetMember && _isBuildMember;

  bool get _isBuildMember =>
      thisOrAncestorOfType<MethodDeclaration>()?.name.lexeme == buildMethodName;

  bool get _isWidgetMember =>
      thisOrAncestorOfType<ClassDeclaration>()
          ?.extendsClause
          ?.superclass
          .type
          ?.isWidgetClass() ??
      false;
}

extension TypeX on DartType {
  bool get isSignal =>
      signalTypes.any((checker) => checker.isAssignableFromType(this));

  bool isWidgetClass() =>
      widgetClasses.any((checker) => checker.isAssignableFromType(this));
}

extension CS on ConstructorDeclaration {
  bool get isSignal => signalTypes.any(
      (checker) => checker.isAssignableFromType(declaredElement!.returnType));
}

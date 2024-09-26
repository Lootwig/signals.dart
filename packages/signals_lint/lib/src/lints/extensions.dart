import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:collection/collection.dart';
import 'package:signals_lint/src/lints/definitions.dart';

extension AstNodeX on AstNode {
  bool createsSignal() {
    if (this
        case InstanceCreationExpression(staticType: DartType(isSignal: true))) {
      return true;
    }
    return false;
  }

  /*bool isIdentifierCreatedInBuild() {
    if (this case DeclaredIdentifier(:final Element declaredElement)) {
      return declaredElement.isInsideBuild();
    }
    return false;
  }*/

  bool isWidgetBuild() => _isWidgetMember && _isBuildMember;

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

extension CheckSignal on Expression {
  bool get isSignal => staticType?.isSignal ?? false;
}

extension ElementX on Element {
  bool isInsideBuild() {
    final ancestor =
        thisOrAncestorMatching((element) => element.isWidgetBuildMethod());
    return ancestor != null;
  }

  bool isWidgetBuildMethod() {
    if (this case MethodElement(name: buildMethodName)) {
      final widgetParent = enclosingElement?.thisOrAncestorMatching(
          (element) => element._isElementWidgetClass());
      return widgetParent != null;
    }
    return false;
  }

  bool _isElementWidgetClass() =>
      widgetClasses.any((checker) => checker.isAssignableFrom(this));
}

extension ConstructorX on ConstructorElement {
  bool get extendsSignal => readonlySignal.isSuperTypeOf(returnType);
}

extension I<T> on Iterable<Iterable<T>> {
  Iterable<Iterable<T>> whereNotEmpty() =>
      whereNot((element) => element.isEmpty);
}

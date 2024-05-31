import 'package:custom_lint_builder/custom_lint_builder.dart';
import 'package:mio/src/rules/header.dart';

PluginBase createPlugin() => _MioLinter();

class _MioLinter extends PluginBase {
  @override
  List<LintRule> getLintRules(CustomLintConfigs configs) => [
        HeaderLintRule(
          filePath: configs.rules['mio_header']?.json['file'] as String?,
          text: configs.rules['mio_header']?.json['text'] as String?,
          templates: configs.rules['mio_header']?.json['templates']
              as Map,
        ),
      ];
}
